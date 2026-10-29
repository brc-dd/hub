#!/usr/bin/env bats
load ../test_helper

@test "push to multiple remotes" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git staging=git@github.com:mislav/dotfiles-staging.git
  run hub --noop push origin,staging,qa cool-feature
  assert_success
  assert_output_equals $'git push origin cool-feature\ngit push staging cool-feature\ngit push qa cool-feature'
  assert_gh_not_called
}

@test "push to multiple remotes with nothing after the list pushes the current branch" {
  make_repo dotfiles
  git checkout -q -b cool-feature
  run hub --noop push origin,staging
  assert_success
  assert_output_equals $'git push origin cool-feature\ngit push staging cool-feature'
}

@test "push options are passed on as given, without adding the current branch" {
  make_repo dotfiles
  run hub --noop push origin,staging --force-with-lease
  assert_success
  assert_output_equals $'git push origin --force-with-lease\ngit push staging --force-with-lease'
}

@test "push --delete without a ref does not delete the current branch" {
  make_repo dotfiles
  run hub --noop push origin,staging --delete
  assert_success
  assert_output_equals $'git push origin --delete\ngit push staging --delete'
}

@test "push --tags, --all and --mirror get no ref added" {
  make_repo dotfiles
  local opt
  for opt in --tags --all --mirror; do
    run hub --noop push origin,staging "$opt"
    assert_success
    assert_output_equals "git push origin $opt"$'\n'"git push staging $opt"
  done
}

@test "push keeps every argument and its order, option values included" {
  make_repo dotfiles
  run hub --noop push origin,staging --push-option ci.skip --dry-run HEAD
  assert_success
  assert_output_equals $'git push origin --push-option ci.skip --dry-run HEAD\ngit push staging --push-option ci.skip --dry-run HEAD'
  run hub --noop push origin,staging -o 'a b,c' -- main:main
  assert_success
  assert_output_equals $'git push origin -o a\\ b\\,c -- main:main\ngit push staging -o a\\ b\\,c -- main:main'
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

@test "an option with a comma in it is not a list of remotes" {
  make_repo dotfiles
  run hub --noop push --push-option=a,b origin main
  assert_success
  assert_output_equals "git push --push-option=a,b origin main"
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
  run git -C "$HUB_TEST_TMP/never.git" rev-parse --verify -q refs/heads/main
  assert_failure
}

@test "push --delete without a ref is left for git to refuse, and deletes nothing" {
  make_repo dotfiles
  local r
  for r in one two; do
    git init -q --bare "$HUB_TEST_TMP/$r.git"
    git remote add "$r" "$HUB_TEST_TMP/$r.git"
    git push -q "$r" main
  done
  run hub push one,two --delete
  assert_failure
  assert_output_contains "--delete doesn't make sense without any refs"
  git -C "$HUB_TEST_TMP/one.git" rev-parse --verify -q refs/heads/main
  git -C "$HUB_TEST_TMP/two.git" rev-parse --verify -q refs/heads/main
}
