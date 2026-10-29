# shellcheck shell=bash
# Summary: Show the CI status of a commit.
# Usage: hub ci-status [-v] [COMMIT]
#
# Prints one word for COMMIT (default HEAD): the most severe state among its
# commit statuses and check runs, in this order
#
#   error, failure, action_required, timed_out, cancelled, pending, success, neutral
#
# or "no status" when it has none. A check run that hasn't completed counts
# as pending; other states, such as skipped, are ignored. The exit code says
# the same:
#
#   0  success or neutral
#   1  error, failure, action_required, timed_out or cancelled
#   2  pending
#   3  no status
#
# COMMIT is resolved locally when possible (a local branch means its local
# tip); anything else is resolved by GitHub. The repository is the one hub
# uses everywhere (its upstream, github or origin remote, or GH_REPO), named
# explicitly to gh along with its host, so `gh repo set-default` and gh's
# default host don't come into it. The two lookups are read-only `gh api`
# calls to repos/OWNER/REPO/commits/SHA/status and .../check-runs.
#
# When GitHub refuses the check runs with HTTP 403, 404 or 422 (a token that
# may not read checks, an older GitHub Enterprise Server), only the commit
# statuses count, as in old hub; any other error, a rate limit included, is
# an error.
#
#   -v, --verbose   Print one line per check instead, failures first:
#                   STATE, NAME and URL, separated by tabs.
#
# For the head commit of a pull request, `gh pr checks` is the richer
# alternative: it can wait for the checks (--watch), show only required ones
# (--required) and print JSON. Its exit codes differ: pending is 8, and
# cancelled checks don't count as failures.
#
#   $ hub ci-status
#   success
#   $ hub ci-status -v main
#   failure   lint    https://github.com/OWNER/REPO/actions/runs/1/job/2
#   success   build   https://github.com/OWNER/REPO/actions/runs/1/job/3

hub_cmd_ci_status() {
  local verbose=0 ref='' arg
  while (($#)); do
    arg=$1
    shift
    case $arg in
      -h | --help) hub::usage ;;
      -v | --verbose) verbose=1 ;;
      -*) hub::die "Aborted: unknown option '$arg'. Usage: hub ci-status [-v] [COMMIT]" ;;
      *)
        [[ -z $ref ]] || hub::die "Aborted: give at most one COMMIT. Usage: hub ci-status [-v] [COMMIT]"
        ref=$arg
        ;;
    esac
  done
  [[ -n ${GH_REPO:-} ]] || hub::require_repo
  local proj host
  proj=$(hub::main_project && printf '%s\n' "$HUB_PROJECT_HOST") || exit 1 # dies without a GitHub remote
  host=${proj##*$'\n'} proj=${proj%%$'\n'*}

  local sha
  sha=$(hub::git_query rev-parse -q --verify "${ref:-HEAD}^{commit}") || sha=${ref:-HEAD}

  # Always name the host: gh's default is GH_HOST, or the only host it is logged in to.
  local -a api=(api --hostname "$host" --paginate)
  local status_jq check_jq
  if ((verbose)); then
    status_jq='.statuses[] | [.state, .context, .target_url // ""] | @tsv'
    check_jq='.check_runs[] | [(if .status == "completed" then .conclusion else "pending" end), .name, .html_url // ""] | @tsv'
  else
    status_jq='.statuses[].state'
    check_jq='.check_runs[] | if .status == "completed" then .conclusion else "pending" end'
  fi
  local statuses checks
  statuses=$(hub::gh_query "${api[@]}" "repos/$proj/commits/$sha/status" --jq "$status_jq") || exit
  checks=$(_hub_ci_status_check_runs "${api[@]}" "repos/$proj/commits/$sha/check-runs" --jq "$check_jq") || exit

  # Each line starts with a state (followed by a tab and more columns with -v).
  local -a lines=()
  local line states=$'\n'
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    lines+=("$line")
    states+=${line%%$'\t'*}$'\n'
  done <<<"$statuses"$'\n'"$checks"

  local state='no status' candidate
  for candidate in error failure action_required timed_out cancelled pending success neutral; do
    if [[ $states == *$'\n'"$candidate"$'\n'* ]]; then
      state=$candidate
      break
    fi
  done

  if ((verbose && ${#lines[@]})); then
    local rank
    for line in "${lines[@]}"; do
      case ${line%%$'\t'*} in
        error | failure | action_required | timed_out | cancelled) rank=1 ;;
        success | neutral) rank=3 ;;
        *) rank=2 ;;
      esac
      printf '%s\t%s\n' "$rank" "$line"
    done | LC_ALL=C sort -t $'\t' -k1,1n -k3,3f | cut -f2-
  else
    printf '%s\n' "$state"
  fi

  case $state in
    success | neutral) return 0 ;;
    pending) return 2 ;;
    'no status') return 3 ;;
    *) return 1 ;;
  esac
}

# _hub_ci_status_check_runs GH-ARGS... : print the output of the check-runs lookup `gh GH-ARGS`.
# If gh fails in a way _hub_ci_status_tolerated accepts, print nothing and succeed.
_hub_ci_status_check_runs() {
  local err rc=0
  # gh's stdout is held back until gh has succeeded (after an HTTP error it is the error
  # document) and then printed to fd 4, our stdout; its stderr goes to fd 3, captured in err.
  { err=$({ out=$(hub::gh_query "$@" 2>&3) && printf '%s\n' "$out" >&4; } 3>&1); } 4>&1 || rc=$?
  if ((rc)) && _hub_ci_status_tolerated "$err"; then
    # Go on with the commit statuses alone, as old hub did; say so only under HUB_VERBOSE.
    if [[ -n ${HUB_VERBOSE:-} ]]; then printf '%s\n' "$err" >&2; fi
    hub::debug "no check runs; counting the commit statuses only"
    return 0
  fi
  [[ -z $err ]] || printf '%s\n' "$err" >&2
  return "$rc"
}

# _hub_ci_status_tolerated GH-STDERR : true when gh's error output says GitHub refused the
# check runs with HTTP 403, 404 or 422, as restricted tokens and older Enterprise servers do:
# a line "gh: MESSAGE (HTTP 404)" or "gh: HTTP 404". A rate limit (also a 403) is not tolerated.
_hub_ci_status_tolerated() {
  local line re='^gh: (.* \()?HTTP (403|404|422)\)?$'
  [[ ${1,,} != *"rate limit"* ]] || return 1
  while IFS= read -r line; do
    [[ $line =~ $re ]] && return 0
  done <<<"$1"
  return 1
}
