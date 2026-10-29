# shellcheck shell=bash
# Summary: List, view, create and update issues (gh issue).
# Usage: hub issue [SUBCOMMAND] [gh issue options]
#
# Runs `gh issue` with gh's own options and behaviour. hub only maps the old
# subcommand names and argument forms that gh doesn't have:
#
#   hub issue [OPTIONS]             gh issue list [OPTIONS]
#   hub issue show NUMBER           gh issue view NUMBER
#   hub issue labels                gh label list
#   hub issue create -m MESSAGE     gh issue create --title TITLE --body BODY: the
#                                   first paragraph is the title and the rest the
#                                   body (empty if there is none, so gh doesn't
#                                   prompt). Repeat -m to add paragraphs. gh's own
#                                   -m is still there as --milestone.
#   hub issue create -F FILE        The same, read from FILE ("-" for stdin). gh's
#                                   body-only -F is still there as --body-file.
#   hub issue update NUMBER ...     gh issue edit NUMBER ...
#   hub issue update NUMBER -s closed|open
#                                   gh issue close|reopen NUMBER, which also gets
#                                   -c COMMENT, -r REASON and --duplicate-of. Any
#                                   other options go to gh issue edit first.
#
# Everything else goes to gh unchanged: the other subcommands (list, transfer,
# close, comment, develop, ...) and all other options, in order. See
# `gh issue SUBCOMMAND --help` for them.
#
#   $ hub issue create -m "Crash on start" -m "Steps to reproduce: ..." -l bug
#   > gh issue create --title "Crash on start" --body "Steps to reproduce: ..." -l bug
#
#   $ hub issue update 12 -s closed -c "Fixed in #13"
#   > gh issue close 12 -c "Fixed in #13"

hub_cmd_issue() {
  case ${1-} in -h | --help) hub::usage ;; esac
  # Like gh, take -R/--repo before the subcommand word (hub issue -R OWNER/REPO create ...).
  local -a repo=()
  while (($#)); do
    case $1 in
      -R | --repo)
        (($# > 1)) || break
        repo+=("$1" "$2")
        shift 2
        ;;
      -R?* | --repo=*)
        repo+=("$1")
        shift
        ;;
      *) break ;;
    esac
  done
  local sub=list
  if (($#)) && [[ $1 != -* ]]; then
    sub=$1
    shift
  fi
  case $sub in
    show) hub::exec_gh issue view "${repo[@]}" "$@" ;;
    labels) hub::exec_gh label list "${repo[@]}" "$@" ;;
    create) _hub_issue_create "${repo[@]}" "$@" ;;
    update) _hub_issue_update "${repo[@]}" "$@" ;;
    *) hub::exec_gh issue "$sub" "${repo[@]}" "$@" ;;
  esac
}

# _hub_issue_create ARGS... : gh issue create, with hub's -m/--message and
# -F/--file turned into --title/--body where the first of them appeared.
_hub_issue_create() {
  local -a args=() messages=() title=()
  local opt val n file='' at=-1 has_body=0
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[abFlmptRT]?*) opt=${1:0:2} val=${1:2} ;;
      -[abFlmptRT] | --message | --file | --assignee | --attach | --blocked-by | --blocking | --body | --body-file | \
        --label | --milestone | --parent | --project | --recover | --template | --title | --type | --repo)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        val=$2 n=2
        ;;
    esac
    case $opt in
      -h | --help) hub::usage ;;
      -m | --message)
        messages+=("$val")
        ((at >= 0)) || at=${#args[@]}
        ;;
      -F | --file)
        file=$val
        ((at >= 0)) || at=${#args[@]}
        ;;
      -b | --body | --body-file | -T | --template)
        has_body=1
        args+=("${@:1:n}")
        ;;
      *) args+=("${@:1:n}") ;;
    esac
    shift "$n"
  done
  if ((at >= 0)); then
    _hub_issue_message "$file" "${messages[@]}"
    title=(--title "$HUB_MSG_TITLE")
    if [[ -n $HUB_MSG_BODY ]] || ((! has_body)); then title+=(--body "$HUB_MSG_BODY"); fi
    args=("${args[@]:0:at}" "${title[@]}" "${args[@]:at}")
  fi
  hub::exec_gh issue create "${args[@]}"
}

# _hub_issue_message FILE [MESSAGE...] : set HUB_MSG_TITLE and HUB_MSG_BODY from the
# -m MESSAGEs (joined as paragraphs) or else from FILE ("-" reads standard input).
_hub_issue_message() {
  local file=$1 text
  shift
  if [[ -n $file ]]; then
    (($# == 0)) || hub::die "Aborted: -m and -F cannot be used together."
    if [[ $file == - ]]; then
      text=$(cat)
    else
      [[ -r $file && ! -d $file ]] || hub::die "Aborted: cannot read $file"
      text=$(<"$file")
    fi
  else
    text=$(printf '%s\n\n' "$@")
  fi
  hub::split_message "$text"
}

# _hub_issue_update ARGS... : gh issue edit, unless -s/--state asks for gh issue
# close or reopen; then the other options, if any, go to gh issue edit first.
_hub_issue_update() {
  local -a args=("$@") edit=() state_args=() repo=()
  local opt val n state='' number=''
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        edit+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[bcFmrRst]?*) opt=${1:0:2} val=${1:2} ;;
      -[bcFmrRst] | --state | --comment | --reason | --duplicate-of | --repo | --title | --body | --body-file | \
        --milestone | --type | --parent | --attach | --add-assignee | --remove-assignee | --add-label | --remove-label | \
        --add-project | --remove-project | --add-blocked-by | --remove-blocked-by | --add-blocking | --remove-blocking | \
        --add-sub-issue | --remove-sub-issue)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        val=$2 n=2
        ;;
    esac
    case $opt in
      -h | --help) hub::usage ;;
      -s | --state) state=$val ;;
      -c | --comment | -r | --reason | --duplicate-of) state_args+=("${@:1:n}") ;;
      -R | --repo) repo+=("${@:1:n}") ;;
      -?*) edit+=("${@:1:n}") ;;
      *) if [[ -z $number ]]; then number=$1; else edit+=("$1"); fi ;;
    esac
    shift "$n"
  done
  [[ -n $state ]] || hub::exec_gh issue edit "${args[@]}"
  local sub
  case ${state,,} in
    closed) sub=close ;;
    open) sub=reopen ;;
    *) hub::die "Aborted: --state must be open or closed, not '$state'." ;;
  esac
  [[ -n $number ]] || hub::die "Usage: hub issue update NUMBER [-s open|closed] [gh issue edit options]"
  if ((${#edit[@]})); then
    hub::gh issue edit "$number" "${repo[@]}" "${edit[@]}" || exit
  fi
  hub::exec_gh issue "$sub" "$number" "${repo[@]}" "${state_args[@]}"
}
