# shellcheck shell=bash
# Summary: Show the CI status of a commit.
# Usage: hub ci-status [-v] [COMMIT]
#
# Prints the most severe state among the commit statuses and check runs of COMMIT (default HEAD):
# error, failure, action_required, timed_out, cancelled, pending, success or neutral, else
# "no status". A check run that has not completed is pending; other states, such as skipped, are
# ignored. The repository is the current project (GH_REPO, else the upstream, github or origin
# remote), named to gh with its host. When GitHub refuses the check runs with HTTP 403, 404 or
# 422, the commit statuses alone count. For a pull request, `gh pr checks` has more to offer.
#
# Options:
#   -v, --verbose   Print STATE, NAME and URL for every check instead, failures first.
#
# Exit status: 0 for success or neutral, 1 for a failure state, 2 for pending, 3 for no status.
#
#   $ hub ci-status -v main
#   failure   lint    https://github.com/OWNER/REPO/actions/runs/1/job/2
#   success   build   https://github.com/OWNER/REPO/actions/runs/1/job/3

hub_cmd_ci_status() {
  local verbose=0 ref='' sha path statuses checks states state line
  local -a lines api
  while (($#)); do
    case $1 in
      -h | --help) hub::usage ;;
      -v | --verbose) verbose=1 ;;
      -*) hub::die "Aborted: unknown option '$1'. Usage: hub ci-status [-v] [COMMIT]" ;;
      *)
        [[ -z $ref ]] || hub::die "Aborted: give at most one COMMIT. Usage: hub ci-status [-v] [COMMIT]"
        ref=$1
        ;;
    esac
    shift
  done
  hub::main_project >/dev/null
  sha=$(hub::git_query rev-parse -q --verify "${ref:-HEAD}^{commit}") || sha=${ref:-HEAD}
  path=repos/$HUB_PROJECT/commits/$sha
  api=(api --hostname "$HUB_PROJECT_HOST" --paginate)
  statuses=$(hub::gh_query "${api[@]}" "$path/status" --jq '.statuses[] | [.state, .context, .target_url // ""] | @tsv') || exit
  checks=$(_hub_ci_status_check_runs "${api[@]}" "$path/check-runs" \
    --jq '.check_runs[] | [(if .status == "completed" then .conclusion else "pending" end), .name, .html_url // ""] | @tsv') || exit

  mapfile -t lines < <(printf '%s\n%s\n' "$statuses" "$checks" | grep .)
  states=$'\n'$(printf '%s\n' "${lines[@]%%$'\t'*}")$'\n'
  for state in error failure action_required timed_out cancelled pending success neutral 'no status'; do
    [[ $states != *$'\n'"$state"$'\n'* ]] || break
  done
  if ((verbose && ${#lines[@]})); then
    for line in "${lines[@]}"; do
      case ${line%%$'\t'*} in
        error | failure | action_required | timed_out | cancelled) printf '1\t%s\n' "$line" ;;
        success | neutral) printf '3\t%s\n' "$line" ;;
        *) printf '2\t%s\n' "$line" ;;
      esac
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

_hub_ci_status_check_runs() {
  local err rc=0
  # gh prints the error document on stdout: pass stdout on (to fd 4) only once gh has succeeded.
  { err=$({ out=$(hub::gh_query "$@" 2>&3) && printf '%s\n' "$out" >&4; } 3>&1); } 4>&1 || rc=$?
  if ((rc)) && _hub_ci_status_tolerated "$err"; then
    [[ -z ${HUB_VERBOSE:-} ]] || printf '%s\n' "$err" >&2
    hub::debug "no check runs; counting the commit statuses only"
    return 0
  fi
  [[ -z $err ]] || printf '%s\n' "$err" >&2
  return "$rc"
}

_hub_ci_status_tolerated() { # GH-STDERR : an HTTP 403, 404 or 422 that is not a rate limit
  [[ ${1,,} != *"rate limit"* ]] && grep -Eq '^gh: (.* \()?HTTP (403|404|422)\)?$' <<<"$1"
}
