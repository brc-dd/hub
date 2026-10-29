#!/usr/bin/env bats
load ../test_helper

# stub_ci STATUSES CHECK-RUNS : what the two gh api lookups print (one state, or -v line, per line).
stub_ci() {
  stub_gh 'api --paginate repos/{owner}/{repo}/commits/*/status *' "$1"
  stub_gh 'api --paginate repos/{owner}/{repo}/commits/*/check-runs *' "$2"
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
  assert_gh_called "api --paginate repos/{owner}/{repo}/commits/$sha/status --jq .statuses\\[\\].state"
  assert_gh_called "api --paginate repos/{owner}/{repo}/commits/$sha/check-runs --jq .check_runs\\[\\] | if .status == \"completed\" then .conclusion else \"pending\" end"
}

@test "COMMIT defaults to HEAD" {
  ci_repo
  stub_ci 'success' ''
  run hub ci-status
  assert_status 0
  assert_gh_called "api --paginate repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/status *"
}

@test "a ref that isn't known locally is left for GitHub to resolve" {
  ci_repo
  stub_ci 'success' ''
  run hub ci-status only-on-github
  assert_status 0
  assert_gh_called 'api --paginate repos/{owner}/{repo}/commits/only-on-github/status *'
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
  assert_gh_called 'api --paginate repos/{owner}/{repo}/commits/*/status --jq .statuses\[\] | \[.state, .context, .target_url // ""\] | @tsv'
  assert_gh_called 'api --paginate repos/{owner}/{repo}/commits/*/check-runs --jq .check_runs\[\] | \[(if .status == "completed" then .conclusion else "pending" end), .name, .html_url // ""\] | @tsv'
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
  stub_gh 'api --hostname ghe.example.com --paginate repos/{owner}/{repo}/commits/*' 'success'
  run hub ci-status
  assert_status 0
  assert_gh_called 'api --hostname ghe.example.com --paginate repos/{owner}/{repo}/commits/*/status *'
  assert_gh_called 'api --hostname ghe.example.com --paginate repos/{owner}/{repo}/commits/*/check-runs *'
}

@test "a failing lookup is an error, not a verdict" {
  ci_repo
  stub_ci 'success' ''
  stub_gh 'api --paginate repos/{owner}/{repo}/commits/*/status *' '' 1
  run hub ci-status
  assert_status 1
  [[ $output != *"no status"* && $output != *success* ]]
  stub_ci 'success' ''
  stub_gh 'api --paginate repos/{owner}/{repo}/commits/*/check-runs *' '' 1
  run hub ci-status
  assert_status 1
  [[ $output != *success* ]]
}

@test "GH_REPO works outside a repository" {
  export GH_REPO=cli/cli
  stub_ci 'success' ''
  run hub ci-status abc123
  assert_status 0
  assert_output_equals "success"
  assert_gh_called 'api --paginate repos/{owner}/{repo}/commits/abc123/status *'
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
