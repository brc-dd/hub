# shellcheck shell=bash
# Summary: List, view, create and update issues (gh issue).
# Usage: hub issue [-R REPO] [SUBCOMMAND] [gh issue options]
#
#   hub issue [OPTIONS]                   gh issue list [OPTIONS]
#   hub issue show NUMBER                 gh issue view NUMBER
#   hub issue labels                      gh label list
#   hub issue create -m MESSAGE           gh issue create --title TITLE --body BODY
#   hub issue update NUMBER... OPTIONS    gh issue edit NUMBER... OPTIONS
#   hub issue update NUMBER... -s STATE   gh issue close|reopen NUMBER, for each NUMBER
#
# Options:
#   -m, --message MESSAGE   The title, then the body after a blank line; repeat -m to add paragraphs.
#   -F, --file FILE         The same as -m, read from FILE ("-" for standard input).
#   -s, --state STATE       update: closed or open; any other changes are made first.
#   -c, --comment TEXT      update -s: comment when closing or reopening.
#   -r, --reason REASON     update -s closed: completed, "not planned" or duplicate.
#   --duplicate-of ISSUE    update -s closed: the issue, a number or URL, they duplicate.
#
# gh's own -m and -F are --milestone and --body-file. create sends an empty body rather than let
# gh prompt; update leaves it out, so the issue keeps its own. hub checks -s, -r and --duplicate-of
# before it runs gh, and stops at the first gh command that fails. Other subcommands and options
# go to gh unchanged.
#
#   $ hub issue update 12 13 -s closed -c "Fixed in #14"
#   > gh issue close 12 -c "Fixed in #14"
#   > gh issue close 13 -c "Fixed in #14"

hub_cmd_issue() {
  case ${1-} in -h | --help) hub::usage ;; esac
  local -a repo=()
  local n
  while [[ ${1-} == -R* || ${1-} == --repo || ${1-} == --repo=* ]]; do # gh takes -R before the subcommand too
    n=1
    [[ $1 != -R && $1 != --repo ]] || n=2
    (($# >= n)) || break
    repo+=("${@:1:n}")
    shift "$n"
  done
  [[ ${1--} == -* ]] && set -- list "$@"
  local sub=$1
  shift
  case $sub in
    show) hub::exec_gh issue view "${repo[@]}" "$@" ;;
    labels) hub::exec_gh label list "${repo[@]}" "$@" ;;
    create | update) "_hub_issue_$sub" "${repo[@]}" "$@" ;;
    *) hub::exec_gh issue "$sub" "${repo[@]}" "$@" ;;
  esac
}

_hub_issue_create() {
  local -a args=() messages=() title=()
  local opt val n file='' at='' body=1
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[abFlmptRT]=?*) opt=${1:0:2} val=${1:3} ;; # gh reads -X=VALUE as -X VALUE
      -[abFlmptRT]?*) opt=${1:0:2} val=${1:2} ;;
      -[abFlmptRT] | --message | --file | --assignee | --attach | --blocked-by | --blocking | --body | --body-file | \
        --label | --milestone | --parent | --project | --recover | --template | --title | --type | --repo)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        val=$2 n=2
        ;;
    esac
    case $opt in
      -h | --help) hub::usage ;;
      -m | --message) messages+=("$val") at=${at:-${#args[@]}} ;;
      -F | --file) file=$val at=${at:-${#args[@]}} ;;
      -b | --body | --body-file | -T | --template) body=0 args+=("${@:1:n}") ;;
      *) args+=("${@:1:n}") ;;
    esac
    shift "$n"
  done
  if [[ -n $at ]]; then
    hub::message "$file" "${messages[@]}"
    title=(--title "$HUB_MSG_TITLE")
    if [[ -n $HUB_MSG_BODY ]] || ((body)); then title+=(--body "$HUB_MSG_BODY"); fi
    args=("${args[@]:0:at}" "${title[@]}" "${args[@]:at}")
  fi
  hub::exec_gh issue create "${args[@]}"
}

_hub_issue_update() {
  local -a numbers=() edit=() close=() repo=() messages=() reasons=() title=()
  local opt val n sub='' file='' at='' only='' base='' dup=''
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        shift
        numbers+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[bcFmrRst]=?*) opt=${1:0:2} val=${1:3} ;; # gh reads -X=VALUE as -X VALUE
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
      -s | --state)
        case ${val,,} in
          closed) sub=close ;;
          open) sub=reopen ;;
          *) hub::die "Aborted: --state must be open or closed, not '$val'." ;;
        esac
        ;;
      -m | --message) messages+=("$val") at=${at:-${#edit[@]}} ;;
      -F | --file) file=$val at=${at:-${#edit[@]}} ;;
      -c | --comment) close+=("${@:1:n}") ;;
      -r | --reason) close+=("${@:1:n}") reasons+=("$val") only=$opt ;;
      --duplicate-of) close+=("${@:1:n}") dup=$val only=$opt ;; # gh takes the last
      -R | --repo) repo+=("${@:1:n}") base=$val ;;
      -?*) edit+=("${@:1:n}") ;;
      *) numbers+=("$1") ;;
    esac
    shift "$n"
  done
  # gh issue close checks these too, but only after gh issue edit or an earlier close has run.
  [[ $sub != reopen || -z $only ]] || hub::die "Aborted: $only only goes with -s closed; gh issue reopen has no such option."
  if [[ $sub == close ]]; then
    for val in "${reasons[@]}"; do
      case $val in
        completed | 'not planned' | duplicate) ;;
        *) hub::die "Aborted: --reason must be 'completed', 'not planned' or 'duplicate', not '$val'." ;;
      esac
    done
    if [[ -n $dup ]]; then
      _hub_issue_parse "$dup" || hub::die "Aborted: --duplicate-of must be an issue number or URL, not '$dup'."
      if ((${#reasons[@]})) && [[ ${reasons[-1]} != duplicate ]]; then
        hub::die "Aborted: --duplicate-of only goes with --reason duplicate, not with --reason '${reasons[-1]}'."
      fi
      _hub_issue_not_itself "$dup" "$base" "${numbers[@]}"
    fi
  fi
  ((${#numbers[@]})) || hub::die "Usage: hub issue update NUMBER... [-s open|closed] [-m MESSAGE | -F FILE] [gh issue edit options]"
  if [[ -n $at ]]; then
    hub::message "$file" "${messages[@]}"
    title=(--title "$HUB_MSG_TITLE")
    [[ -z $HUB_MSG_BODY ]] || title+=(--body "$HUB_MSG_BODY") # gh's --body '' would clear it
    edit=("${edit[@]:0:at}" "${title[@]}" "${edit[@]:at}")
  fi
  [[ -n $sub ]] || hub::exec_gh issue edit "${numbers[@]}" "${repo[@]}" "${edit[@]}" "${close[@]}"
  if ((${#edit[@]})); then hub::gh issue edit "${numbers[@]}" "${repo[@]}" "${edit[@]}" || exit; fi
  for val in "${numbers[@]}"; do
    hub::gh issue "$sub" "$val" "${repo[@]}" "${close[@]}" || exit
  done
}

_hub_issue_not_itself() {
  local dup=$1 base=$2 dup_repo dup_number here='' number
  shift 2
  _hub_issue_parse "$dup"
  dup_repo=$HUB_ISSUE_REPO dup_number=$HUB_ISSUE_NUMBER
  # As in gh, a bare number is in the closed issue's repository: -R's, GH_REPO's or the main remote's.
  if [[ -n $dup_repo ]] && { [[ -n $base || -n ${GH_REPO:-} ]] || hub::main_remote >/dev/null; }; then
    GH_REPO=${base:-${GH_REPO:-}} hub::main_project >/dev/null
    here=${HUB_PROJECT_HOST,,}/${HUB_PROJECT,,}
  fi
  for number; do
    if _hub_issue_parse "$number" && ((HUB_ISSUE_NUMBER == dup_number)) \
      && [[ -z $dup_repo || ${HUB_ISSUE_REPO:-$here} == "$dup_repo" ]]; then
      hub::die "Aborted: issue $number cannot be closed as a duplicate of itself (--duplicate-of $dup)."
    fi
  done
}

_hub_issue_parse() { # ISSUE : HUB_ISSUE_NUMBER, and HUB_ISSUE_REPO (host/owner/repo) for a URL
  HUB_ISSUE_REPO=''
  if [[ $1 =~ ^#?([0-9]+)$ ]]; then
    HUB_ISSUE_NUMBER=$((10#${BASH_REMATCH[1]}))
  elif [[ ${1,,} =~ ^https?://(www\.)?([^/?#]+/[^/?#]+/[^/?#]+)/(issues|pull)/([0-9]+)([/?#].*)?$ ]]; then
    HUB_ISSUE_REPO=${BASH_REMATCH[2]} HUB_ISSUE_NUMBER=$((10#${BASH_REMATCH[4]}))
  else
    return 1
  fi
}
