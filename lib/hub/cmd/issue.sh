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
#   hub issue update NUMBER... [OPTIONS]
#                                   gh issue edit NUMBER... [OPTIONS].
#   hub issue update NUMBER... -m MESSAGE | -F FILE
#                                   --title and --body as for create, except that
#                                   an empty body is left out, so the issue keeps
#                                   its body (gh's --body '' clears it). gh's -m
#                                   and -F are still there as --milestone and
#                                   --body-file.
#   hub issue update NUMBER... -s closed|open
#                                   gh issue close|reopen NUMBER for each NUMBER
#                                   in turn, with -c COMMENT. Closing also takes
#                                   -r REASON (completed, "not planned" or
#                                   duplicate) and --duplicate-of ISSUE (a number
#                                   or URL, with no -r or -r duplicate);
#                                   reopening doesn't, so -s open with them is an
#                                   error. Any other options go to one gh issue
#                                   edit first. hub checks everything before it
#                                   runs gh, and stops at the first gh command
#                                   that fails.
#
# hub 2.x's update -l LABELS and -a USERS replaced the whole set; gh issue edit
# has no such options and refuses them. Use --add-label and --remove-label
# (--add-assignee and --remove-assignee for users) instead.
#
# Everything else goes to gh unchanged: the other subcommands (list, transfer,
# close, comment, develop, ...) and all other options, in order. See
# `gh issue SUBCOMMAND --help` for them.
#
#   $ hub issue create -m "Crash on start" -m "Steps to reproduce: ..." -l bug
#   > gh issue create --title "Crash on start" --body "Steps to reproduce: ..." -l bug
#
#   $ hub issue update 12 -m "Crash on start" --add-label bug
#   > gh issue edit 12 --title "Crash on start" --add-label bug
#
#   $ hub issue update 12 13 -s closed -c "Fixed in #14"
#   > gh issue close 12 -c "Fixed in #14"
#   > gh issue close 13 -c "Fixed in #14"

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

# _hub_issue_update ARGS... : gh issue edit NUMBER..., with hub's -m/--message and
# -F/--file turned into --title/--body where the first of them appeared. With
# -s/--state, the other options (if any) go to gh issue edit first, then gh issue
# close or reopen runs once per NUMBER. Everything is checked before gh runs.
_hub_issue_update() {
  local -a numbers=() edit=() state_args=() repo=() messages=() title=() reasons=() duplicates=()
  local opt val n state='' has_state=0 file='' at=-1 close_only='' reason duplicate
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        shift
        numbers+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[bcFmrRst]?*) opt=${1:0:2} val=${1:2} ;;
      -[bcFmrRst] | --state | --message | --file | --comment | --reason | --duplicate-of | --repo | --title | --body | \
        --body-file | --milestone | --type | --parent | --attach | --add-assignee | --remove-assignee | --add-label | \
        --remove-label | --add-project | --remove-project | --add-blocked-by | --remove-blocked-by | --add-blocking | \
        --remove-blocking | --add-sub-issue | --remove-sub-issue)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        val=$2 n=2
        ;;
    esac
    case $opt in
      -h | --help) hub::usage ;;
      -s | --state) state=$val has_state=1 ;;
      -m | --message)
        messages+=("$val")
        ((at >= 0)) || at=${#edit[@]}
        ;;
      -F | --file)
        file=$val
        ((at >= 0)) || at=${#edit[@]}
        ;;
      -c | --comment) state_args+=("${@:1:n}") ;;
      -r | --reason)
        state_args+=("${@:1:n}")
        reasons+=("$val")
        close_only=$opt
        ;;
      --duplicate-of)
        state_args+=("${@:1:n}")
        duplicates+=("$val")
        close_only=$opt
        ;;
      -R | --repo) repo+=("${@:1:n}") ;;
      -?*) edit+=("${@:1:n}") ;;
      *) numbers+=("$1") ;;
    esac
    shift "$n"
  done
  local sub=''
  if ((has_state)); then
    case ${state,,} in
      closed) sub=close ;;
      open) sub=reopen ;;
      *) hub::die "Aborted: --state must be open or closed, not '$state'." ;;
    esac
    [[ $sub == close || -z $close_only ]] \
      || hub::die "Aborted: $close_only only goes with -s closed; gh issue reopen has no such option."
  fi
  # gh issue close checks these itself, but only once gh issue edit has already run.
  if [[ $sub == close ]]; then
    for reason in "${reasons[@]}"; do
      case $reason in
        completed | 'not planned' | duplicate) ;;
        *) hub::die "Aborted: --reason must be 'completed', 'not planned' or 'duplicate', not '$reason'." ;;
      esac
    done
    local number_re='^#?[0-9]+$' url_re='^https?://[^/?#]+/[^/?#]+/[^/?#]+/(issues|pull)/[0-9]+([/?#].*)?$'
    for duplicate in "${duplicates[@]}"; do
      [[ $duplicate =~ $number_re || $duplicate =~ $url_re ]] \
        || hub::die "Aborted: --duplicate-of must be an issue number or URL, not '$duplicate'."
    done
    if ((${#duplicates[@]} && ${#reasons[@]})) && [[ ${reasons[-1]} != duplicate ]]; then
      hub::die "Aborted: --duplicate-of only goes with --reason duplicate, not with --reason '${reasons[-1]}'."
    fi
  fi
  ((${#numbers[@]})) || hub::die "Usage: hub issue update NUMBER... [-s open|closed] [-m MESSAGE | -F FILE] [gh issue edit options]"
  if ((at >= 0)); then
    _hub_issue_message "$file" "${messages[@]}"
    title=(--title "$HUB_MSG_TITLE")
    [[ -z $HUB_MSG_BODY ]] || title+=(--body "$HUB_MSG_BODY") # an empty body would clear the issue's
    edit=("${edit[@]:0:at}" "${title[@]}" "${edit[@]:at}")
  fi
  # Without -s, -c/-r/--duplicate-of are gh issue edit's to accept or refuse.
  [[ -n $sub ]] || hub::exec_gh issue edit "${numbers[@]}" "${repo[@]}" "${edit[@]}" "${state_args[@]}"
  if ((${#edit[@]})); then
    hub::gh issue edit "${numbers[@]}" "${repo[@]}" "${edit[@]}" || exit
  fi
  local i last=$((${#numbers[@]} - 1))
  for ((i = 0; i < last; i++)); do
    hub::gh issue "$sub" "${numbers[i]}" "${repo[@]}" "${state_args[@]}" || exit
  done
  hub::exec_gh issue "$sub" "${numbers[last]}" "${repo[@]}" "${state_args[@]}"
}
