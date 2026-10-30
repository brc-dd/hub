#!/usr/bin/env bats
load ../test_helper

# serve_github OWNER/REPO... : make https://github.com/OWNER/REPO.git resolve to a local bare repo
@test "clone OWNER/REPO expands to an HTTPS URL by default" {
  run hub --noop clone rtomayko/ronn
  assert_success
  assert_output_equals "git clone https://github.com/rtomayko/ronn.git"
  assert_gh_called 'config get git_protocol -h github.com'
  [[ $(gh_calls) != *"config get user"* ]]
}

@test "clone REPO is one of your own repositories" {
  run hub --noop clone dotfiles
  assert_success
  assert_output_equals "git clone https://github.com/mislav/dotfiles.git"
  assert_gh_called 'config get user -h github.com'
}

@test "clone keeps the directory and every other argument in place" {
  run hub --noop clone --depth 1 mislav/dotfiles --single-branch dots
  assert_success
  assert_output_equals "git clone --depth 1 https://github.com/mislav/dotfiles.git --single-branch dots"
}

@test "clone -p uses SSH and is not passed to git" {
  run hub --noop clone -p mislav/dotfiles
  assert_success
  assert_output_equals "git clone git@github.com:mislav/dotfiles.git"
  run hub --noop clone mislav/dotfiles -p dots
  assert_success
  assert_output_equals "git clone git@github.com:mislav/dotfiles.git dots"
}

@test "clone -p with a URL drops -p and keeps the URL" {
  run hub --noop clone -p https://github.com/mislav/dotfiles.git
  assert_success
  assert_output_equals "git clone https://github.com/mislav/dotfiles.git"
}

@test "clone uses SSH when hub.protocol is ssh, without asking gh" {
  git config --global hub.protocol ssh
  run hub --noop clone mislav/dotfiles
  assert_success
  assert_output_equals "git clone git@github.com:mislav/dotfiles.git"
  assert_gh_not_called
}

@test "clone honors hub -c hub.protocol=ssh" {
  run hub -c hub.protocol=ssh --noop clone mislav/dotfiles
  assert_success
  assert_output_equals "git -c hub.protocol=ssh clone git@github.com:mislav/dotfiles.git"
}

@test "clone follows gh's git_protocol when hub.protocol is unset" {
  stub_gh 'config get git_protocol -h github.com' 'ssh'
  run hub --noop clone mislav/dotfiles
  assert_success
  assert_output_equals "git clone git@github.com:mislav/dotfiles.git"
}

@test "values of git clone options are never taken for the repository" {
  local opt
  for opt in -b --branch -c --config -j --jobs -o --origin -u --upload-pack --depth --filter \
    --reference --reference-if-able --revision --separate-git-dir --server-option \
    --shallow-exclude --shallow-since --template --bundle-uri --ref-format; do
    run hub --noop clone "$opt" value mislav/dotfiles
    assert_success
    assert_output_equals "git clone $opt value https://github.com/mislav/dotfiles.git"
  done
}

@test "stuck option values and short option clusters" {
  run hub --noop clone --depth=1 --origin=up mislav/dotfiles
  assert_success
  assert_output_equals "git clone --depth=1 --origin=up https://github.com/mislav/dotfiles.git"
  run hub --noop clone -bmain mislav/dotfiles
  assert_success
  assert_output_equals "git clone -bmain https://github.com/mislav/dotfiles.git"
  run hub --noop clone -qb main mislav/dotfiles
  assert_success
  assert_output_equals "git clone -qb main https://github.com/mislav/dotfiles.git"
  run hub --noop clone -qn mislav/dotfiles dots
  assert_success
  assert_output_equals "git clone -qn https://github.com/mislav/dotfiles.git dots"
}

@test "boolean options before the repository take no value" {
  run hub --noop clone --bare --recurse-submodules --mirror -n -q mislav/dotfiles
  assert_success
  assert_output_equals "git clone --bare --recurse-submodules --mirror -n -q https://github.com/mislav/dotfiles.git"
}

@test "-- ends the options" {
  run hub --noop clone --depth 1 -- mislav/dotfiles dots
  assert_success
  assert_output_equals "git clone --depth 1 -- https://github.com/mislav/dotfiles.git dots"
  run hub --noop clone -- --help
  assert_success
  assert_output_equals "git clone -- --help"
}

@test "clone a wiki" {
  run hub --noop clone mislav/dotfiles.wiki
  assert_success
  assert_output_equals "git clone https://github.com/mislav/dotfiles.wiki.git"
  run hub --noop clone dotfiles.wiki
  assert_success
  assert_output_equals "git clone https://github.com/mislav/dotfiles.wiki.git"
}

@test "a bare repository name may contain dots" {
  run hub --noop clone mislav.github.io
  assert_success
  assert_output_equals "git clone https://github.com/mislav/mislav.github.io.git"
}

@test "a .git suffix is not doubled" {
  run hub --noop clone mislav/dotfiles.git
  assert_success
  assert_output_equals "git clone https://github.com/mislav/dotfiles.git"
}

@test "GH_HOST selects the host, its login and its protocol" {
  export GH_HOST=ghe.example.com
  stub_gh 'config get user -h ghe.example.com' 'hubot'
  stub_gh 'config get git_protocol -h ghe.example.com' 'https'
  run hub --noop clone tools/deploy
  assert_success
  assert_output_equals "git clone https://ghe.example.com/tools/deploy.git"
  run hub --noop clone deploy
  assert_success
  assert_output_equals "git clone https://ghe.example.com/hubot/deploy.git"
  stub_gh 'config get git_protocol -h ghe.example.com' 'ssh'
  run hub --noop clone tools/deploy
  assert_success
  assert_output_equals "git clone git@ghe.example.com:tools/deploy.git"
}

@test "clone HOST/OWNER/REPO uses that host and its protocol" {
  run hub --noop clone ghe.example.com/tools/deploy
  assert_success
  assert_output_equals "git clone https://ghe.example.com/tools/deploy.git"
  assert_gh_called 'config get git_protocol -h ghe.example.com'
  stub_gh 'config get git_protocol -h ghe.example.com' 'ssh'
  run hub --noop clone ghe.example.com/tools/deploy
  assert_success
  assert_output_equals "git clone git@ghe.example.com:tools/deploy.git"
  run hub --noop clone github.com/mislav/dotfiles dots
  assert_success
  assert_output_equals "git clone https://github.com/mislav/dotfiles.git dots"
}

@test "a host without a dot is only recognized when configured" {
  run hub --noop clone ghe/tools/deploy
  assert_success
  assert_output_equals "git clone ghe/tools/deploy"
  git config --global hub.host ghe
  run hub --noop clone ghe/tools/deploy
  assert_success
  assert_output_equals "git clone https://ghe/tools/deploy.git"
}

@test "URLs pass through untouched" {
  local url
  for url in https://github.com/mislav/dotfiles.git git@github.com:mislav/dotfiles.git \
    ssh://git@github.com/mislav/dotfiles github.com:mislav/dotfiles file:///srv/dotfiles.git \
    https://github.com/mislav/dotfiles/tree/main; do
    run hub --noop clone "$url"
    assert_success
    assert_output_equals "git clone $url"
  done
  assert_gh_not_called
}

@test "local paths pass through untouched" {
  mkdir -p dotfiles nested/dir
  local path
  for path in dotfiles ./dotfiles ../dotfiles /srv/dotfiles.git nested/dir; do
    run hub --noop clone "$path" copy
    assert_success
    assert_output_equals "git clone $path copy"
  done
  assert_gh_not_called
}

@test "clone without a repository argument is plain git clone" {
  run hub --noop clone
  assert_success
  assert_output_equals "git clone"
  run hub --noop clone --depth 1
  assert_success
  assert_output_equals "git clone --depth 1"
  assert_gh_not_called
}

@test "clone --help prints the manual; -h is git's" {
  run hub clone --help
  assert_success
  assert_line_equals 0 "Summary: Clone a GitHub repository by its [OWNER/]REPO name."
  assert_output_contains "Usage: hub clone [-p]"
  run hub --noop clone mislav/dotfiles --help
  assert_success
  assert_output_contains "Usage: hub clone [-p]"
  run hub --noop clone -h
  assert_success
  assert_output_equals "git clone -h"
  assert_gh_not_called
  run hub help clone
  assert_success
  assert_output_contains "Usage: hub clone [-p]"
}

@test "clone REPO aborts when your login is unknown" {
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user -q .login' '' 1
  run hub --noop clone dotfiles
  assert_failure
  assert_output_contains "could not determine your GitHub login"
  [[ $output != *"git clone"* ]]
}

@test "clone runs git clone for real" {
  serve_github alice/dotfiles
  run hub clone alice/dotfiles
  assert_success
  [[ $(git -C dotfiles config remote.origin.url) == https://github.com/alice/dotfiles.git ]]
  git -C dotfiles rev-parse --verify -q refs/remotes/origin/main
}

@test "clone exits with git's status" {
  serve_github alice/dotfiles
  run hub clone alice/nothing-here
  assert_failure
  [[ ! -e nothing-here ]]
}
