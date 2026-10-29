#!/usr/bin/env bats
load ../test_helper

SHA=a319d88b3f4b58a1b8d4a5ef2d1b8e5a6f7c8d9e

@test "cherry-pick of a commit URL fetches that commit from its repository, then cherry-picks it" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop cherry-pick "https://github.com/jingweno/dotfiles/commit/$SHA"
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA
git cherry-pick $SHA"
  [[ $(gh_calls) != *api* ]]
}

@test "cherry-pick of a commit URL with a short SHA looks up the full SHA, which the fetch needs" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'api --hostname github.com repos/jingweno/dotfiles/commits/a319d88 --jq .sha' "$SHA"
  run hub --noop cherry-pick https://github.com/jingweno/dotfiles/commit/a319d88
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA
git cherry-pick $SHA"
}

@test "cherry-pick fetches through a remote that points at the commit's repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git jingweno=git@github.com:JingWeno/dotfiles.git
  run hub --noop cherry-pick "https://github.com/jingweno/dotfiles/commit/$SHA"
  assert_success
  assert_line_equals 0 "git fetch --no-tags jingweno $SHA"
  assert_gh_not_called
}

@test "cherry-pick of a pull request's commit fetches the pull request's head" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop cherry-pick https://github.com/mislav/dotfiles/pull/12/commits/a319d88
  assert_success
  assert_output_equals "git fetch --no-tags origin refs/pull/12/head
git cherry-pick a319d88"
  assert_gh_not_called
}

@test "cherry-pick USER@SHA fetches from USER's fork of the current project" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'api --hostname github.com repos/jingweno/dotfiles/commits/a319d88 --jq .sha' "$SHA"
  run hub --noop cherry-pick jingweno@a319d88
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA
git cherry-pick $SHA"
}

@test "cherry-pick USER@SHA uses a remote for that fork when there is one" {
  make_repo dotfiles upstream=https://github.com/mislav/dotfiles.git jingweno=https://github.com/jingweno/dotfiles.git
  run hub --noop cherry-pick "jingweno@$SHA"
  assert_success
  assert_output_equals "git fetch --no-tags jingweno $SHA
git cherry-pick $SHA"
  assert_gh_not_called
}

@test "cherry-pick keeps the options given before the commit" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop cherry-pick -x -m 1 https://github.com/mislav/dotfiles/pull/12/commits/a319d88
  assert_success
  assert_line_equals 1 "git cherry-pick -x -m 1 a319d88"
}

@test "cherry-pick always tells gh the commit's host" {
  git config --global hub.host ghe.example.com
  make_repo app origin=git@ghe.example.com:team/app.git
  # Only the call with the host has an answer: any other one fails, and so would hub.
  stub_gh 'api --hostname ghe.example.com repos/team/app/commits/a319d88 --jq .sha' "$SHA"
  run hub --noop cherry-pick https://ghe.example.com/team/app/commit/a319d88
  assert_success
  assert_output_equals "git fetch --no-tags origin $SHA
git cherry-pick $SHA"
  # Also when that host is gh's default anyway, and for USER@SHA, on the current project's host.
  export GH_HOST=ghe.example.com
  run hub --noop cherry-pick https://ghe.example.com/team/app/commit/a319d88
  assert_success
  assert_line_equals 0 "git fetch --no-tags origin $SHA"
  stub_gh 'api --hostname ghe.example.com repos/alice/app/commits/a319d88 --jq .sha' "$SHA"
  run hub --noop cherry-pick alice@a319d88
  assert_success
  assert_line_equals 0 "git fetch --no-tags https://ghe.example.com/alice/app.git $SHA"
}

@test "cherry-pick looks up a github.com commit on github.com, whatever host gh defaults to" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  export GH_HOST=enterprise.example
  stub_gh 'api --hostname github.com repos/jingweno/dotfiles/commits/a319d88 --jq .sha' "$SHA"
  run hub --noop cherry-pick https://github.com/jingweno/dotfiles/commit/a319d88
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA
git cherry-pick $SHA"
  run hub --noop cherry-pick jingweno@a319d88
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA
git cherry-pick $SHA"
  # No GH_HOST, and gh is logged in to enterprise.example only, which makes that gh's default host.
  unset GH_HOST
  mkdir -p "$GH_CONFIG_DIR"
  printf 'enterprise.example:\n    user: me\n' >"$GH_CONFIG_DIR/hosts.yml"
  run hub --noop cherry-pick https://github.com/jingweno/dotfiles/commit/a319d88
  assert_success
  assert_line_equals 0 "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA"
}

@test "cherry-pick without a commit URL or USER@SHA last is plain git cherry-pick" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop cherry-pick a319d88
  assert_success
  assert_output_equals "git cherry-pick a319d88"
  run hub --noop cherry-pick -x main~2 topic
  assert_output_equals "git cherry-pick -x main~2 topic"
  run hub --noop cherry-pick 'HEAD@{1}'
  assert_output_equals "git cherry-pick $(printf %q 'HEAD@{1}')"
  run hub --noop cherry-pick --continue
  assert_output_equals "git cherry-pick --continue"
  run hub --noop cherry-pick -h
  assert_output_equals "git cherry-pick -h"
  run hub --noop cherry-pick
  assert_output_equals "git cherry-pick"
  run hub --noop cherry-pick https://github.com/mislav/dotfiles/pull/12
  assert_output_equals "git cherry-pick https://github.com/mislav/dotfiles/pull/12"
  assert_gh_not_called
}

@test "cherry-pick really runs git cherry-pick" {
  make_repo dotfiles
  git checkout -q -b topic
  git commit -q --allow-empty -m "topic work"
  git checkout -q main
  run hub cherry-pick --allow-empty topic
  assert_success
  [[ $(git log -1 --format=%s) == "topic work" ]]
  assert_gh_not_called
}

@test "cherry-pick leaves a local revision that looks like USER@SHA to git" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git branch jingweno@a319d88
  run hub --noop cherry-pick jingweno@a319d88
  assert_success
  assert_output_equals "git cherry-pick jingweno@a319d88"
  assert_gh_not_called
}

@test "cherry-pick USER@SHA needs a GitHub remote for the current project" {
  make_repo dotfiles
  run hub --noop cherry-pick jingweno@a319d88
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
}

@test "cherry-pick aborts when the commit can't be found" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'api --hostname github.com repos/jingweno/dotfiles/commits/a319d88 --jq .sha' '' 1
  run hub --noop cherry-pick https://github.com/jingweno/dotfiles/commit/a319d88
  assert_failure
  assert_output_equals "Aborted: could not find commit https://github.com/jingweno/dotfiles/commit/a319d88"
}

@test "cherry-pick of a commit URL really fetches the commit and applies it" {
  git init -q --bare "$HUB_TEST_TMP/fork.git"
  make_repo seed origin="$HUB_TEST_TMP/fork.git"
  echo fixed >build.txt
  git add build.txt
  git commit -q -m "Fix the build"
  local sha
  sha=$(git rev-parse HEAD)
  git push -q origin main
  cd "$HUB_TEST_TMP"
  make_repo work origin=https://github.com/mislav/dotfiles.git
  git config --global url."$HUB_TEST_TMP/fork.git".insteadOf https://github.com/jingweno/dotfiles.git
  run hub cherry-pick "https://github.com/jingweno/dotfiles/commit/$sha"
  assert_success
  [[ $(git log -1 --format=%s) == "Fix the build" && -f build.txt ]]
  [[ $(git rev-list --count HEAD) == 2 ]]
}

@test "cherry-pick --help prints the manual" {
  run hub cherry-pick --help
  assert_success
  assert_output_contains "Usage: hub cherry-pick [git-cherry-pick options] COMMIT-URL"
}
