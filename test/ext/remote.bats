#!/usr/bin/env bats
load ../test_helper

@test "remote add USER adds USER's copy of the current repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/dotfiles.git"
  assert_gh_called 'config get git_protocol -h github.com'
}

@test "remote add OWNER/REPO names the remote after the owner" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote add alice/dots
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/dots.git"
}

@test "remote add NAME OWNER/REPO and NAME USER" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote add upstream github/hub
  assert_success
  assert_output_equals "git remote add upstream https://github.com/github/hub.git"
  run hub --noop remote add work alice
  assert_success
  assert_output_equals "git remote add work https://github.com/alice/dotfiles.git"
}

@test "remote add origin, alone, adds your own copy of the current repository" {
  make_repo dotfiles upstream=https://github.com/mislav/dotfiles.git
  stub_gh 'config get user -h github.com' 'alice'
  run hub --noop remote add origin
  assert_success
  assert_output_equals "git remote add origin https://github.com/alice/dotfiles.git"
  assert_gh_called 'config get user -h github.com'
  run hub --noop remote add -p -f -t main origin
  assert_success
  assert_output_equals "git remote add -f -t main origin git@github.com:alice/dotfiles.git"
}

@test "remote add origin in a new repository uses the directory name, and adds the remote" {
  make_repo "my project"
  stub_gh 'config get user -h github.com' 'alice'
  run hub --noop remote add origin
  assert_success
  assert_output_equals "git remote add origin https://github.com/alice/my-project.git"
  run hub remote add origin
  assert_success
  [[ $(git config remote.origin.url) == https://github.com/alice/my-project.git ]]
}

@test "remote add origin OWNER[/REPO] keeps its explicit meaning" {
  make_repo dotfiles upstream=https://github.com/mislav/dotfiles.git
  stub_gh 'config get user -h github.com' 'alice'
  run hub --noop remote add origin bob
  assert_success
  assert_output_equals "git remote add origin https://github.com/bob/dotfiles.git"
  run hub --noop remote add origin someone/repo
  assert_success
  assert_output_equals "git remote add origin https://github.com/someone/repo.git"
  run hub --noop remote add origin/dots
  assert_success
  assert_output_equals "git remote add origin https://github.com/origin/dots.git"
  [[ $(gh_calls) != *"config get user"* ]]
}

@test "remote add origin uses your login on the project's host" {
  git config --global hub.host ghe.example.com
  make_repo tool upstream=git@ghe.example.com:tools/tool.git
  stub_gh 'config get user -h ghe.example.com' 'alice-ghe'
  run hub --noop remote add origin
  assert_success
  assert_output_equals "git remote add origin https://ghe.example.com/alice-ghe/tool.git"
}

@test "remote add origin aborts when gh does not know your login" {
  make_repo dotfiles upstream=https://github.com/mislav/dotfiles.git
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user -q .login' '' 1
  run hub --noop remote add origin
  assert_failure
  assert_output_equals "Aborted: could not determine your GitHub login for github.com; run 'gh auth login'"
}

@test "a .git suffix is not doubled" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote add alice/dots.git
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/dots.git"
}

@test "the repository name comes from the main GitHub remote" {
  make_repo work-copy origin=git@github.com:me/fork-name.git upstream=https://github.com/org/real-name.git
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/real-name.git"
}

@test "GH_REPO names the current project" {
  make_repo work-copy origin=https://github.com/mislav/dotfiles.git
  export GH_REPO=cli/cli
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/cli.git"
}

@test "without a GitHub remote, the work tree's directory name is the repository name" {
  make_repo "my project" mirror=https://gitlab.com/me/elsewhere.git
  mkdir sub && cd sub
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/my-project.git"
}

@test "remote add -p uses SSH and is not passed to git" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote add -p alice
  assert_success
  assert_output_equals "git remote add alice git@github.com:alice/dotfiles.git"
  run hub --noop remote add work alice/dots -p
  assert_success
  assert_output_equals "git remote add work git@github.com:alice/dots.git"
}

@test "remote add uses SSH when hub.protocol is ssh, without asking gh" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git config --global hub.protocol ssh
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice git@github.com:alice/dotfiles.git"
  assert_gh_not_called
}

@test "remote add follows gh's git_protocol" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'config get git_protocol -h github.com' 'ssh'
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice git@github.com:alice/dotfiles.git"
}

@test "git remote add options are kept and go before the name" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote add -f -t main -m main --mirror=fetch --no-tags alice
  assert_success
  assert_output_equals "git remote add -f -t main -m main --mirror=fetch --no-tags alice https://github.com/alice/dotfiles.git"
  run hub --noop remote add alice -f
  assert_success
  assert_output_equals "git remote add -f alice https://github.com/alice/dotfiles.git"
}

@test "values of -t, -m, --track and --master are never taken for the name" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  local opt
  for opt in -t -m --track --master -ft; do
    run hub --noop remote add "$opt" feature alice
    assert_success
    assert_output_equals "git remote add $opt feature alice https://github.com/alice/dotfiles.git"
  done
  run hub --noop remote add -tfeature --track=other alice
  assert_success
  assert_output_equals "git remote add -tfeature --track=other alice https://github.com/alice/dotfiles.git"
}

@test "-- before the operands is kept" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote add -f -- alice
  assert_success
  assert_output_equals "git remote add -f -- alice https://github.com/alice/dotfiles.git"
}

@test "on GitHub Enterprise the URL is on the project's host, with that host's protocol" {
  git config --global hub.host ghe.example.com
  make_repo tool origin=git@ghe.example.com:tools/tool.git
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice https://ghe.example.com/alice/tool.git"
  assert_gh_called 'config get git_protocol -h ghe.example.com'
  stub_gh 'config get git_protocol -h ghe.example.com' 'ssh'
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice git@ghe.example.com:alice/tool.git"
}

@test "GH_HOST is the host when there is no GitHub remote" {
  make_repo tool
  export GH_HOST=ghe.example.com
  run hub --noop remote add alice
  assert_success
  assert_output_equals "git remote add alice https://ghe.example.com/alice/tool.git"
}

@test "remote set-url NAME USER[/REPO]" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote set-url origin alice
  assert_success
  assert_output_equals "git remote set-url origin https://github.com/alice/dotfiles.git"
  run hub --noop remote set-url origin alice/dots -p
  assert_success
  assert_output_equals "git remote set-url origin git@github.com:alice/dots.git"
}

@test "remote set-url keeps --push, --add and OLDURL" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote set-url origin alice --push
  assert_success
  assert_output_equals "git remote set-url --push origin https://github.com/alice/dotfiles.git"
  run hub --noop remote set-url --add --push origin alice/dots
  assert_success
  assert_output_equals "git remote set-url --add --push origin https://github.com/alice/dots.git"
  run hub --noop remote set-url origin alice 'https://github.com/mislav/.*'
  assert_success
  assert_output_equals "git remote set-url origin https://github.com/alice/dotfiles.git https://github.com/mislav/.\\*"
}

@test "remote set-url --delete passes through" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote set-url --delete origin alice
  assert_success
  assert_output_equals "git remote set-url --delete origin alice"
  assert_gh_not_called
}

@test "URLs and paths pass through untouched" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  mkdir backup
  local url
  for url in https://github.com/alice/dotfiles.git git@github.com:alice/dotfiles.git \
    ssh://git@example.com/alice/dotfiles host:alice/dotfiles ../other.git /srv/repo.git backup; do
    run hub --noop remote add other "$url"
    assert_success
    assert_output_equals "git remote add other $url"
    run hub --noop remote set-url origin "$url"
    assert_success
    assert_output_equals "git remote set-url origin $url"
  done
  run hub --noop remote add https://github.com/alice/dotfiles.git
  assert_success
  assert_output_equals "git remote add https://github.com/alice/dotfiles.git"
  assert_gh_not_called
}

@test "other remote subcommands and argument shapes pass through" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop remote
  assert_output_equals "git remote"
  run hub --noop remote -v
  assert_output_equals "git remote -v"
  run hub --noop remote rename origin alice
  assert_output_equals "git remote rename origin alice"
  run hub --noop remote remove alice
  assert_output_equals "git remote remove alice"
  run hub --noop remote get-url origin
  assert_output_equals "git remote get-url origin"
  run hub --noop remote add
  assert_output_equals "git remote add"
  run hub --noop remote add one two three
  assert_output_equals "git remote add one two three"
  run hub --noop remote set-url origin
  assert_output_equals "git remote set-url origin"
  assert_gh_not_called
}

@test "remote --help prints the manual; -h is git's" {
  run hub remote --help
  assert_success
  assert_line_equals 0 "Summary: Add or change a remote using a GitHub OWNER[/REPO] name."
  assert_output_contains "Usage: hub remote add [-p]"
  run hub remote add alice --help
  assert_success
  assert_output_contains "Usage: hub remote add [-p]"
  run hub remote set-url --help
  assert_success
  assert_output_contains "Usage: hub remote add [-p]"
  run hub --noop remote rename --help
  assert_output_equals "git remote rename --help"
  run hub --noop remote add -h
  assert_output_equals "git remote add -h"
  assert_gh_not_called
}

@test "remote add and set-url change the repository's config" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add alice
  assert_success
  [[ $(git config remote.alice.url) == https://github.com/alice/dotfiles.git ]]
  run hub remote set-url -p alice alice/dots
  assert_success
  [[ $(git config remote.alice.url) == git@github.com:alice/dots.git ]]
  run hub remote add alice
  assert_failure
  assert_output_contains "remote alice already exists"
}
