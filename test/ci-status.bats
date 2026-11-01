#!/usr/bin/env bats
# hub ci-status: GitHub's verdict on a commit's checks, from one GraphQL query.

load test_helper

setup() {
  hub_test_setup
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  # gh's --jq, applied by jq to the stub's GraphQL answer, so the module's filter runs too.
  mkdir -p "$HUB_TEST_TMP/jqgh"
  printf '%s\n' '#!/usr/bin/env bash' 'prev= filter=' \
    'for arg; do [[ $prev != --jq ]] || filter=$arg; prev=$arg; done' \
    'out=$("$HUB_TEST_ROOT/test/stubs/gh" "$@") || { rc=$?; printf "%s\n" "$out"; exit "$rc"; }' \
    '[[ -z $filter ]] || exec jq -r "$filter" <<<"$out"' 'printf "%s\n" "$out"' \
    >"$HUB_TEST_TMP/jqgh/gh"
  chmod +x "$HUB_TEST_TMP/jqgh/gh"
  PATH=$HUB_TEST_TMP/jqgh:$PATH
}

# stub_object EXPR OBJECT [HOST OWNER REPO] : GitHub's answer for the object EXPR names.
stub_object() {
  local repo="-f owner=${4:-mislav} -f name=${5:-dotfiles}"
  stub_gh "api graphql --hostname ${3:-github.com} -f query=* $repo -f expr=$1 --jq *" \
    "{\"data\": {\"repository\": {\"object\": $2}}}"
}

# stub_rollup EXPR STATE [NODE...] : a commit whose rollup has this state and these contexts.
stub_rollup() {
  local expr=$1 state=$2 nodes
  shift 2
  nodes=$(IFS=, && printf '%s' "$*")
  stub_object "$expr" "{\"statusCheckRollup\": {\"state\": \"$state\",\
 \"contexts\": {\"nodes\": [$nodes]}}}"
}

# check NAME STATUS CONCLUSION URL : a CheckRun node; null for an absent value.
check() {
  printf '{"__typename": "CheckRun", "name": "%s", "status": "%s", "conclusion": %s,' \
    "$1" "$2" "$3"
  printf ' "detailsUrl": %s}' "$4"
}

# status NAME STATE URL : a StatusContext node; null for an absent URL.
status() {
  printf '{"__typename": "StatusContext", "context": "%s", "state": "%s", "targetUrl": %s}' \
    "$1" "$2" "$3"
}

@test "hub ci-status asks GitHub about HEAD's commit and prints success" {
  stub_rollup "$(tip main)" SUCCESS
  run hub ci-status
  assert_success
  assert_output_equals success
  assert_gh_called "api graphql --hostname github.com -f query=* -f owner=mislav -f name=dotfiles\
 -f expr=$(tip main) --jq *"
  assert_gh_called 'api graphql * -f query=*statusCheckRollup { state contexts(first: 100) *'
  assert_equals "$(gh_calls | wc -l | tr -d ' ')" 1
}

@test "hub ci-status prints the verdict and exits by it" {
  local head
  head=$(tip main)
  stub_rollup "$head" FAILURE
  run hub ci-status
  assert_status 1
  assert_output_equals failure
  stub_rollup "$head" ERROR
  run hub ci-status
  assert_status 1
  assert_output_equals error
  stub_rollup "$head" PENDING
  run hub ci-status
  assert_status 2
  assert_output_equals pending
  stub_rollup "$head" EXPECTED
  run hub ci-status
  assert_status 2
  assert_output_equals pending
  stub_object "$head" '{"statusCheckRollup": null}'
  run hub ci-status
  assert_status 3
  assert_output_equals 'no status'
}

@test "hub ci-status resolves COMMIT with git and passes a name git does not know as given" {
  git branch topic
  commit_on topic 'second commit'
  stub_rollup "$(tip topic)" SUCCESS
  run hub ci-status topic
  assert_success
  assert_gh_called "api graphql * -f expr=$(tip topic) --jq *"
  stub_rollup 'feature/only-on-github' PENDING
  run hub ci-status feature/only-on-github
  assert_status 2
  assert_gh_called 'api graphql * -f expr=feature/only-on-github --jq *'
  stub_rollup HEADLESS SUCCESS
  run hub ci-status HEADLESS
  assert_success
  assert_gh_called 'api graphql * -f expr=HEADLESS --jq *'
  stub_rollup '--all' SUCCESS
  run hub ci-status -- --all
  assert_success
  assert_gh_called 'api graphql * -f expr=--all --jq *'
}

@test "hub ci-status takes a tag to the commit it names" {
  git tag -a -m 'release' v1.0
  stub_rollup "$(tip main)" SUCCESS
  run hub ci-status v1.0
  assert_success
  assert_gh_called "api graphql * -f expr=$(tip main) --jq *"
}

@test "hub ci-status -v lists failures first, then pending checks, then the rest, by name" {
  local u=https://ci.test
  stub_rollup "$(tip main)" FAILURE \
    "$(check success COMPLETED '"SUCCESS"' "\"$u/1\"")" \
    "$(check neutral COMPLETED '"NEUTRAL"' "\"$u/2\"")" \
    "$(check skipped COMPLETED '"SKIPPED"' "\"$u/3\"")" \
    "$(check queued QUEUED null "\"$u/4\"")" \
    "$(check in_progress IN_PROGRESS null null)" \
    "$(check waiting WAITING null "\"$u/5\"")" \
    "$(check requested REQUESTED null "\"$u/6\"")" \
    "$(check pending PENDING null "\"$u/7\"")" \
    "$(status expected EXPECTED null)" \
    "$(check dup COMPLETED '"FAILURE"' "\"$u/8\"")" \
    "$(status dup ERROR "\"$u/9\"")" \
    "$(check cancelled COMPLETED '"CANCELLED"' "\"$u/10\"")" \
    "$(check timed_out COMPLETED '"TIMED_OUT"' "\"$u/11\"")" \
    "$(check action_required COMPLETED '"ACTION_REQUIRED"' "\"$u/12\"")" \
    "$(check startup_failure COMPLETED '"STARTUP_FAILURE"' "\"$u/13\"")" \
    "$(check stale COMPLETED '"STALE"' "\"$u/14\"")" \
    "$(status Zeta FAILURE "\"$u/15\"")" \
    "$(status ci/build SUCCESS "\"$u/16\"")"
  LC_ALL=en_US.UTF-8 run hub ci-status -v
  assert_status 1
  assert_output_equals "$(printf '%s\n' \
    $'failure\tZeta\thttps://ci.test/15' \
    $'action_required\taction_required\thttps://ci.test/12' \
    $'cancelled\tcancelled\thttps://ci.test/10' \
    $'failure\tdup\thttps://ci.test/8' \
    $'error\tdup\thttps://ci.test/9' \
    $'stale\tstale\thttps://ci.test/14' \
    $'startup_failure\tstartup_failure\thttps://ci.test/13' \
    $'timed_out\ttimed_out\thttps://ci.test/11' \
    $'expected\texpected\t' \
    $'in_progress\tin_progress\t' \
    $'pending\tpending\thttps://ci.test/7' \
    $'queued\tqueued\thttps://ci.test/4' \
    $'requested\trequested\thttps://ci.test/6' \
    $'waiting\twaiting\thttps://ci.test/5' \
    $'success\tci/build\thttps://ci.test/16' \
    $'neutral\tneutral\thttps://ci.test/2' \
    $'skipped\tskipped\thttps://ci.test/3' \
    $'success\tsuccess\thttps://ci.test/1')"
}

@test "hub ci-status -v exits by the verdict and prints nothing when there is no check" {
  stub_rollup "$(tip main)" PENDING "$(check lint IN_PROGRESS null '"https://ci.test/2"')"
  run hub ci-status -v
  assert_status 2
  assert_output_equals $'in_progress\tlint\thttps://ci.test/2'
  stub_rollup "$(tip main)" SUCCESS
  run hub ci-status -v
  assert_success
  assert_output_equals ''
  stub_object "$(tip main)" '{"statusCheckRollup": null}'
  run hub ci-status -v
  assert_status 3
  assert_output_equals ''
}

@test "hub ci-status takes --verbose as -v" {
  stub_rollup "$(tip main)" FAILURE "$(check lint COMPLETED '"FAILURE"' '"https://ci.test/1"')"
  run hub ci-status --verbose main
  assert_status 1
  assert_output_equals $'failure\tlint\thttps://ci.test/1'
}

@test "hub ci-status refuses a commit GitHub does not have" {
  stub_object "$(tip main)" null
  run hub ci-status
  assert_status 1
  local repo=github.com/mislav/dotfiles
  assert_output_equals "hub ci-status: HEAD is not a commit of $repo"
  stub_object nosuch null
  run hub ci-status nosuch
  assert_status 1
  assert_output_equals "hub ci-status: nosuch is not a commit of $repo"
  stub_object 'main:docs' '{}'
  run hub ci-status main:docs
  assert_status 1
  assert_output_equals "hub ci-status: main:docs is not a commit of $repo"
}

@test "hub ci-status refuses a HEAD name that does not resolve in the repository" {
  run hub ci-status HEAD~1
  assert_status 1
  assert_output_equals 'hub ci-status: HEAD~1 is not a commit in this repository'
  run hub ci-status '@{upstream}'
  assert_status 1
  assert_output_equals 'hub ci-status: @{upstream} is not a commit in this repository'
  git checkout -q --orphan fresh
  run hub ci-status
  assert_status 1
  assert_output_equals 'hub ci-status: HEAD is not a commit in this repository'
  assert_gh_not_called
}

@test "hub ci-status refuses an empty commit" {
  run hub ci-status ''
  assert_status 1
  assert_line_equals 0 'hub ci-status: empty commit'
  assert_gh_not_called
}

@test "hub ci-status relays gh's error and exits 1" {
  stub_gh 'api graphql *' '{"data": null}' 4
  local message='gh: Could not resolve to a Repository with the name mislav/dotfiles.'
  PATH=$(failing_gh "$message"):$PATH run hub ci-status
  assert_status 1
  assert_output_equals 'gh: Could not resolve to a Repository with the name mislav/dotfiles.'
}

@test "hub ci-status names the host of the project's remote" {
  local rollup='{"statusCheckRollup": {"state": "SUCCESS", "contexts": {"nodes": []}}}'
  git remote set-url origin https://ghe.example.test/acme/tools.git
  stub_object "$(tip main)" "$rollup" ghe.example.test acme tools
  GH_HOST=ghe.example.test run hub ci-status
  assert_success
  assert_gh_called "api graphql --hostname ghe.example.test -f query=* -f owner=acme\
 -f name=tools -f expr=$(tip main) --jq *"
}

@test "hub ci-status works outside a repository with GH_REPO, passing HEAD to GitHub" {
  cd "$HUB_TEST_TMP"
  local rollup='{"statusCheckRollup": {"state": "PENDING", "contexts": {"nodes": []}}}'
  stub_object HEAD "$rollup" example.test cli cli
  GH_REPO=example.test/cli/cli run hub ci-status
  assert_status 2
  assert_output_equals pending
  local call='GH_REPO=example.test/cli/cli gh api graphql --hostname example.test *'
  assert_gh_called "$call -f owner=cli -f name=cli -f expr=HEAD *"
}

@test "hub ci-status refuses a repository without a GitHub remote" {
  git remote set-url origin https://gitlab.example.test/mislav/dotfiles.git
  run hub ci-status
  assert_status 1
  assert_output_equals 'hub ci-status: no GitHub remote found (looked for upstream, github, origin)'
  assert_gh_not_called
}

@test "hub ci-status refuses unknown options and a second commit" {
  run hub ci-status --verbose=1
  assert_status 1
  assert_line_equals 0 'hub ci-status: unknown option: --verbose=1'
  assert_line_equals 1 'Usage: hub ci-status [-v] [COMMIT]'
  run hub ci-status main topic
  assert_status 1
  assert_line_equals 0 'hub ci-status: unexpected argument: topic'
  run hub ci-status -vx
  assert_status 1
  assert_line_equals 0 'hub ci-status: unknown option: -x'
  assert_gh_not_called
}

@test "hub ci-status needs gh" {
  PATH=$(no_gh_path) run hub ci-status
  assert_status 1
  assert_output_equals \
    'hub ci-status: this command needs the GitHub CLI, gh (https://cli.github.com)'
}

@test "hub ci-status --help prints its manual" {
  run hub ci-status --help
  assert_success
  assert_line_equals 0 'Summary: Show the CI status of a commit.'
  assert_line_equals 1 'Usage: hub ci-status [-v] [COMMIT]'
  assert_gh_not_called
}
