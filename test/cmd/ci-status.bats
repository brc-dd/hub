#!/usr/bin/env bats
load ../test_helper

# tagged KIND LINES : KIND and a tab in front of every line of LINES (printf %b escapes, \n between
# lines), the way hub's jq filters tag what they print.
tagged() {
  [[ -n $2 ]] || return 0
  printf '%s' "$1\\t${2//\\n/\\n$1\\t}"
}

# stub_ci STATUSES CHECK-RUNS [HOST/OWNER/REPO] : what the two gh api lookups for the repository
# (github.com/mislav/dotfiles by default) print: one STATE[\tNAME\tURL] per line.
stub_ci() {
  local repo=${3:-github.com/mislav/dotfiles}
  stub_gh "api --hostname ${repo%%/*} --paginate repos/${repo#*/}/commits/*/status *" "$(tagged status "$1")"
  stub_gh "api --hostname ${repo%%/*} --paginate repos/${repo#*/}/commits/*/check-runs *" "$(tagged check "$2")"
}

# shim_gh : a gh in PATH that logs its calls, prints HUB_TEST_STATUSES for the status lookup and
# HUB_TEST_CHECKS for the check-runs lookup (what hub's jq filters print: tagged lines, with printf
# %b escapes; for the check runs, a "page\t" line per page read and a check line per check run),
# then, when HUB_TEST_CHECKS_ERROR is set, fails the way gh does when a page cannot be read: the
# error document on stdout, "gh: $HUB_TEST_CHECKS_ERROR" on stderr, exit 1.
shim_gh() {
  mkdir -p "$HUB_TEST_TMP/shim"
  cat >"$HUB_TEST_TMP/shim/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$HUB_TEST_LOG"
case $* in
  *'/status --jq '*) [[ -z ${HUB_TEST_STATUSES-} ]] || printf '%b\n' "$HUB_TEST_STATUSES" ;;
  *'/check-runs --jq '*)
    [[ -z ${HUB_TEST_CHECKS-} ]] || printf '%b\n' "$HUB_TEST_CHECKS"
    [[ -n ${HUB_TEST_CHECKS_ERROR-} ]] || exit 0
    printf '{"message":"%s"}\n' "${HUB_TEST_CHECKS_ERROR% (*}"
    printf 'gh: %s\n' "$HUB_TEST_CHECKS_ERROR" >&2
    exit 1
    ;;
  *) exit 97 ;;
esac
SH
  chmod +x "$HUB_TEST_TMP/shim/gh"
  export PATH=$HUB_TEST_TMP/shim:$PATH HUB_TEST_STATUSES='status\tsuccess\tci\thttps://ci.example/1'
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
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$sha/status --jq *"
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$sha/check-runs --jq *"
  run hub ci-status -- HEAD~1
  assert_status 0
  git update-ref refs/tags/-dash HEAD # a name only -- can introduce; git still resolves it
  run hub ci-status -- -dash
  assert_status 0
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$(git rev-parse HEAD)/status --jq *"
}

@test "COMMIT defaults to HEAD" {
  ci_repo
  stub_ci 'success' ''
  run hub ci-status
  assert_status 0
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$(git rev-parse HEAD)/status *"
}

@test "a ref git does not know goes to the API as it is, encoded as one path segment" {
  ci_repo
  stub_ci 'success' ''
  run hub ci-status only-on-github
  assert_status 0
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/only-on-github/status *'
  run hub ci-status 'feature#123'
  assert_status 0
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/feature%23123/status *'
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/feature%23123/check-runs *'
  run hub ci-status 'feature%2Fother' # a literal percent sequence stays one
  assert_status 0
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/feature%252Fother/status *'
  run hub ci-status topic/sub
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/topic%2Fsub/status *'
  run hub ci-status 'héllo wörld'
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/h%C3%A9llo%20w%C3%B6rld/status *'
  [[ $(gh_calls) != *'commits/feature/'* && $(gh_calls) != *'commits/topic/sub/'* ]]
  # a branch of such a name is resolved by git first
  git branch 'feature#123'
  : >"$HUB_TEST_LOG"
  run hub ci-status 'feature#123'
  assert_status 0
  assert_gh_called "api --hostname github.com --paginate repos/mislav/dotfiles/commits/$(git rev-parse HEAD)/status *"
  [[ $(gh_calls) != *'feature%23123'* ]]
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
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/status --jq .statuses\[\] | \["status", .state, .context, .target_url // ""\] | @tsv'
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/check-runs --jq if (.check_runs | type) != "array" then error("not a page of check runs") else (\["page", ""\], (.check_runs\[\] | \["check", (if .status == "completed" then .conclusion else "pending" end), .name, .html_url // ""\])) | @tsv end'
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
  stub_gh 'api --hostname ghe.example.com --paginate repos/mislav/dotfiles/commits/*' 'status\tsuccess'
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

@test "check runs refused outright with HTTP 403, 404 or 422 leave the commit statuses to decide" {
  ci_repo
  shim_gh
  for HUB_TEST_CHECKS_ERROR in 'Not Found (HTTP 404)' 'Validation Failed (HTTP 422)' \
    'Resource not accessible by integration (HTTP 403)' 'Resource not accessible by personal access token (HTTP 403)'; do
    export HUB_TEST_CHECKS_ERROR
    run hub ci-status
    assert_status 0
    assert_output_equals "success"
    run hub ci-status -v
    assert_status 0
    assert_output_equals "$(printf 'success\tci\thttps://ci.example/1')"
  done
  assert_gh_called 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/check-runs *'
  # a status that failed is the verdict then, as always
  HUB_TEST_STATUSES='status\tfailure\tci\thttps://ci.example/1' run hub ci-status
  assert_status 1
  assert_output_equals "failure"
}

@test "any other check runs failure is an error that shows gh's message" {
  ci_repo
  shim_gh
  for HUB_TEST_CHECKS_ERROR in 'Server Error (HTTP 500)' 'Bad credentials (HTTP 401)' \
    'API rate limit exceeded for user ID 1. (HTTP 403)' 'You have exceeded a secondary rate limit. (HTTP 403)'; do
    export HUB_TEST_CHECKS_ERROR
    run hub ci-status
    assert_status 1
    assert_output_equals "gh: $HUB_TEST_CHECKS_ERROR"
  done
}

@test "a check-runs page that cannot be read after a failing check was keeps the failure" {
  ci_repo
  shim_gh
  export HUB_TEST_CHECKS='page\t\ncheck\tfailure\tlint\thttps://github.com/r/1\ncheck\tsuccess\tbuild\thttps://github.com/r/2'
  for HUB_TEST_CHECKS_ERROR in 'Resource not accessible by integration (HTTP 403)' 'Not Found (HTTP 404)' \
    'Validation Failed (HTTP 422)' 'Server Error (HTTP 500)'; do
    export HUB_TEST_CHECKS_ERROR
    run hub ci-status
    assert_status 1
    assert_output_equals "$(printf '%s\n' "gh: $HUB_TEST_CHECKS_ERROR" \
      "hub ci-status: not every check run could be read; the failure already seen is final" failure)"
    run hub ci-status -v
    assert_status 1
    assert_output_equals "$(printf '%s\n' "gh: $HUB_TEST_CHECKS_ERROR" \
      "hub ci-status: not every check run could be read; the failure already seen is final" \
      "$(printf '%s\t%s\t%s\n' failure lint https://github.com/r/1 success build https://github.com/r/2 success ci https://ci.example/1)")"
  done
  # a check that was cancelled is a failure, too
  HUB_TEST_CHECKS='page\t\ncheck\tcancelled\tdeploy\thttps://github.com/r/3' run hub ci-status
  assert_status 1
  assert_output_equals "$(printf '%s\n' "gh: $HUB_TEST_CHECKS_ERROR" \
    "hub ci-status: not every check run could be read; the cancelled already seen is final" cancelled)"
}

@test "a check-runs page that cannot be read after only passing or pending checks is an error, not a verdict" {
  ci_repo
  shim_gh
  local checks
  for checks in 'page\t\ncheck\tsuccess\tbuild\thttps://github.com/r/2' 'page\t\ncheck\tpending\tbuild\thttps://github.com/r/2' \
    'page\t\ncheck\tskipped\tbuild\thttps://github.com/r/2'; do
    export HUB_TEST_CHECKS=$checks
    for HUB_TEST_CHECKS_ERROR in 'Resource not accessible by integration (HTTP 403)' 'Not Found (HTTP 404)' \
      'Validation Failed (HTTP 422)' 'Server Error (HTTP 500)'; do
      export HUB_TEST_CHECKS_ERROR
      run hub ci-status
      assert_status 1
      assert_output_equals "gh: $HUB_TEST_CHECKS_ERROR"
      run hub ci-status -v
      assert_status 1
      assert_output_equals "gh: $HUB_TEST_CHECKS_ERROR"
    done
  done
}

@test "a check-runs page that cannot be read after an empty page is an error, not a verdict" {
  ci_repo
  shim_gh
  export HUB_TEST_CHECKS='page\t' # the first page was read and held no check run; the next one fails
  for HUB_TEST_CHECKS_ERROR in 'Resource not accessible by integration (HTTP 403)' 'Not Found (HTTP 404)' \
    'Validation Failed (HTTP 422)'; do
    export HUB_TEST_CHECKS_ERROR
    run hub ci-status
    assert_status 1
    assert_output_equals "gh: $HUB_TEST_CHECKS_ERROR"
    run hub ci-status -v
    assert_status 1
    assert_output_equals "gh: $HUB_TEST_CHECKS_ERROR"
  done
  # refused on the first page, with nothing read: the statuses decide, as always
  unset HUB_TEST_CHECKS
  run hub ci-status
  assert_status 0
  assert_output_equals "success"
}

@test "a status that failed is final even when the check runs cannot be read at all" {
  ci_repo
  shim_gh
  export HUB_TEST_STATUSES='status\tfailure\tci\thttps://ci.example/1\nstatus\tsuccess\tdocs\thttps://ci.example/2'
  export HUB_TEST_CHECKS_ERROR='Server Error (HTTP 500)'
  run hub ci-status
  assert_status 1
  assert_output_equals "$(printf '%s\n' 'gh: Server Error (HTTP 500)' \
    "hub ci-status: not every check run could be read; the failure already seen is final" failure)"
  export HUB_TEST_STATUSES='status\tpending\tci\thttps://ci.example/1'
  run hub ci-status
  assert_status 1
  assert_output_equals "gh: Server Error (HTTP 500)"
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

@test "gh's two output streams are told apart, whatever it prints on which" {
  export HUB_ROOT=$HUB_TEST_ROOT
  source "$HUB_TEST_ROOT/lib/hub/core.sh"
  source "$HUB_TEST_ROOT/lib/hub/cmd/ci-status.sh"
  mkdir fakegh
  printf '#!/usr/bin/env bash\nprintf "check\\tfailure\\tlint\\turl\\n"\nprintf "gh: first\\n" >&2\nprintf "{\\"message\\":\\"x\\"}\\n"\nprintf "gh: second (HTTP 403)\\n" >&2\nexit 7\n' >fakegh/gh
  chmod +x fakegh/gh
  PATH=$PWD/fakegh:$PATH _hub_ci_status_api anything || status=$?
  assert_equals "$status" 7
  assert_equals "$HUB_CI_ERR" $'gh: first\ngh: second (HTTP 403)'
  assert_equals "$HUB_CI_OUT" $'check\tfailure\tlint\turl\n{"message":"x"}'
  assert_equals "$(_hub_ci_status_lines check)" $'failure\tlint\turl'
  assert_equals "$(_hub_ci_status_lines status)" ''
  printf '#!/usr/bin/env bash\nexit 0\n' >fakegh/gh
  PATH=$PWD/fakegh:$PATH _hub_ci_status_api anything
  [[ -z $HUB_CI_ERR && -z $HUB_CI_OUT ]]
}

@test "a failing lookup is an error, not a verdict" {
  ci_repo
  stub_ci 'success' ''
  stub_gh 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/status *' '{"message":"Not Found"}' 1
  run hub ci-status
  assert_status 1
  [[ $output != *"no status"* && $output != *success* ]]
  stub_ci 'success' ''
  stub_gh 'api --hostname github.com --paginate repos/mislav/dotfiles/commits/*/check-runs *' '{"message":"Server Error"}' 1
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
  assert_output_contains "once seen, is final"
}

@test "unknown options and extra arguments are rejected" {
  ci_repo
  run hub ci-status -f '%S'
  assert_failure
  assert_output_equals $'hub ci-status: unknown option: -f\nUsage: hub ci-status [-v] [COMMIT]'
  run hub ci-status main HEAD
  assert_failure
  assert_output_contains "hub ci-status: give at most one COMMIT"
  run hub ci-status --verbose=1
  assert_failure
  assert_output_contains "hub ci-status: unknown option: --verbose=1"
  assert_gh_not_called
}

@test "outside a repository, or without a GitHub remote, it aborts" {
  run hub ci-status
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
  make_repo local-only
  run hub ci-status
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
  assert_gh_not_called
}

@test "an answer that is no page of check runs fails the lookup instead of counting as an empty page" {
  ci_repo
  shim_gh
  export HUB_TEST_CHECKS='' HUB_TEST_CHECKS_ERROR='not a page of check runs'
  run hub ci-status
  assert_status 1
  assert_output_equals "gh: not a page of check runs"
  run hub ci-status -v
  assert_status 1
  assert_output_equals "gh: not a page of check runs"
}

@test "the check-runs filter marks every page and fails on anything that is not one" {
  command -v jq >/dev/null || skip "jq is not installed"
  ci_repo
  shim_gh
  run hub ci-status
  local filter
  filter=$(gh_calls | sed -n 's/.*check-runs --jq //p' | head -n 1)
  [[ -n $filter ]]
  run jq -r "$filter" <<<'{"check_runs":[]}'
  assert_success
  assert_output_equals $'page\t'
  run jq -r "$filter" <<<'{"check_runs":[{"status":"completed","conclusion":"failure","name":"lint","html_url":"https://github.com/r/1"},{"status":"in_progress","name":"build"}]}'
  assert_success
  assert_output_equals $'page\t\ncheck\tfailure\tlint\thttps://github.com/r/1\ncheck\tpending\tbuild\t'
  run jq -r "$filter" <<<'{"message":"not a checks document"}'
  assert_failure
  assert_output_contains "not a page of check runs"
  run jq -r "$filter" <<<'{"check_runs":null,"total_count":0}'
  assert_failure
}
