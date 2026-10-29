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
#                                   or URL, with no -r or -r duplicate), which
#                                   must not be one of the NUMBERs; reopening
#                                   doesn't, so -s open with them is an error.
#                                   Any other options go to one gh issue edit
#                                   first. hub checks everything before it runs
#                                   gh, and stops at the first gh command that
#                                   fails.
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
      -[abFlmptRT]?*)
        opt=${1:0:2} val=${1:2}
        [[ $val != =?* ]] || val=${val:1} # gh reads -X=VALUE as -X VALUE
        ;;
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
  local opt val n state='' has_state=0 file='' at=-1 close_only='' repo_name='' reason duplicate
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        shift
        numbers+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[bcFmrRst]?*)
        opt=${1:0:2} val=${1:2}
        [[ $val != =?* ]] || val=${val:1} # gh reads -X=VALUE as -X VALUE
        ;;
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
      -R | --repo) repo+=("${@:1:n}") repo_name=$val ;; # gh takes the last
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
    for duplicate in "${duplicates[@]}"; do
      _hub_issue_parse "$duplicate" \
        || hub::die "Aborted: --duplicate-of must be an issue number or URL, not '$duplicate'."
    done
    if ((${#duplicates[@]} && ${#reasons[@]})) && [[ ${reasons[-1]} != duplicate ]]; then
      hub::die "Aborted: --duplicate-of only goes with --reason duplicate, not with --reason '${reasons[-1]}'."
    fi
    # gh takes the last --duplicate-of.
    if ((${#duplicates[@]})); then _hub_issue_not_itself "${duplicates[-1]}" "$repo_name" "${numbers[@]}"; fi
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

# _hub_issue_not_itself ISSUE REPO NUMBER... : die if ISSUE (the --duplicate-of value) is one of
# the NUMBERs being closed. As in gh issue close, a bare ISSUE number is in the closed issue's
# repository: its URL's, else REPO (the -R value) or, without one, hub's current project. When
# hub cannot tell that repository, it leaves the check to gh.
_hub_issue_not_itself() {
  local dup=$1 repo_name=$2 dup_repo dup_number number closed here=''
  shift 2
  _hub_issue_parse "$dup" || return 0
  dup_repo=$HUB_ISSUE_REPO dup_number=$HUB_ISSUE_NUMBER
  for number; do
    if ! _hub_issue_parse "$number" || [[ $HUB_ISSUE_NUMBER != "$dup_number" ]]; then continue; fi
    closed=$HUB_ISSUE_REPO
    if [[ -n $dup_repo ]]; then
      if [[ -z $closed ]]; then
        [[ -n $here ]] || here=$(_hub_issue_repo "$repo_name") || here=-
        closed=$here
      fi
      [[ $closed == "$dup_repo" ]] || continue
    fi
    hub::die "Aborted: issue $number cannot be closed as a duplicate of itself (--duplicate-of $dup)."
  done
  return 0
}

# _hub_issue_parse ISSUE : read ISSUE as gh does: NUMBER, #NUMBER or an issue or pull request URL.
# Sets HUB_ISSUE_NUMBER (without leading zeros) and HUB_ISSUE_REPO (the URL's HOST/OWNER/REPO,
# lowercased; empty for a bare number). Fails for anything else.
_hub_issue_parse() {
  local host
  HUB_ISSUE_NUMBER='' HUB_ISSUE_REPO=''
  if [[ $1 =~ ^#?([0-9]+)$ ]]; then
    HUB_ISSUE_NUMBER=${BASH_REMATCH[1]}
  elif [[ $1 =~ ^https?://([^/?#]+)/([^/?#]+)/([^/?#]+)/(issues|pull)/([0-9]+)([/?#].*)?$ ]]; then
    HUB_ISSUE_NUMBER=${BASH_REMATCH[5]}
    host=${BASH_REMATCH[1],,}
    host=${host##*@}
    host=${host%:*}
    HUB_ISSUE_REPO=${host#www.}/${BASH_REMATCH[2],,}/${BASH_REMATCH[3],,}
  else
    return 1
  fi
  while [[ $HUB_ISSUE_NUMBER == 0?* ]]; do HUB_ISSUE_NUMBER=${HUB_ISSUE_NUMBER#0}; done
}

# _hub_issue_repo [REPO] : print HOST/OWNER/REPO, lowercased, of REPO (-R's [HOST/]OWNER/REPO or
# URL), or else of hub's current project (GH_REPO, else the main remote). Fails if there is none.
_hub_issue_repo() {
  local out
  if [[ -z ${1-} ]]; then
    out=$(hub::main_project 2>/dev/null && printf '%s\n' "$HUB_PROJECT_HOST") || return 1
    out=${out#*$'\n'}/${out%%$'\n'*}
  elif hub::parse_remote_url "$1"; then
    out=$HUB_URL_HOST/$HUB_URL_OWNER/$HUB_URL_REPO
  elif [[ $1 =~ ^[^/]+/[^/]+/[^/]+$ ]]; then
    out=$1
  elif [[ $1 =~ ^[^/]+/[^/]+$ ]]; then
    out=$(hub::host)/$1
  else
    return 1
  fi
  out=${out,,}
  printf '%s\n' "${out#www.}"
}
