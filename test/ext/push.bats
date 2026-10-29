#!/usr/bin/env bats
load ../test_helper

@test "push to multiple remotes" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git staging=git@github.com:mislav/dotfiles-staging.git
  run hub --noop push origin,staging,qa cool-feature
  assert_success
  assert_output_equals $'git push origin cool-feature\ngit push staging cool-feature\ngit push qa cool-feature'
  assert_gh_not_called
}

@test "push to multiple remotes without a ref pushes the current branch" {
  make_repo dotfiles
  git checkout -q -b cool-feature
  run hub --noop push origin,staging
  assert_success
  assert_output_equals $'git push origin cool-feature\ngit push staging cool-feature'
}

@test "push options are kept and the branch is still appended" {
  make_repo dotfiles
  run hub --noop push origin,staging --force-with-lease
  assert_success
  assert_output_equals $'git push origin --force-with-lease main\ngit push staging --force-with-lease main'
}

@test "push with a single remote is plain git push" {
  run hub --noop push origin cool-feature
  assert_success
  assert_output_equals "git push origin cool-feature"
}

@test "push with no arguments is plain git push" {
  run hub --noop push
  assert_success
  assert_output_equals "git push"
}

@test "push to multiple remotes from a detached HEAD aborts" {
  make_repo dotfiles
  git checkout -q --detach
  run hub --noop push origin,staging
  assert_failure
  assert_output_contains "Aborted: not currently on any branch."
}

@test "push stops at the first remote that fails" {
  make_repo dotfiles
  git init -q --bare "$HUB_TEST_TMP/good.git"
  git remote add good "$HUB_TEST_TMP/good.git"
  git remote add bad "$HUB_TEST_TMP/does-not-exist.git"
  git init -q --bare "$HUB_TEST_TMP/never.git"
  git remote add never "$HUB_TEST_TMP/never.git"
  run hub push good,bad,never main
  assert_failure
  git -C "$HUB_TEST_TMP/good.git" rev-parse --verify -q refs/heads/main
  ! git -C "$HUB_TEST_TMP/never.git" rev-parse --verify -q refs/heads/main
}
