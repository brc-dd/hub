#!/usr/bin/env bats
load ../test_helper

# stub_ci STATUSES CHECK-RUNS [HOST/OWNER/REPO] : what the two gh api lookups for the repository
# (github.com/mislav/dotfiles by default) print: one state, or -v line, per line.
stub_ci() {
  local repo=${3:-github.com/mislav/dotfiles}
  stub_gh "api --hostname ${repo%%/*} --paginate repos/${repo#*/}/commits/*/status *" "$1"
  stub_gh "api --hostname ${repo%%/*} --paginate repos/${repo#*/}/commits/*/check-runs *" "$2"
}

# shim_gh_check_runs_error : put a gh in PATH whose status lookup prints "success" and whose
# check-runs lookup fails the way gh does on an HTTP error: the error document on stdout,
# "gh: $HUB_TEST_CHECKS_ERROR" on stderr, exit 1.
shim_gh_check_runs_error() {
  mkdir -p "$HUB_TEST_TMP/shim"
  cat >"$HUB_TEST_TMP/shim/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$HUB_TEST_LOG"
case $* in
  *'/status --jq '*) printf 'success\n' ;;
  *'/check-runs --jq '*)
    printf '{"message":"%s"}\n' "${HUB_TEST_CHECKS_ERROR% (*}"
    printf 'gh: %s\n' "$HUB_TEST_CHECKS_ERROR" >&2
    exit 1
    ;;
  *) exit 97 ;;
esac
SH
  chmod +x "$HUB_TEST_TMP/shim/gh"
  export PATH=$HUB_TEST_TMP/shim:$PATH
}

assert_status() { [[ $status -eq $1 ]] || {
  printf 'expected exit %s, got %s\noutput:\n%s\n' "$1" "$status" "$output"
  return 1
}; }

ci_repo() { make_repo dotfiles origin=https://github.com/mislav/dotfiles.git; }

@test "success when every check passed" {
  ci_repo
  stub_ci 'success\nsuccess' 'success\nneutral'
  run hub ci-status
  assert_status 0
  assert_output_equals "success"
}

@test "neutral alone still passes" {
  ci_repo
  stub_ci '' 'neutral'
  run hub ci-status
  assert_status 0
  assert_output_equals "neutral"
}

@test "pending while any check is still running" {
  ci_repo
  stub_ci 'success\npending' 'success'
  run hub ci-status
  assert_status 2
  assert_output_equals "pending"
}

@test "a failure outranks pending" {
  ci_repo
  stub_ci 'pending' 'success\nfailure'
  run hub ci-status
  assert_status 1
  assert_output_equals "failure"
}

@test "cancelled counts as a failure" {
  ci_repo
  stub_ci 'success' 'cancelled\nsuccess'
  run hub ci-status
  assert_status 1
  assert_output_equals "cancelled"
}

@test "the most severe state wins" {
  ci_repo
  stub_ci 'failure\nerror' 'action_required\ntimed_out'
  run hub ci-status
  assert_status 1
  assert_output_equals "error"
  stub_ci 'success' 'timed_out\naction_required\npending'
  run hub ci-status
  assert_status 1
  assert_output_equals "action_required"
  stub_ci 'pending' 'cancelled\ntimed_out'
  run hub ci-status
  assert_status 1
  assert_output_equals "timed_out"
}

@test "no checks at all is 'no status'" {
  ci_repo
  stub_ci '' ''
  run hub ci-status
  assert_status 3
  assert_output_equals "no status"
}

@test "skipped and stale checks are ignored" {
  ci_repo
  stub_ci '' 'skipped\nstale'
  run hub ci-status
  assert_status 3
  assert_output_equals "no status"
}

@test "COMMIT is resolved locally and both lookups are made" {
  ci_repo
  git commit -q --allow-empty -m second
  sha=$(git rev-parse HEAD~1)
  stub_ci 'success' ''
  run hub ci-status HEAD~1
  assert_status 0
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$sha/status --jq .statuses\\[\\].state"
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$sha/check-runs --jq .check_runs\\[\\] | if .status == \"completed\" then .conclusion else \"pending\" end"
}

@test "COMMIT defaults to HEAD" {
  ci_repo
  stub_ci 'success' ''
  run hub ci-status
  assert_status 0
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$(git rev-parse HEAD)/status *"
}

@test "a ref that isn't known locally is left for GitHub to resolve" {
  ci_repo
  stub_ci 'success' ''
  run hub ci-status only-on-github
  assert_status 0
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/only-on-github/status *'
}

@test "-v lists every check, failures first, then pending, then passes" {
  ci_repo
  stub_ci 'success\tci/travis\thttps://ci.example/1\nfailure\tZeta\thttps://ci.example/2' \
    'pending\tbuild\thttps://github.com/r/3\nfailure\talpha\thttps://github.com/r/4\nneutral\tlint\thttps://github.com/r/5'
  run hub ci-status -v
  assert_status 1
  assert_output_equals "$(printf '%s\t%s\t%s\n' \
    failure alpha https://github.com/r/4 \
    failure Zeta https://ci.example/2 \
    pending build https://github.com/r/3 \
    success ci/travis https://ci.example/1 \
    neutral lint https://github.com/r/5)"
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/status --jq .statuses\[\] | \[.state, .context, .target_url // ""\] | @tsv'
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/check-runs --jq .check_runs\[\] | \[(if .status == "completed" then .conclusion else "pending" end), .name, .html_url // ""\] | @tsv'
}

@test "-v keeps the exit code and says 'no status' when there are no checks" {
  ci_repo
  stub_ci 'pending\tci/travis\thttps://ci.example/1' ''
  run hub ci-status --verbose main
  assert_status 2
  assert_output_equals "$(printf 'pending\tci/travis\thttps://ci.example/1')"
  stub_ci '' ''
  run hub ci-status -v
  assert_status 3
  assert_output_equals "no status"
}

@test "GitHub Enterprise projects pass --hostname" {
  git config --global --add hub.host ghe.example.com
  make_repo dotfiles origin=https://ghe.example.com/mislav/dotfiles.git
  stub_gh 'api --hostname ghe.example.com --paginate repos/mislav/dotfiles/commits/*' 'success'
  run hub ci-status
  assert_status 0
  assert_gh_called 'api --hostname ghe.example.com --paginate repos/mislav/dotfiles/commits/*/status *'
  assert_gh_called 'api --hostname ghe.example.com --paginate repos/mislav/dotfiles/commits/*/check-runs *'
}

@test "the repository hub picks is named to gh, not left to gh's own default" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/dotcom/dotfiles.git
  stub_ci 'success' '' github.com/dotcom/dotfiles
  run hub ci-status
  assert_status 0
  assert_output_equals "success"
  assert_gh_called 'api --hostname github.com --paginate repos/dotcom/dotfiles/commits/*/status *'
  assert_gh_called 'api --hostname github.com --paginate repos/dotcom/dotfiles/commits/*/check-runs *'
  [[ $(gh_calls) != *"{owner}"* && $(gh_calls) != *"{repo}"* ]]
}

@test "a github.com project names github.com even when GH_HOST is another host" {
  ci_repo
  stub_ci 'success' ''
  GH_HOST=ghe.example.com run hub ci-status
  assert_status 0
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/status *'
}

@test "GH_REPO's host, else GH_HOST or GITHUB_HOST, is the host" {
  stub_ci 'success' '' ghe.example.com/corp/app
  GH_REPO=ghe.example.com/corp/app run hub ci-status abc123
  assert_status 0
  assert_gh_called 'api --hostname ghe.example.com --paginate repos/corp/app/commits/abc123/status *'
  GH_REPO=corp/app GH_HOST=ghe.example.com run hub ci-status abc123
  assert_status 0
  GH_REPO=corp/app GITHUB_HOST=ghe.example.com run hub ci-status abc123
  assert_status 0
  assert_output_equals "success"
}

@test "check runs refused with HTTP 403, 404 or 422 leave the commit statuses to decide" {
  ci_repo
  shim_gh_check_runs_error
  for HUB_TEST_CHECKS_ERROR in 'Not Found (HTTP 404)' 'Validation Failed (HTTP 422)' \
    'Resource not accessible by integration (HTTP 403)' 'Resource not accessible by personal access token (HTTP 403)'; do
    export HUB_TEST_CHECKS_ERROR
    run hub ci-status
    assert_status 0
    assert_output_equals "success"
  done
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/check-runs *'
}

@test "any other check runs failure is an error that shows gh's message" {
  ci_repo
  shim_gh_check_runs_error
  for HUB_TEST_CHECKS_ERROR in 'Server Error (HTTP 500)' 'Bad credentials (HTTP 401)' \
    'API rate limit exceeded for user ID 1. (HTTP 403)' 'You have exceeded a secondary rate limit. (HTTP 403)'; do
    export HUB_TEST_CHECKS_ERROR
    run hub ci-status
    assert_status 1
    assert_output_equals "gh: $HUB_TEST_CHECKS_ERROR"
  done
}

@test "which gh errors are tolerated is decided from gh's own error lines" {
  export HUB_ROOT=$HUB_TEST_ROOT
  source "$HUB_TEST_ROOT/lib/hub/core.sh"
  source "$HUB_TEST_ROOT/lib/hub/cmd/ci-status.sh"
  _hub_ci_status_tolerated 'gh: Not Found (HTTP 404)'
  _hub_ci_status_tolerated 'gh: Validation Failed (HTTP 422)'
  _hub_ci_status_tolerated 'gh: Must have admin rights to Repository. (HTTP 403)'
  _hub_ci_status_tolerated 'gh: HTTP 404'
  _hub_ci_status_tolerated $'gh: Resource not accessible by integration (HTTP 403)\ngh: This API operation needs the "checks" scope.'
  local msg
  for msg in 'gh: Server Error (HTTP 500)' 'gh: Bad credentials (HTTP 401)' 'gh: API rate limit exceeded for user ID 1. (HTTP 403)' \
    'gh: upstream said HTTP 404 (HTTP 502)' 'gh: HTTP 4040' 'error connecting to api.github.com' ''; do
    run _hub_ci_status_tolerated "$msg"
    assert_failure
  done
}

@test "a failing lookup is an error, not a verdict" {
  ci_repo
  stub_ci 'success' ''
  stub_gh 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/status *' '' 1
  run hub ci-status
  assert_status 1
  [[ $output != *"no status"* && $output != *success* ]]
  stub_ci 'success' ''
  stub_gh 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/check-runs *' '' 1
  run hub ci-status
  assert_status 1
  [[ $output != *success* ]]
}

@test "GH_REPO works outside a repository" {
  export GH_REPO=cli/cli
  stub_ci 'success' '' github.com/cli/cli
  run hub ci-status abc123
  assert_status 0
  assert_output_equals "success"
  assert_gh_called 'api --hostname github.com --paginate repos/cli/cli/commits/abc123/status *'
}

@test "--help prints the manual" {
  run hub ci-status --help
  assert_success
  assert_output_contains "Usage: hub ci-status [-v] [COMMIT]"
  assert_output_contains "gh pr checks"
}

@test "unknown options and extra arguments are rejected" {
  ci_repo
  run hub ci-status -f '%S'
  assert_failure
  assert_output_contains "Aborted: unknown option '-f'"
  run hub ci-status main HEAD
  assert_failure
  assert_output_contains "Aborted: give at most one COMMIT"
  assert_gh_not_called
}

@test "outside a repository, or without a GitHub remote, it aborts" {
  run hub ci-status
  assert_failure
  assert_output_contains "fatal: not a git repository"
  make_repo local-only
  run hub ci-status
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
  assert_gh_not_called
}
