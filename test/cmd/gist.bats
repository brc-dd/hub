#!/usr/bin/env bats
load ../test_helper

# shim_gh : a gh on PATH that prints its arguments, GH_HOST and its standard input (give it one).
shim_gh() {
  mkdir -p "$HUB_TEST_TMP/shim"
  cat >"$HUB_TEST_TMP/shim/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s | GH_HOST=%s | stdin=%s\n' "$*" "${GH_HOST-}" "$(cat)"
SH
  chmod +x "$HUB_TEST_TMP/shim/gh"
  SHIM_PATH=$HUB_TEST_TMP/shim:$PATH
}

@test "gist with no subcommand word is gh gist list, options in place" {
  run hub --noop gist
  assert_success
  assert_output_equals "gh gist list"
  run hub --noop gist -L 5 --public
  assert_success
  assert_output_equals "gh gist list -L 5 --public"
  run hub --noop gist --filter=notes -L5
  assert_success
  assert_output_equals "gh gist list --filter=notes -L5"
  assert_gh_not_called
}

@test "gist show is gh gist view, with every other argument in its place" {
  run hub --noop gist show 8f3c4e2
  assert_success
  assert_output_equals "gh gist view 8f3c4e2"
  run hub --noop gist show 8f3c4e2 --raw -f notes.md
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 --raw -f notes.md"
  run hub --noop gist show https://gist.github.com/mislav/8f3c4e2 --web
  assert_success
  assert_output_equals "gh gist view https://gist.github.com/mislav/8f3c4e2 --web"
}

@test "gist passes gh's subcommands and options through unchanged, in order" {
  local args
  for args in "list --public -L 5" "view 8f3c4e2 --files" "edit 8f3c4e2 -a new.txt" "delete 8f3c4e2 --yes" \
    "clone 8f3c4e2 notes" "rename 8f3c4e2 old.md new.md" "create a.txt b.md -d Notes" "create - a.txt" \
    "create -p -w --filename notes.md"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop gist $args
    assert_success
    assert_output_equals "gh gist $args"
  done
  assert_gh_not_called
}

@test "gist does not translate old hub's options: they reach gh as typed" {
  run hub --noop gist show 8f3c4e2 notes.md
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 notes.md"
  run hub --noop gist create --public -o a.txt
  assert_success
  assert_output_equals "gh gist create --public -o a.txt"
  run hub --noop gist create a.txt --browse
  assert_success
  assert_output_equals "gh gist create a.txt --browse"
  stub_gh 'gist view 8f3c4e2 notes.md' 'accepts at most 1 arg(s), received 2' 1
  run hub gist show 8f3c4e2 notes.md
  assert_failure
  assert_output_equals 'accepts at most 1 arg(s), received 2'
  assert_equals "$(gh_calls)" 'gh gist view 8f3c4e2 notes.md'
}

@test "gist: clustered short options and their values are gh's to read" {
  run hub --noop gist create -pd -o file.txt
  assert_success
  assert_output_equals "gh gist create -pd -o file.txt"
  run hub --noop gist create -p -d -o file.txt
  assert_success
  assert_output_equals "gh gist create -p -d -o file.txt"
  run hub --noop gist create -p -w -d "-o is not --browse" --filename -o a.txt
  assert_success
  assert_output_equals "gh gist create -p -w -d -o\\ is\\ not\\ --browse --filename -o a.txt"
}

@test "gist: nothing after -- is read, not even a subcommand word" {
  run hub --noop gist show 8f3c4e2 asset.txt -- --filename=--web
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 asset.txt -- --filename=--web"
  run hub --noop gist show 8f3c4e2 -- --web
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 -- --web"
  run hub --noop gist -- show 8f3c4e2
  assert_success
  assert_output_equals "gh gist list -- show 8f3c4e2"
  assert_gh_not_called
}

@test "gist adds no host of its own: a gist URL and GH_HOST reach gh as they are" {
  local url=https://gist.github.com/local-owner/abcdef1234567890abcdef1234567890
  run hub --noop gist view "$url" --raw
  assert_success
  assert_output_equals "gh gist view $url --raw"
  run hub --noop gist delete "$url" --yes
  assert_success
  assert_output_equals "gh gist delete $url --yes"
  shim_gh
  GH_HOST=github.localhost PATH=$SHIM_PATH run hub gist show "$url" --raw </dev/null
  assert_success
  assert_output_equals "gh gist view $url --raw | GH_HOST=github.localhost | stdin="
}

@test "gist finds the subcommand word where gh does: an option's value is never one" {
  run hub --noop gist -f show
  assert_success
  assert_output_equals "gh gist list -f show"
  run hub --noop gist --desc show list
  assert_success
  assert_output_equals "gh gist --desc show list"
  run hub --noop gist '' show 8f3c4e2
  assert_success
  assert_output_equals "gh gist '' view 8f3c4e2"
  run hub --noop gist -L
  assert_success
  assert_output_equals "gh gist list -L"
}

@test "gist create reads standard input through gh, not hub" {
  shim_gh
  PATH=$SHIM_PATH run hub gist create -p <<<"hello"
  assert_success
  assert_output_equals "gh gist create -p | GH_HOST= | stdin=hello"
}

@test "gist -h and --help before the subcommand word print hub's manual; after it, gh's" {
  run hub gist --help
  assert_success
  assert_output_contains "Usage: hub gist [SUBCOMMAND] [gh gist options]"
  run hub gist -h
  assert_success
  assert_output_contains "Usage: hub gist"
  run hub help gist
  assert_success
  assert_output_contains "Usage: hub gist"
  run hub --noop gist view 8f3c4e2 --help
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 --help"
  run hub --noop gist create -h
  assert_success
  assert_output_equals "gh gist create -h"
  assert_gh_not_called
}

@test "gist hands over to gh and returns its output and status" {
  stub_gh 'gist view 8f3c4e2 --raw' 'hello'
  run hub gist show 8f3c4e2 --raw
  assert_success
  assert_output_equals "hello"
  stub_gh 'gist list' 'no gists found' 1
  run hub gist
  assert_failure
  assert_output_equals "no gists found"
  assert_equals "$(gh_calls)" $'gh gist view 8f3c4e2 --raw\ngh gist list'
}

@test "gist without gh gives hub's message" {
  mkdir nogh
  ln -s "$(command -v bash)" nogh/bash
  ln -s "$(command -v git)" nogh/git
  PATH=$PWD/nogh run hub gist show 8f3c4e2
  assert_failure
  assert_output_equals "hub: this command needs the GitHub CLI (gh): https://cli.github.com"
}
