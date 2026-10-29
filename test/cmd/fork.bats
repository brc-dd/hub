#!/usr/bin/env bats
load ../test_helper

@test "fork adds the fork as a remote named after your login, then fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork
  assert_success
  assert_output_equals $'gh repo fork --remote --remote-name mislav\ngit fetch mislav'
  assert_gh_called 'config get user -h github.com'
}

@test "fork --org forks into the organization and names the remote after it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --org myorg
  assert_success
  assert_output_equals $'gh repo fork --remote --remote-name myorg --org myorg\ngit fetch myorg'
  run hub --noop fork --org=myorg
  assert_output_equals $'gh repo fork --remote --remote-name myorg --org myorg\ngit fetch myorg'
}

@test "fork --remote-name picks the remote name" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --remote-name fork
  assert_success
  assert_output_equals $'gh repo fork --remote --remote-name fork\ngit fetch fork'
  run hub --noop fork --remote-name=mine --org myorg
  assert_output_equals $'gh repo fork --remote --remote-name mine --org myorg\ngit fetch mine'
  assert_gh_not_called
}

@test "fork --no-remote only forks" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --no-remote
  assert_success
  assert_output_equals "gh repo fork --remote=false"
  run hub --noop fork --no-remote --org myorg
  assert_output_equals "gh repo fork --remote=false --org myorg"
  assert_gh_not_called
}

@test "fork passes other options to gh" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --fork-name dots --default-branch-only
  assert_success
  assert_output_equals $'gh repo fork --remote --remote-name mislav --fork-name dots --default-branch-only\ngit fetch mislav'
}

@test "fork uses your login on the repository's enterprise host" {
  make_repo app origin=git@ghe.example.com:corp/app.git
  export GH_HOST=ghe.example.com
  stub_gh 'config get user -h ghe.example.com' 'mona'
  run hub --noop fork
  assert_success
  assert_output_equals $'gh repo fork --remote --remote-name mona\ngit fetch mona'
}

@test "fork fetches the new remote once gh has added it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  git init -q --bare "$HUB_TEST_TMP/fork.git"
  git push -q "$HUB_TEST_TMP/fork.git" main
  git remote add mislav "$HUB_TEST_TMP/fork.git"   # what gh would have added
  stub_gh 'repo fork --remote --remote-name mislav' ''
  run hub fork
  assert_success
  git rev-parse --verify -q refs/remotes/mislav/main
}

@test "fork does not fetch when gh fails" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  git init -q --bare "$HUB_TEST_TMP/fork.git"
  git push -q "$HUB_TEST_TMP/fork.git" main
  git remote add mislav "$HUB_TEST_TMP/fork.git"
  stub_gh 'repo fork *' '' 1
  run hub fork
  assert_failure
  ! git rev-parse --verify -q refs/remotes/mislav/main
}

@test "fork needs a repository with a GitHub remote" {
  run hub --noop fork
  assert_failure
  assert_output_contains "not a git repository"
  make_repo local-only
  run hub --noop fork
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
  assert_gh_not_called
}

@test "fork --help prints the manual" {
  run hub fork --help
  assert_success
  assert_output_contains 'renamed to "upstream"'
}
