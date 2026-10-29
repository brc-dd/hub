#!/usr/bin/env bats
load ../test_helper

# serve_github OWNER/REPO... : make https://github.com/OWNER/REPO.git resolve to a local bare repo
# with one commit (git's url.insteadOf), and allow only local transports so nothing reaches the network.
serve_github() {
  local repo dir tree
  git config --global url."$HUB_TEST_TMP/srv/".insteadOf https://github.com/
  export GIT_ALLOW_PROTOCOL=file
  for repo in "$@"; do
    dir=$HUB_TEST_TMP/srv/$repo.git
    git init -q --bare "$dir"
    tree=$(git -C "$dir" hash-object -t tree -w --stdin </dev/null)
    git -C "$dir" update-ref refs/heads/main "$(git -C "$dir" commit-tree -m "initial commit" "$tree")"
  done
}

@test "fetch USER adds a remote for USER's fork and fetches it" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch alice'
}

@test "fetch a comma-separated list of users with --multiple" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch alice,bob
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit remote add bob https://github.com/bob/dotfiles.git\ngit fetch --multiple alice bob'
}

@test "fetch --multiple USER USER2 adds the missing remotes and fetches them with the options first" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch --multiple alice origin bob alice --prune --depth 1
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/dotfiles.git
git remote add bob https://github.com/bob/dotfiles.git
git fetch --multiple --prune --depth 1 alice origin bob"
  run hub --noop fetch -m alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch --multiple alice'
}

@test "fetch --multiple takes the names up to the first option" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch --multiple alice --prune bob
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch --multiple --prune bob alice'
  run hub --noop fetch --multiple --prune alice
  assert_success
  assert_output_equals "git fetch --multiple --prune alice"
  run hub --noop fetch --multiple
  assert_output_equals "git fetch --multiple"
}

@test "fetch --multiple leaves remotes and remote groups as they are, and URLs and paths to git" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  git config remotes.everyone "origin upstream"
  run hub --noop fetch --multiple origin everyone upstream --prune
  assert_success
  assert_output_equals "git fetch --multiple --prune origin everyone upstream"
  run hub --noop fetch --multiple alice https://github.com/bob/dotfiles.git --prune
  assert_success
  assert_output_equals "git fetch --multiple alice https://github.com/bob/dotfiles.git --prune"
  run hub --noop fetch --multiple alice ../other.git
  assert_output_equals "git fetch --multiple alice ../other.git"
  run hub --noop fetch --multiple alice not.a.login
  assert_output_equals "git fetch --multiple alice not.a.login"
  assert_gh_not_called
}

@test "existing remotes in the list are not added again" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch origin,alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch --multiple origin alice'
}

@test "a list of existing remotes is fetched without asking gh" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  run hub --noop fetch origin,upstream
  assert_success
  assert_output_equals "git fetch --multiple origin upstream"
  assert_gh_not_called
}

@test "a name given twice is added and fetched once" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch alice,alice,
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch alice'
}

@test "arguments after the list stay in place" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch alice,bob --prune --depth 1
  assert_success
  assert_line_equals 2 "git fetch --multiple alice bob --prune --depth 1"
  run hub --noop fetch alice main:refs/remotes/alice/main --no-tags
  assert_success
  assert_line_equals 1 "git fetch alice main:refs/remotes/alice/main --no-tags"
}

@test "remote groups are not mistaken for users" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git config remotes.everyone "origin"
  run hub --noop fetch everyone
  assert_success
  assert_output_equals "git fetch everyone"
  run hub --noop fetch everyone,alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch --multiple everyone alice'
}

@test "options, URLs, paths and existing remotes pass through" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  touch alice
  run hub --noop fetch origin
  assert_output_equals "git fetch origin"
  run hub --noop fetch origin main --prune
  assert_output_equals "git fetch origin main --prune"
  run hub --noop fetch --all
  assert_output_equals "git fetch --all"
  run hub --noop fetch --prune bob
  assert_output_equals "git fetch --prune bob"
  run hub --noop fetch https://github.com/bob/dotfiles.git main
  assert_output_equals "git fetch https://github.com/bob/dotfiles.git main"
  run hub --noop fetch git@github.com:bob/dotfiles.git
  assert_output_equals "git fetch git@github.com:bob/dotfiles.git"
  run hub --noop fetch ../other.git
  assert_output_equals "git fetch ../other.git"
  run hub --noop fetch alice
  assert_output_equals "git fetch alice"
  run hub --noop fetch
  assert_output_equals "git fetch"
  assert_gh_not_called
}

@test "a name that cannot be a GitHub login makes it plain git fetch" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch alice,not.a.login
  assert_success
  assert_output_equals "git fetch alice,not.a.login"
  run hub --noop fetch alice.bob
  assert_success
  assert_output_equals "git fetch alice.bob"
  assert_gh_not_called
}

@test "an existing remote with a dot in its name can be in the list" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git origin.backup=../backup.git
  run hub --noop fetch origin.backup,alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch --multiple origin.backup alice'
}

@test "outside a repository it is plain git fetch" {
  mkdir outside && cd outside
  export GIT_CEILING_DIRECTORIES=$HUB_TEST_TMP
  run hub --noop fetch alice
  assert_success
  assert_output_equals "git fetch alice"
  run hub --noop fetch --multiple alice bob
  assert_success
  assert_output_equals "git fetch --multiple alice bob"
  assert_gh_not_called
}

@test "fetch uses SSH when hub.protocol is ssh, without asking gh" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git config --global hub.protocol ssh
  run hub --noop fetch alice,bob
  assert_success
  assert_line_equals 0 "git remote add alice git@github.com:alice/dotfiles.git"
  assert_line_equals 1 "git remote add bob git@github.com:bob/dotfiles.git"
  assert_gh_not_called
}

@test "the protocol is looked up once for several users" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'config get git_protocol -h github.com' 'ssh'
  run hub --noop fetch alice,bob
  assert_success
  assert_line_equals 1 "git remote add bob git@github.com:bob/dotfiles.git"
  [[ $(grep -c 'config get git_protocol' "$HUB_TEST_LOG") -eq 1 ]]
}

@test "the fork is on the current project's host, under the project's name" {
  git config --global hub.host ghe.example.com
  make_repo work-copy origin=https://ghe.example.com/me/fork-name.git upstream=git@ghe.example.com:tools/tool.git
  run hub --noop fetch alice
  assert_success
  assert_output_equals $'git remote add alice https://ghe.example.com/alice/tool.git\ngit fetch alice'
  assert_gh_called 'config get git_protocol -h ghe.example.com'
}

@test "without a GitHub remote, the work tree's directory name is the repository name" {
  make_repo tool
  run hub --noop fetch alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/tool.git\ngit fetch alice'
}

@test "fetch --help prints the manual; -h is git's" {
  run hub fetch --help
  assert_success
  assert_line_equals 0 "Summary: Fetch from GitHub users' forks, adding remotes for them first."
  assert_output_contains "Usage: hub fetch USER[,USER2...]"
  run hub fetch alice,bob --help
  assert_success
  assert_output_contains "Usage: hub fetch USER[,USER2...]"
  run hub --noop fetch -h
  assert_output_equals "git fetch -h"
  assert_gh_not_called
}

@test "fetch really adds the remotes and fetches the forks" {
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub fetch alice,bob
  assert_success
  [[ $(git config remote.alice.url) == https://github.com/alice/dotfiles.git ]]
  [[ $(git config remote.bob.url) == https://github.com/bob/dotfiles.git ]]
  git rev-parse --verify -q refs/remotes/alice/main
  git rev-parse --verify -q refs/remotes/bob/main
}

@test "fetch --multiple really adds the remotes and fetches the forks" {
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub fetch --multiple alice bob --prune
  assert_success
  [[ $(git config remote.alice.url) == https://github.com/alice/dotfiles.git ]]
  [[ $(git config remote.bob.url) == https://github.com/bob/dotfiles.git ]]
  git rev-parse --verify -q refs/remotes/alice/main
  git rev-parse --verify -q refs/remotes/bob/main
}

@test "a fork that does not exist fails in git and its remote stays" {
  serve_github mislav/dotfiles
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub fetch nobody
  assert_failure
  [[ $(git config remote.nobody.url) == https://github.com/nobody/dotfiles.git ]]
}
