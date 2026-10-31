#!/usr/bin/env bats
load ../test_helper

@test "release with no subcommand word is gh release list, options in place" {
  run hub --noop release
  assert_success
  assert_output_equals "gh release list"
  run hub --noop release -L 5 --exclude-drafts
  assert_success
  assert_output_equals "gh release list -L 5 --exclude-drafts"
  run hub --noop release -R mislav/dotfiles
  assert_success
  assert_output_equals "gh release list -R mislav/dotfiles"
  assert_gh_not_called
}

@test "release show is gh release view, with every other argument in its place" {
  run hub --noop release show v1.0 --json tagName,assets
  assert_success
  assert_output_equals "gh release view v1.0 --json tagName,assets"
  run hub --noop release -R mislav/dotfiles show v1.0
  assert_success
  assert_output_equals "gh release -R mislav/dotfiles view v1.0"
  run hub --noop release --repo=mislav/dotfiles show
  assert_success
  assert_output_equals "gh release --repo=mislav/dotfiles view"
}

@test "release passes gh's subcommands and options through unchanged, in order" {
  local args
  for args in "delete v1.0 -y --cleanup-tag" "upload v1.0 a.tgz --clobber" "list -O asc --some-new-flag" \
    "create v1.0 a.tgz b.zip#Label --title T --notes N --target main --latest=false --verify-tag" \
    "edit v1.0 --draft=false --latest --tag v1.0.1" "download v1.0 -D dist -O - -A zip" \
    "view v1.0 --web" "delete-asset v1.0 a.tgz -y" "verify v1.0"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop release $args
    assert_success
    assert_output_equals "gh release $args"
  done
  run hub --noop release download v1.0 -p '*.tgz' -p '*.zip'
  assert_success
  assert_output_equals "gh release download v1.0 -p \\*.tgz -p \\*.zip"
  assert_gh_not_called
}

@test "release does not translate old hub's options: they reach gh as typed" {
  touch a.tgz
  run hub --noop release create v1.0 -a a.tgz -m v1.0 -t main
  assert_success
  assert_output_equals "gh release create v1.0 -a a.tgz -m v1.0 -t main"
  run hub --noop release edit v1.0 -a a.tgz --clobber
  assert_success
  assert_output_equals "gh release edit v1.0 -a a.tgz --clobber"
  run hub --noop release download v1.0 -i '*.tgz' --include=*.deb
  assert_success
  assert_output_equals "gh release download v1.0 -i \\*.tgz --include=\\*.deb"
  run hub --noop release -R mislav/dotfiles create v1.0 -a a.tgz
  assert_success
  assert_output_equals "gh release -R mislav/dotfiles create v1.0 -a a.tgz"
  stub_gh 'release create v1.0 -a a.tgz' "unknown shorthand flag: 'a' in -a" 1
  run hub release create v1.0 -a a.tgz
  assert_failure
  assert_output_equals "unknown shorthand flag: 'a' in -a"
  assert_equals "$(gh_calls)" 'gh release create v1.0 -a a.tgz'
}

@test "release: a file whose name looks like an option is an argument where the user put it" {
  touch -- --clobber app.tgz
  mkdir -- --repo=other
  touch -- --repo=other/project
  run hub --noop release edit v1 -a --clobber -a app.tgz
  assert_success
  assert_output_equals "gh release edit v1 -a --clobber -a app.tgz"
  run hub --noop release edit v1 -a --repo=other/project -a app.tgz
  assert_success
  assert_output_equals "gh release edit v1 -a --repo=other/project -a app.tgz"
  run hub --noop release upload v1 -- --clobber app.tgz
  assert_success
  assert_output_equals "gh release upload v1 -- --clobber app.tgz"
  run hub --noop release upload v1 ./--clobber ./--repo=other/project app.tgz
  assert_success
  assert_output_equals "gh release upload v1 ./--clobber ./--repo=other/project app.tgz"
  assert_gh_not_called
}

@test "release: clustered short options are gh's to read" {
  touch app.tgz
  run hub --noop release create v1 -dtdevelop --notes body
  assert_success
  assert_output_equals "gh release create v1 -dtdevelop --notes body"
  run hub --noop release create v1 -d -t develop --notes body
  assert_success
  assert_output_equals "gh release create v1 -d -t develop --notes body"
  run hub --noop release create v1 -da app.tgz -dmTitle
  assert_success
  assert_output_equals "gh release create v1 -da app.tgz -dmTitle"
  run hub --noop release edit v1 -dp
  assert_success
  assert_output_equals "gh release edit v1 -dp"
}

@test "release: asset names reach gh with their bytes and argument boundaries, for gh to check" {
  touch '[broken'
  run hub --noop release edit v1 --title Changed -a '[broken'
  assert_success
  assert_output_equals "gh release edit v1 --title Changed -a \\[broken"
  run hub --noop release upload v1 '[broken' 'dist/*.tgz'
  assert_success
  assert_output_equals "gh release upload v1 \\[broken dist/\\*.tgz"
  local name=$'line\nbreak.txt'
  printf data >"$name"
  run hub --noop release upload v1 "$name" "$name#label"
  assert_success
  assert_output_equals "gh release upload v1 \$'line\\nbreak.txt' \$'line\\nbreak.txt#label'"
  stub_gh 'release upload v1 *' ''
  run hub release upload v1 "$name"
  assert_success
  assert_equals "$(gh_calls)" $'gh release upload v1 line\nbreak.txt'
}

@test "release edit is one gh command: nothing is published or uploaded before gh has checked all of it" {
  touch asset.txt app.tgz
  run hub --noop release edit v1 --draft=false -a asset.txt --clobber=garbage
  assert_success
  assert_output_equals "gh release edit v1 --draft=false -a asset.txt --clobber=garbage"
  run hub --noop release edit v1 --draft=false -a app.tgz
  assert_success
  assert_output_equals "gh release edit v1 --draft=false -a app.tgz"
  stub_gh 'release edit v1 *' "unknown shorthand flag: 'a' in -a" 1
  run hub release edit v1 --draft=false -a app.tgz
  assert_failure
  assert_output_equals "unknown shorthand flag: 'a' in -a"
  assert_equals "$(gh_calls)" 'gh release edit v1 --draft=false -a app.tgz'
  # gh's way: upload to the draft, then publish it
  run hub --noop release upload v1 app.tgz --clobber
  assert_success
  assert_output_equals "gh release upload v1 app.tgz --clobber"
  run hub --noop release edit v1 --draft=false
  assert_success
  assert_output_equals "gh release edit v1 --draft=false"
}

@test "release download: option values are gh's, whatever they look like" {
  run hub --noop release download v1 --dir -i
  assert_success
  assert_output_equals "gh release download v1 --dir -i"
  run hub --noop release download v1 --dir --help
  assert_success
  assert_output_equals "gh release download v1 --dir --help"
  run hub --noop release download v1 '-i=*.tgz' -D=dist -O -
  assert_success
  assert_output_equals "gh release download v1 -i=\\*.tgz -D=dist -O -"
  assert_gh_not_called
}

@test "release: nothing after -- is read, not even a subcommand word" {
  touch app.tgz
  run hub --noop release edit -a app.tgz -- v1
  assert_success
  assert_output_equals "gh release edit -a app.tgz -- v1"
  run hub --noop release edit -- v1
  assert_success
  assert_output_equals "gh release edit -- v1"
  run hub --noop release -- show v1
  assert_success
  assert_output_equals "gh release list -- show v1"
  run hub --noop release -R mislav/dotfiles -- show v1
  assert_success
  assert_output_equals "gh release list -R mislav/dotfiles -- show v1"
  assert_gh_not_called
}

@test "release: whether an option is in effect is gh's to judge: =false and empty values reach gh as typed" {
  run hub --noop release create v1 -m Title --generate-notes=false
  assert_success
  assert_output_equals "gh release create v1 -m Title --generate-notes=false"
  run hub --noop release create v1 --title Title --notes-file=
  assert_success
  assert_output_equals "gh release create v1 --title Title --notes-file="
  run hub --noop release create v1 --title T --notes N --help=false
  assert_success
  assert_output_equals "gh release create v1 --title T --notes N --help=false"
  run hub --noop release edit v1 --title Title --help=false
  assert_success
  assert_output_equals "gh release edit v1 --title Title --help=false"
  assert_gh_not_called
}

@test "release finds the subcommand word where gh does: an option's value is never one" {
  run hub --noop release -L show
  assert_success
  assert_output_equals "gh release list -L show"
  run hub --noop release --order show list
  assert_success
  assert_output_equals "gh release --order show list"
  run hub --noop release -L5 show v1
  assert_success
  assert_output_equals "gh release -L5 view v1"
  run hub --noop release '' show v1
  assert_success
  assert_output_equals "gh release '' view v1"
}

@test "release -h and --help before the subcommand word print hub's manual; after it, gh's" {
  run hub release --help
  assert_success
  assert_output_contains "Usage: hub release [SUBCOMMAND] [gh release options]"
  run hub release -h
  assert_success
  assert_output_contains "Usage: hub release"
  run hub release -R mislav/dotfiles -h
  assert_success
  assert_output_contains "Usage: hub release"
  run hub help release
  assert_success
  assert_output_contains "Usage: hub release"
  run hub --noop release delete --help
  assert_success
  assert_output_equals "gh release delete --help"
  run hub --noop release create v1.0 -h
  assert_success
  assert_output_equals "gh release create v1.0 -h"
  assert_gh_not_called
}

@test "release hands over to gh and returns its output and status" {
  stub_gh 'release list' 'v1.0\tLatest'
  run hub release
  assert_success
  assert_output_equals $'v1.0\tLatest'
  stub_gh 'release view v9' 'release not found' 1
  run hub release show v9
  assert_failure
  assert_output_equals "release not found"
  assert_equals "$(gh_calls)" $'gh release list\ngh release view v9'
}

@test "release without gh gives hub's message" {
  mkdir nogh
  ln -s "$(command -v bash)" nogh/bash
  ln -s "$(command -v git)" nogh/git
  PATH=$PWD/nogh run hub release
  assert_failure
  assert_output_equals "hub: this command needs the GitHub CLI (gh): https://cli.github.com"
}
