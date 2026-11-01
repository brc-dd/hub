#!/usr/bin/env bats
# hub cherry-pick: commit URLs fetched from their repository and picked by their full id.

load test_helper

# setup_commit : octo/app and its fork jingweno/app served; app is a clone of octo/app at base;
# pick (on the fork's fix branch, octo/app's feature branch and pull request 12) and next (on
# top of pick, in the fork only) are commits app does not have yet.
setup_commit() {
  serve_github octo/app jingweno/app
  clone_served octo/app
  base=$(tip main)
  cd "$HUB_TEST_TMP" || return 1
  clone_served jingweno/app contrib
  git config user.name 'Jingwen Owen Ou'
  git config user.email jingweno@example.test
  printf 'fixed\n' >fix.txt
  git add fix.txt
  git commit -q -m 'Fix the build'
  pick=$(git rev-parse HEAD)
  printf 'more\n' >more.txt
  git add more.txt
  git commit -q -m 'Fix more'
  next=$(git rev-parse HEAD)
  git push -q origin HEAD:refs/heads/fix
  git push -q https://github.com/octo/app.git "$pick:refs/heads/feature" \
    "$pick:refs/pull/12/head"
  cd "$HUB_TEST_TMP/app" || return 1
}

# assert_picked COMMIT : HEAD is a copy of COMMIT on top of base, with its author and message.
assert_picked() {
  assert_equals "$(git rev-parse HEAD^)" "$base"
  assert_equals "$(git log -1 --format='%an|%B' HEAD)" "$(git log -1 --format='%an|%B' "$1")"
  assert_equals "$(git status --porcelain)" ''
}

# assert_untouched : HEAD is still base and no cherry-pick is in progress.
assert_untouched() {
  assert_equals "$(git rev-parse HEAD)" "$base"
  assert_equals "$(git rev-parse --verify --quiet CHERRY_PICK_HEAD)" ''
}

@test "hub cherry-pick picks the commit a full commit URL names, without asking gh" {
  setup_commit
  run hub cherry-pick "https://github.com/octo/app/commit/$pick"
  assert_success
  assert_picked "$pick"
  assert_equals "$(cat fix.txt)" fixed
  assert_gh_not_called
}

@test "hub cherry-pick expands a short id through gh's API on the URL's host" {
  setup_commit
  stub_gh "api --hostname github.com repos/jingweno/app/commits/${pick:0:7} --jq .sha" "$pick"
  run hub cherry-pick "https://github.com/jingweno/app/commit/${pick:0:7}"
  assert_success
  assert_picked "$pick"
  assert_gh_called "api --hostname github.com repos/jingweno/app/commits/${pick:0:7} --jq .sha"
}

@test "hub cherry-pick lowercases the full id gh answers with" {
  setup_commit
  stub_gh "api --hostname github.com repos/octo/app/commits/${pick:0:7} --jq .sha" "${pick^^}"
  run hub cherry-pick "https://github.com/octo/app/commit/${pick:0:7}"
  assert_success
  assert_picked "$pick"
}

@test "hub cherry-pick reads the other forms of a commit URL" {
  local url
  setup_commit
  stub_gh "api --hostname github.com repos/octo/app/commits/${pick:0:9} --jq .sha" "$pick"
  for url in "https://github.com/octo/app/pull/12/commits/${pick:0:9}" \
    "https://github.com/octo/app/commit/$pick.patch" \
    "https://github.com/octo/app/commit/$pick.diff" \
    "https://github.com/octo/app/commit/$pick?diff=split#diff-1" \
    "http://github.com/octo/app/commit/$pick/"; do
    run hub cherry-pick "$url"
    assert_success
    assert_picked "$pick"
    git reset -q --hard "$base"
  done
  assert_gh_called "api --hostname github.com repos/octo/app/commits/${pick:0:9} --jq .sha"
}

@test "hub cherry-pick refuses an id longer than a commit's, before asking gh" {
  local id
  setup_commit
  for id in "${pick}a" "$pick$pick"; do
    run hub cherry-pick "https://github.com/octo/app/commit/${id:0:64}"
    assert_status 1
    assert_output_equals \
      "hub cherry-pick: not a commit id: https://github.com/octo/app/commit/${id:0:64}"
  done
  assert_gh_not_called
  assert_untouched
}

@test "hub cherry-pick picks a pull request's commit from the pull request's repository" {
  setup_commit
  git -C "$(server_dir octo/app)" update-ref -d refs/heads/feature
  run hub cherry-pick "https://github.com/octo/app/pull/12/commits/$pick"
  assert_success
  assert_picked "$pick"
  run cat .git/FETCH_HEAD
  assert_output_contains "$pick"
  assert_output_contains "of https://github.com/octo/app"
}

@test "hub cherry-pick fetches from the URL in gh's protocol when no remote points at it" {
  setup_commit
  stub_gh 'config get git_protocol -h github.com' ssh
  run hub cherry-pick "https://github.com/jingweno/app/commit/$next"
  assert_success
  assert_equals "$(git rev-parse HEAD^)" "$base"
  assert_equals "$(git log -1 --format=%s)" 'Fix more'
  run cat .git/FETCH_HEAD
  assert_output_contains "of github.com:jingweno/app"
  assert_equals "$(git remote)" origin
}

@test "hub cherry-pick fetches through a remote whose URL names the repository in any case" {
  setup_commit
  git remote add fork git@github.com:JingWeno/App.git
  run hub cherry-pick "https://github.com/jingweno/app/commit/$pick"
  assert_success
  assert_picked "$pick"
  run cat .git/FETCH_HEAD
  assert_output_contains "of github.com:JingWeno/App"
}

@test "hub cherry-pick fetches through a remote whose name starts with a dash" {
  setup_commit
  git remote add -- -x https://github.com/jingweno/app.git
  run hub cherry-pick "https://github.com/jingweno/app/commit/$next"
  assert_success
  assert_equals "$(git log -1 --format=%s)" 'Fix more'
  run cat .git/FETCH_HEAD
  assert_output_contains "of https://github.com/jingweno/app"
}

@test "hub cherry-pick brings no tags in, even from a remote that fetches all tags" {
  setup_commit
  git -C "$(server_dir octo/app)" tag v1.0 "$pick"
  git config remote.origin.tagOpt --tags
  run hub cherry-pick "https://github.com/octo/app/commit/$pick"
  assert_success
  assert_picked "$pick"
  assert_equals "$(git tag)" ''
}

@test "hub cherry-pick passes the full id in lowercase" {
  setup_commit
  run hub cherry-pick -x "https://github.com/octo/app/commit/${pick^^}"
  assert_success
  assert_equals "$(git rev-parse HEAD^)" "$base"
  run git log -1 --format=%B
  assert_output_contains "(cherry picked from commit $pick)"
}

@test "hub cherry-pick keeps options, local commits and URLs in their order" {
  setup_commit
  git branch topic main
  git switch -q topic
  printf 'topic\n' >topic.txt
  git add topic.txt
  git commit -q -m 'A topic'
  git switch -q main
  run hub cherry-pick --signoff -X theirs refs/heads/topic \
    "https://github.com/jingweno/app/commit/$pick"
  assert_success
  assert_equals "$(git log -3 --format=%s)" $'Fix the build\nA topic\ninitial commit'
  assert_equals "$(git log -1 --format='%(trailers:key=Signed-off-by,valueonly)')" \
    'hub tests <hub@example.test>'
}

@test "hub cherry-pick picks every URL, in order" {
  setup_commit
  stub_gh "api --hostname github.com repos/jingweno/app/commits/${next:0:8} --jq .sha" "$next"
  run hub cherry-pick "https://github.com/octo/app/commit/$pick" \
    "https://github.com/jingweno/app/commit/${next:0:8}"
  assert_success
  assert_equals "$(git log -3 --format=%s)" $'Fix more\nFix the build\ninitial commit'
  assert_equals "$(git rev-parse HEAD~2)" "$base"
}

@test "hub cherry-pick asks the URL's host" {
  serve_github ghe.example.test/o/r
  clone_served ghe.example.test/o/r work
  printf 'ghe\n' >ghe.txt
  git add ghe.txt
  git commit -q -m 'On GHE'
  pick=$(git rev-parse HEAD)
  git push -q origin HEAD:refs/heads/topic
  git reset -q --hard HEAD^
  base=$(git rev-parse HEAD)
  git update-ref -d refs/remotes/origin/topic
  git reflog expire --expire=now --all
  git gc -q --prune=now
  export GH_HOST=ghe.example.test
  stub_gh 'config get git_protocol -h ghe.example.test' https
  stub_gh "api --hostname ghe.example.test repos/o/r/commits/${pick:0:7} --jq .sha" "$pick"
  run hub cherry-pick "https://GHE.example.test/o/r/commit/${pick:0:7}"
  assert_success
  assert_picked "$pick"
}

@test "hub cherry-pick relays gh's message and stops before fetching when gh fails" {
  setup_commit
  local lookup='api --hostname github.com repos/octo/app/commits/abcdef1 --jq .sha'
  run hub cherry-pick "https://github.com/octo/app/commit/$pick" \
    https://github.com/octo/app/commit/abcdef1
  assert_failure
  assert_output_equals "gh stub: unexpected call: gh $lookup"
  assert_gh_called "$lookup"
  assert_untouched
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub cherry-pick relays gh's exit status" {
  setup_commit
  stub_gh 'api --hostname github.com repos/octo/app/commits/abcdef1 --jq .sha' '' 4
  run hub cherry-pick https://github.com/octo/app/commit/abcdef1
  assert_status 4
  assert_untouched
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub cherry-pick refuses an answer from gh that is not a commit id" {
  setup_commit
  stub_gh 'api --hostname github.com repos/octo/app/commits/abcdef1 --jq .sha' ''
  run hub cherry-pick https://github.com/octo/app/commit/abcdef1
  assert_status 1
  assert_output_equals 'hub cherry-pick: no such commit: https://github.com/octo/app/commit/abcdef1'
  assert_untouched
}

@test "hub cherry-pick with a short id refuses without gh, before git runs" {
  setup_commit
  PATH=$(no_gh_path) run hub cherry-pick \
    "https://github.com/octo/app/commit/${pick:0:7}"
  assert_status 1
  assert_output_equals \
    'hub cherry-pick: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_untouched
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub cherry-pick relays git's message and picks nothing when a fetch fails" {
  setup_commit
  local missing=0123456789abcdef0123456789abcdef01234567
  run hub cherry-pick "https://github.com/octo/app/commit/$pick" \
    "https://github.com/octo/app/commit/$missing"
  assert_failure
  assert_output_contains "$missing"
  assert_output_lacks 'bad object'
  assert_untouched
}

@test "hub cherry-pick picks a commit app already has without reaching its repository" {
  setup_commit
  git fetch -q origin refs/heads/feature
  run hub cherry-pick "https://github.com/ghost/app/commit/$pick"
  assert_success
  assert_picked "$pick"
}

@test "hub cherry-pick returns git's status and leaves the pick to resume on a conflict" {
  setup_commit
  printf 'local\n' >fix.txt
  git add fix.txt
  git commit -q -m 'Local fix'
  run hub cherry-pick "https://github.com/octo/app/commit/$pick"
  assert_status 1
  assert_output_contains 'CONFLICT'
  assert_equals "$(git rev-parse CHERRY_PICK_HEAD)" "$pick"
  run git cherry-pick --abort
  assert_success
}

@test "hub cherry-pick without a URL is plain git cherry-pick" {
  setup_commit
  git fetch -q origin refs/heads/feature
  run hub cherry-pick FETCH_HEAD
  assert_success
  assert_picked "$pick"
  assert_gh_not_called
}

@test "hub cherry-pick leaves URLs after -- or --end-of-options to git" {
  setup_commit
  local url=https://github.com/octo/app/commit/$pick
  run hub cherry-pick -- "$url"
  assert_status 128
  assert_output_contains "bad revision '$url'"
  run hub cherry-pick --end-of-options "$url"
  assert_status 128
  assert_output_contains "bad revision '$url'"
  assert_untouched
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub cherry-pick leaves other GitHub URLs to git" {
  local url
  make_repo work
  for url in https://github.com/o/r https://github.com/o/r/pull/8 \
    https://github.com/o/r/commit/main https://github.com/o/r/commits/abcdef1 \
    https://github.com/o/r/pull/x/commits/abcdef1 https://github.com/o/r/issues/8 \
    https://gitlab.com/o/r/commit/abcdef1; do
    run hub cherry-pick "$url"
    assert_failure
    assert_output_contains "$url"
  done
  assert_gh_not_called
}

@test "hub cherry-pick refuses to run outside a work tree" {
  mkdir outside
  cd outside || return 1
  run hub cherry-pick https://github.com/o/r/commit/abcdef1
  assert_status 1
  assert_output_contains 'not a git repository'
  assert_gh_not_called
}

@test "hub cherry-pick -h prints git cherry-pick's usage" {
  make_repo work
  run hub cherry-pick -h https://github.com/o/r/commit/abcdef1
  assert_status 129
  assert_output_contains 'usage: git cherry-pick'
  assert_gh_not_called
}

@test "hub cherry-pick -xh is git's usage, before gh is asked or anything is fetched" {
  setup_commit
  local word
  for word in -xh -nh -esh; do
    run hub cherry-pick "$word" "https://github.com/octo/app/commit/$pick"
    assert_status 129
    assert_output_contains 'usage: git cherry-pick'
    run hub cherry-pick "$word" "https://github.com/octo/app/commit/${pick:0:7}"
    assert_status 129
  done
  assert_gh_not_called
  assert_untouched
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub cherry-pick --help hands the line to git for its manual" {
  run hub --noop cherry-pick --help https://github.com/o/r/commit/abcdef1
  assert_success
  assert_output_equals 'git cherry-pick --help https://github.com/o/r/commit/abcdef1'
  assert_gh_not_called
}

@test "hub cherry-pick --help-all is git's usage, before gh is asked" {
  make_repo work
  run hub cherry-pick --help-all https://github.com/o/r/commit/abcdef1
  assert_status 129
  assert_gh_not_called
}

@test "hub help cherry-pick prints hub's manual, ending with the pointer to git's" {
  run hub help cherry-pick
  assert_success
  assert_line_equals 0 'Summary: Cherry-pick a commit from its GitHub URL.'
  assert_line_equals -1 "git's own manual: git cherry-pick --help"
}

@test "hub --noop cherry-pick looks the id up and prints the fetch and the pick" {
  setup_commit
  stub_gh "api --hostname github.com repos/octo/app/commits/${pick:0:7} --jq .sha" "$pick"
  run hub --noop cherry-pick -x "https://github.com/octo/app/commit/${pick:0:7}"
  assert_success
  assert_output_equals "git fetch --quiet --no-tags --refmap= -- origin $pick
git cherry-pick -x $pick"
  assert_untouched
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}
