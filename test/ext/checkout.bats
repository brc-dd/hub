#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12

@test "checkout of a pull request URL hands off to gh pr checkout" {
  run hub --noop checkout "$PR"
  assert_success
  assert_output_equals "gh pr checkout $PR"
  assert_gh_not_called
}

@test "checkout of a pull request URL runs gh for real" {
  stub_gh "pr checkout $PR -b fix-build" ''
  run hub checkout "$PR" fix-build
  assert_success
  assert_gh_called "pr checkout $PR -b fix-build"
}

@test "checkout of a pull request URL into a named branch" {
  run hub --noop checkout "$PR" fix-build
  assert_success
  assert_output_equals "gh pr checkout $PR -b fix-build"
}

@test "checkout -b BRANCH with a pull request URL names the branch" {
  run hub --noop checkout -b fix-build "$PR"
  assert_success
  assert_output_equals "gh pr checkout $PR -b fix-build"
  run hub --noop checkout -bfix-build "$PR"
  assert_success
  assert_output_equals "gh pr checkout $PR -b fix-build"
}

@test "checkout passes --detach and --recurse-submodules on to gh" {
  run hub --noop checkout --recurse-submodules "$PR" -d
  assert_success
  assert_output_equals "gh pr checkout $PR --recurse-submodules --detach"
}

@test "checkout of any page of a pull request, or on an enterprise host, goes to gh" {
  run hub --noop checkout "$PR/files"
  assert_success
  assert_output_equals "gh pr checkout $PR/files"
  git config --global hub.host ghe.example.com
  run hub --noop checkout https://ghe.example.com/team/app/pull/7
  assert_success
  assert_output_equals "gh pr checkout https://ghe.example.com/team/app/pull/7"
}

@test "checkout -f with a pull request URL is refused, because gh's --force resets the branch" {
  run hub --noop checkout -f "$PR"
  assert_failure
  assert_output_contains "Aborted: -f can't be used with a pull request URL"
  assert_output_contains "gh pr checkout --force $PR"
  assert_gh_not_called
}

@test "checkout options gh doesn't share are refused with a pull request URL" {
  run hub --noop checkout -q "$PR"
  assert_failure
  assert_output_equals "Aborted: -q can't be used with a pull request URL (gh pr checkout accepts -b BRANCH, --detach and --recurse-submodules)"
  run hub --noop checkout --track "$PR"
  assert_failure
  run hub --noop checkout "$PR" -- README.md
  assert_failure
  assert_gh_not_called
}

@test "checkout of a pull request URL takes at most one branch name, after the URL" {
  run hub --noop checkout "$PR" one two
  assert_failure
  assert_output_equals "Usage: hub checkout PULLREQ-URL [BRANCH]"
  run hub --noop checkout main "$PR"
  assert_failure
  assert_output_equals "Usage: hub checkout PULLREQ-URL [BRANCH]"
  assert_gh_not_called
}

@test "checkout without a pull request URL is plain git checkout" {
  run hub --noop checkout main
  assert_success
  assert_output_equals "git checkout main"
  run hub --noop checkout -b feature origin/main
  assert_output_equals "git checkout -b feature origin/main"
  run hub --noop checkout
  assert_output_equals "git checkout"
  assert_gh_not_called
}

@test "checkout really runs git checkout" {
  make_repo dotfiles
  git branch feature
  run hub checkout -q feature
  assert_success
  [[ $(git symbolic-ref --short HEAD) == feature ]]
  assert_gh_not_called
}

@test "checkout of other GitHub URLs, or pull requests on unknown hosts, is plain git" {
  run hub --noop checkout https://github.com/mislav/dotfiles/issues/12
  assert_output_equals "git checkout https://github.com/mislav/dotfiles/issues/12"
  run hub --noop checkout https://gitlab.com/mislav/dotfiles/pull/12
  assert_output_equals "git checkout https://gitlab.com/mislav/dotfiles/pull/12"
  assert_gh_not_called
}

@test "checkout treats a URL after -- as a path" {
  run hub --noop checkout main -- "$PR"
  assert_success
  assert_output_equals "git checkout main -- $PR"
}

@test "checkout --help prints the manual, while -h is left to git" {
  run hub checkout --help
  assert_success
  assert_output_contains "Usage: hub checkout PULLREQ-URL [BRANCH]"
  run hub --noop checkout -h
  assert_output_equals "git checkout -h"
}
