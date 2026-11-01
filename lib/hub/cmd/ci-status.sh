# shellcheck shell=bash
# shellcheck disable=SC2016  # $owner, $o and the like are GraphQL's and jq's variables
# Summary: Show the CI status of a commit.
# Usage: hub ci-status [-v] [COMMIT]
#
# hub's own command: these are all of its options. Prints GitHub's combined verdict on the
# checks and commit statuses of COMMIT (default HEAD) in the current project: success,
# failure, error, pending or no status. COMMIT is resolved by git when it can be (a branch, a
# tag, HEAD~2); any other name, such as a branch only GitHub has, goes to GitHub as it is.
# Inside a repository, HEAD and @ names must resolve here: GitHub reads HEAD as its default
# branch.
#
# Options:
#   -v, --verbose   Print STATE, NAME and URL of every check instead (the first 100), failures
#                   first, then pending ones, then the rest; nothing when there is no check.
#
# Exit status: 0 success, 1 failure or error (also when the lookup fails or GitHub has no
# such commit), 2 pending, 3 no status.
#
#   $ hub ci-status
#   success
#   $ hub ci-status -v main
#   failure	lint	https://github.com/OWNER/REPO/actions/runs/1/job/2
#   success	build	https://github.com/OWNER/REPO/actions/runs/1/job/3

hub_cmd_ci_status() {
  local verbose=0 ref expr project host owner repo out state query jq rc
  local -a operands=() contexts
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -v | --verbose) verbose=1 ;;
      -h | --help) hub::usage ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $(hub::shown "$1")" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} <= 1)) \
    || hub::usage_error "unexpected argument: $(hub::shown "${operands[1]}")"
  ref=${operands[0]-HEAD}
  [[ -n $ref ]] || hub::usage_error 'empty commit'
  project=$(hub::project) || exit 1
  read -r host owner repo <<<"$project"
  hub::require_gh
  if ! expr=$(hub::git_query rev-parse --verify --quiet --end-of-options "$ref^{commit}"); then
    # GitHub would answer for its default branch: a name of the local HEAD must resolve here.
    if [[ $ref =~ ^(HEAD|@)([~^@{:]|$) ]] && hub::git_query rev-parse --git-dir >/dev/null; then
      hub::die "$(hub::shown "$ref") is not a commit in this repository"
    fi
    expr=$ref
  fi
  query='query($owner: String!, $name: String!, $expr: String!) {'
  query+=' repository(owner: $owner, name: $name) { object(expression: $expr) {'
  query+=' ... on Commit { statusCheckRollup { state contexts(first: 100) { nodes { __typename'
  query+=' ... on CheckRun { name status conclusion detailsUrl }'
  query+=' ... on StatusContext { context state targetUrl } } } } } } } }'
  # A missing object is null and a tree or blob has no rollup field: both are no commit.
  jq='.data.repository.object as $o | if ($o // {} | has("statusCheckRollup") | not)'
  jq+=' then "MISSING" elif $o.statusCheckRollup == null then "NONE"'
  jq+=' else $o.statusCheckRollup | .state, (.contexts.nodes[] | if .__typename == "CheckRun"'
  jq+=' then [(if .status == "COMPLETED" then .conclusion else .status end), .name, .detailsUrl]'
  jq+=' else [.state, .context, .targetUrl] end | map(. // "") | .[0] |= ascii_downcase'
  jq+=' | @tsv) end'
  # -f, never -F: gh would read a value such as @file or 12 as a file or a number.
  out=$(gh api graphql --hostname "$host" -f query="$query" -f owner="$owner" -f name="$repo" \
    -f expr="$expr" --jq "$jq") || exit 1
  mapfile -t contexts <<<"$out"
  state=${contexts[0]}
  contexts=("${contexts[@]:1}")
  # GitHub answers a missing commit without an error, so the message is hub's.
  [[ $state != MISSING ]] || hub::die "$(hub::shown "$ref") is not a commit of $host/$owner/$repo"
  case $state in
    SUCCESS) out=success rc=0 ;;
    PENDING | EXPECTED) out=pending rc=2 ;;
    NONE) out='no status' rc=3 ;;
    *) out=${state,,} rc=1 ;;
  esac
  if ((verbose)); then
    ((${#contexts[@]} == 0)) || _hub_ci_status_sort "${contexts[@]}"
  else
    printf '%s\n' "$out"
  fi
  return "$rc"
}

# _hub_ci_status_sort LINE... : STATE<TAB>NAME<TAB>URL lines, failures first, then pending ones.
_hub_ci_status_sort() {
  local line rank
  for line; do
    case ${line%%$'\t'*} in
      failure | error | cancelled | timed_out | action_required | startup_failure | stale)
        rank=0
        ;;
      pending | expected | queued | in_progress | waiting | requested) rank=1 ;;
      *) rank=2 ;;
    esac
    printf '%s\t%s\n' "$rank" "$line"
  done | LC_ALL=C sort -t $'\t' -k 1,1n -k 3,3 -s | cut -f 2-
}
