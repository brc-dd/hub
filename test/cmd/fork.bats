#!/usr/bin/env bats
load ../test_helper

@test "fork forks hub's project by name, then adds the fork as a remote named after your login and fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false\ngit remote add mislav https://github.com/mislav/dotfiles.git\ngit fetch mislav'
  assert_gh_called 'config get user -h github.com'
}

@test "fork forks the upstream remote's repository, whatever gh's default repository is" {
  make_repo dotfiles origin=https://github.com/hubot/dotfiles.git upstream=https://github.com/dotcom/dotfiles.git
  git config remote.origin.gh-resolved base # what gh repo set-default origin records
  run hub --noop fork
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false\ngit remote add mislav https://github.com/mislav/dotfiles.git\ngit fetch mislav'
}

@test "fork names the project's host for gh, and uses your login and the protocol on that host" {
  make_repo app origin=git@ghe.example.com:corp/app.git
  git config hub.host ghe.example.com # gh's default host stays github.com
  stub_gh 'config get user -h ghe.example.com' 'mona'
  stub_gh 'config get git_protocol -h ghe.example.com' 'ssh'
  run hub --noop fork
  assert_success
  assert_output_equals $'gh repo fork ghe.example.com/corp/app --clone=false\ngit remote add mona git@ghe.example.com:mona/app.git\ngit fetch mona'
}

@test "fork forks GH_REPO when it is set" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  export GH_REPO=ghe.example.com/corp/app
  stub_gh 'config get user -h ghe.example.com' 'mona'
  run hub --noop fork
  assert_success
  assert_output_equals $'gh repo fork ghe.example.com/corp/app --clone=false\ngit remote add mona https://ghe.example.com/mona/app.git\ngit fetch mona'
}

@test "fork --org forks into the organization and names the remote after it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --org myorg
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg\ngit remote add myorg https://github.com/myorg/dotfiles.git\ngit fetch myorg'
  run hub --noop fork --org=myorg
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg\ngit remote add myorg https://github.com/myorg/dotfiles.git\ngit fetch myorg'
  [[ $(gh_calls) != *"config get user"* ]]
}

@test "fork --remote-name picks the remote name" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --remote-name fork
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false\ngit remote add fork https://github.com/mislav/dotfiles.git\ngit fetch fork'
  run hub --noop fork --remote-name=mine --org myorg
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg\ngit remote add mine https://github.com/myorg/dotfiles.git\ngit fetch mine'
}

@test "fork --fork-name names the fork, and the remote's URL with it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --fork-name dots
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false --fork-name dots\ngit remote add mislav https://github.com/mislav/dots.git\ngit fetch mislav'
  run hub --noop fork --fork-name=dots --org myorg
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg --fork-name dots\ngit remote add myorg https://github.com/myorg/dots.git\ngit fetch myorg'
}

@test "fork --no-remote only forks" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --no-remote
  assert_success
  assert_output_equals "gh repo fork github.com/dotcom/dotfiles --clone=false"
  run hub --noop fork --remote=false --org myorg --fork-name dots
  assert_success
  assert_output_equals "gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg --fork-name dots"
  assert_gh_not_called
}

@test "fork passes other options to gh and takes gh's --remote as its default" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --default-branch-only --remote
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false --default-branch-only\ngit remote add mislav https://github.com/mislav/dotfiles.git\ngit fetch mislav'
}

@test "fork keeps a remote that already points at the fork and fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:Mislav/dotfiles.git
  run hub --noop fork
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false\nUsing the existing remote \'mislav\' for mislav/dotfiles.\ngit fetch mislav'
  git remote add mine https://github.com/myorg/dots.git
  run hub --noop fork --org myorg --fork-name dots --remote-name mine
  assert_success
  assert_output_equals $'gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg --fork-name dots\nUsing the existing remote \'mine\' for myorg/dots.\ngit fetch mine'
}

@test "fork stops before forking when the remote name is taken by another repository" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  stub_gh 'repo fork *' ''
  run hub fork --remote-name origin
  assert_failure
  assert_output_equals "Aborted: a remote named 'origin' already exists for https://github.com/dotcom/dotfiles.git, not for the fork mislav/dotfiles; pick another name with --remote-name NAME."
  git remote add mislav ../elsewhere.git
  run hub fork
  assert_failure
  assert_output_equals "Aborted: a remote named 'mislav' already exists for ../elsewhere.git, not for the fork mislav/dotfiles; pick another name with --remote-name NAME."
  run hub fork --fork-name dots
  assert_failure
  assert_output_contains "not for the fork mislav/dots;"
  [[ $(gh_calls) != *"repo fork"* ]]
}

@test "fork refuses names it could not use, a repository argument and --clone before running gh" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub fork --remote-name 'my fork'
  assert_failure
  assert_output_equals "Aborted: 'my fork' is not a valid remote name."
  run hub fork --remote-name -f
  assert_failure
  assert_output_equals "Aborted: '-f' is not a valid remote name."
  run hub fork --fork-name 'my dots'
  assert_failure
  assert_output_equals "Aborted: 'my dots' is not a repository name GitHub keeps as it is; use letters, digits, '-', '_' and '.'."
  run hub fork --org=
  assert_failure
  assert_output_equals "hub fork: --org needs a value"
  run hub fork --remote-name
  assert_failure
  assert_output_equals "hub fork: --remote-name needs a value"
  run hub fork other/repo
  assert_failure
  assert_output_contains "Usage: hub fork"
  run hub fork --clone
  assert_failure
  assert_output_contains "does not clone it"
  assert_gh_not_called
}

@test "fork adds the remote itself and fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  git init -q --bare "$HUB_TEST_TMP/fork.git"
  git push -q "$HUB_TEST_TMP/fork.git" main
  # Fetch "from GitHub" out of the local bare repository.
  git config --global url."$HUB_TEST_TMP/fork.git".insteadOf https://github.com/mislav/dotfiles.git
  stub_gh 'repo fork github.com/dotcom/dotfiles --clone=false' ''
  run hub fork
  assert_success
  [[ $(git config remote.mislav.url) == https://github.com/mislav/dotfiles.git ]]
  git rev-parse --verify -q refs/remotes/mislav/main
}

@test "fork adds no remote and fetches nothing when gh fails" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  stub_gh 'repo fork *' 'could not fork' 1
  run hub fork
  assert_failure
  assert_output_equals "could not fork"
  ! git remote get-url mislav
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
  assert_output_contains "--fork-name NAME"
}
