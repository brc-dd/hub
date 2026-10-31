# shellcheck shell=bash
# Summary: Show the CI status of a commit.
# Usage: hub ci-status [-v] [COMMIT]
#
# Prints the most severe state among the commit statuses and check runs of COMMIT (default HEAD):
# error, failure, action_required, timed_out, cancelled, pending, success or neutral, else
# "no status". A check run that has not completed is pending; other states, such as skipped, are
# ignored. COMMIT is resolved by git when it can be (a branch, a tag, HEAD~2, ...); a name git
# does not know, such as a branch only GitHub has, goes to the API as it is, encoded as one path
# segment (feature/x as feature%2Fx). The repository is the current project (GH_REPO, else the
# one the upstream, github or origin remote points at), named to gh with its host.
#
# The statuses and the check runs are read with `gh api --paginate`. When GitHub refuses the
# check runs outright with HTTP 403, 404 or 422 on their first page (not every token may read
# them), the commit statuses alone count. A failing state, once seen, is final: when the check
# runs cannot be read completely after one was seen (a later page fails, or they fail while a
# status already failed), hub still reports it and prints gh's error as a warning. Without one,
# an unreadable page is an error, even after an empty page, since what is missing could still
# fail. For a pull request, `gh pr checks` has more to offer.
#
# Options:
#   -v, --verbose   Print STATE, NAME and URL for every check instead, failures first.
#
# Exit status: 0 for success or neutral, 1 for a failure state, 2 for pending, 3 for no status;
# gh's status (1) when a lookup failed without a verdict.
#
#   $ hub ci-status -v main
#   failure   lint    https://github.com/OWNER/REPO/actions/runs/1/job/2
#   success   build   https://github.com/OWNER/REPO/actions/runs/1/job/3

hub_cmd_ci_status() {
  local verbose=0 ref commit path state line rc=0 seen
  local -a operands=() api lines=() pages=()
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -v | --verbose) verbose=1 ;;
      -h | --help) hub::usage ;;
      --)
        shift
        operands+=("$@")
        break
        ;;
      -?*) _hub_ci_status_usage_error "unknown option: $1" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} <= 1)) || _hub_ci_status_usage_error "give at most one COMMIT"
  ref=${operands[0]:-HEAD}
  hub::require_gh
  hub::main_project >/dev/null
  # git resolves what it knows to a hash; anything else is one path segment of the API URL
  commit=$(hub::git_query rev-parse -q --verify --end-of-options "$ref^{commit}") || commit=$(hub::url_segment "$ref")
  path=repos/$HUB_PROJECT/commits/$commit
  api=(api --hostname "$HUB_PROJECT_HOST" --paginate)

  _hub_ci_status_api "${api[@]}" "$path/status" --jq '.statuses[] | ["status", .state, .context, .target_url // ""] | @tsv' || {
    rc=$?
    [[ -z $HUB_CI_ERR ]] || printf '%s\n' "$HUB_CI_ERR" >&2
    exit "$rc"
  }
  mapfile -t lines < <(_hub_ci_status_lines status)
  # every page read is marked, so that a page that fails after an empty one is still missing; a
  # page without a check_runs array is no page of check runs, and fails the lookup
  _hub_ci_status_api "${api[@]}" "$path/check-runs" \
    --jq 'if (.check_runs | type) != "array" then error("not a page of check runs") else (["page", ""], (.check_runs[] | ["check", (if .status == "completed" then .conclusion else "pending" end), .name, .html_url // ""])) | @tsv end' || rc=$?
  seen=${#lines[@]}
  mapfile -t -O "$seen" lines < <(_hub_ci_status_lines check)
  mapfile -t pages < <(_hub_ci_status_lines page)
  state=$(_hub_ci_status_state "${lines[@]}")
  if ((rc)); then
    if ((${#pages[@]} == 0)) && _hub_ci_status_tolerated "$HUB_CI_ERR"; then
      # refused before any page of check runs was read: the commit statuses alone decide
      [[ -z ${HUB_VERBOSE:-} || -z $HUB_CI_ERR ]] || printf '%s\n' "$HUB_CI_ERR" >&2
      hub::debug "no check runs; counting the commit statuses only"
    elif _hub_ci_status_failing "$state"; then
      [[ -z $HUB_CI_ERR ]] || printf '%s\n' "$HUB_CI_ERR" >&2
      hub::warn "hub ci-status: not every check run could be read; the $state already seen is final"
    else
      [[ -z $HUB_CI_ERR ]] || printf '%s\n' "$HUB_CI_ERR" >&2
      exit "$rc"
    fi
  fi

  if ((verbose && ${#lines[@]})); then
    for line in "${lines[@]}"; do
      if _hub_ci_status_failing "${line%%$'\t'*}"; then
        printf '1\t%s\n' "$line"
      else
        case ${line%%$'\t'*} in
          success | neutral) printf '3\t%s\n' "$line" ;;
          *) printf '2\t%s\n' "$line" ;;
        esac
      fi
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

_hub_ci_status_usage_error() {
  hub::die "hub ci-status: $1"$'\n'"Usage: hub ci-status [-v] [COMMIT]"
}

# _hub_ci_status_api ARGS... : gh api ARGS..., with what it printed on stdout in HUB_CI_OUT and on
# stderr in HUB_CI_ERR; returns gh's status. A failed request leaves its error document on stdout,
# after the results of the pages read before it, and "gh: MESSAGE (HTTP N)" on stderr. Both streams
# come through one capture: stderr while gh runs, then, once it has exited, a separator line with
# its status, then stdout.
_hub_ci_status_api() {
  local text out
  text=$({
    out=$(hub::gh_query "$@" 2>&3)
    printf '\n\x1f%s\n%s' "$?" "$out" >&3
  } 3>&1)
  HUB_CI_ERR=${text%%$'\n\x1f'*}
  while [[ $HUB_CI_ERR == *$'\n' ]]; do HUB_CI_ERR=${HUB_CI_ERR%$'\n'}; done
  text=${text#*$'\n\x1f'}
  if [[ $text == *$'\n'* ]]; then HUB_CI_OUT=${text#*$'\n'}; else HUB_CI_OUT=''; fi
  return "${text%%$'\n'*}"
}

# _hub_ci_status_lines KIND : the lines of HUB_CI_OUT that gh's jq filter tagged KIND, untagged:
# STATE, NAME and URL, tab-separated, or an empty line per page read. Anything else gh printed
# there (an error document) is dropped.
_hub_ci_status_lines() {
  local line
  while IFS= read -r line; do
    [[ $line == "$1"$'\t'* ]] && printf '%s\n' "${line#*$'\t'}"
  done <<<"$HUB_CI_OUT"
}

# _hub_ci_status_state LINE... : the most severe state among the lines, else "no status".
_hub_ci_status_state() {
  local states state
  states=$'\n'$(printf '%s\n' "${@%%$'\t'*}")$'\n'
  for state in error failure action_required timed_out cancelled pending success neutral 'no status'; do
    [[ $states != *$'\n'"$state"$'\n'* ]] || break
  done
  printf '%s\n' "$state"
}

# _hub_ci_status_failing STATE : a state that counts as a failure (exit status 1).
_hub_ci_status_failing() {
  case $1 in
    error | failure | action_required | timed_out | cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

_hub_ci_status_tolerated() { # GH-STDERR : an HTTP 403, 404 or 422 that is not a rate limit
  [[ ${1,,} != *"rate limit"* ]] && grep -Eq '^gh: (.* \()?HTTP (403|404|422)\)?$' <<<"$1"
}
