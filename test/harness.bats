#!/usr/bin/env bats
load test_helper

@test "fixtures never touch the repository named by the caller's environment" {
  git init -q -b main victim
  git -C victim commit -q --allow-empty -m v1
  echo staged >victim/f
  git -C victim add f
  mkdir hooks
  local before after
  before=$(git -C victim rev-parse HEAD && git -C victim diff --cached --stat && git -C victim remote && git -C victim config --local --list)
  run env GIT_DIR="$PWD/victim/.git" GIT_WORK_TREE="$PWD/victim" GIT_INDEX_FILE="$PWD/victim/.git/index" \
    GIT_CONFIG_PARAMETERS="'core.hooksPath'='$PWD/hooks'" GIT_CEILING_DIRECTORIES=/ GH_REPO=o/r GH_HOST=ghe.example.com \
    BATS_TEST_TMPDIR="$HUB_TEST_TMP" HUB_NOOP=1 CDPATH="$PWD" \
    bash -c 'source "$HUB_TEST_ROOT/test/test_helper.bash" && hub_test_setup && make_repo r origin=https://github.com/mislav/r.git \
      && git commit -q --allow-empty -m fixture && { git config core.hooksPath || echo no-hooks; } && hub remote add alice && git remote && hub browse -u'
  assert_success
  assert_output_equals $'no-hooks\nalice\norigin\nhttps://github.com/mislav/r'
  after=$(git -C victim rev-parse HEAD && git -C victim diff --cached --stat && git -C victim remote && git -C victim config --local --list)
  assert_equals "$after" "$before"
}

@test "the gh stub replays the last matching response and rejects unexpected calls" {
  stub_gh 'api *' 'first'
  stub_gh 'api user' 'second' 3
  run gh api user
  assert_output_equals second
  [[ $status -eq 3 ]]
  run gh api other
  assert_output_equals first
  run gh nothing registered
  [[ $status -eq 97 ]]
  assert_gh_called 'api user'
  assert_gh_called 'nothing *'
}

@test "a served repository is reached through github.com URLs of every protocol" {
  serve_github o/r ghe.example/o/r
  clone_served o/r
  assert_equals "$(remote_url origin)" https://github.com/o/r.git
  assert_equals "$(git remote get-url origin)" https://github.com/o/r.git # no URL rewriting: hub sees what the user has
  git commit -q --allow-empty -m local
  git push -q origin main
  assert_equals "$(server_ref o/r main)" "$(git rev-parse HEAD)"
  git remote set-url origin git@github.com:o/r.git
  git commit -q --allow-empty -m over-scp-url
  git push -q origin main
  assert_equals "$(server_ref o/r main)" "$(git rev-parse HEAD)"
  git remote set-url origin ssh://git@github.com/o/r.git
  git commit -q --allow-empty -m over-ssh-url
  git push -q origin main:topic
  assert_equals "$(server_ref o/r topic)" "$(git rev-parse HEAD)"
  assert_equals "$(server_branches o/r)" $'main\ntopic'
  git remote add ghe https://ghe.example/o/r.git
  git fetch -q ghe
  assert_equals "$(git rev-parse ghe/main)" "$(server_ref ghe.example/o/r main)"
  [[ $(server_ref o/r main) != $(server_ref ghe.example/o/r main) ]]
  run git fetch -q origin nothing-here
  assert_failure
  run git clone -q https://github.com/o/unserved.git
  assert_failure
  assert_output_contains 'nothing is served'
}
