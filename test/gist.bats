#!/usr/bin/env bats
# hub gist: gh gist with show as view and list for no subcommand.

load test_helper

@test "hub gist without arguments runs gh gist list" {
  stub_gh 'gist list' '8f3c4e2  notes.md  1 file  secret'
  run hub gist
  assert_success
  assert_output_equals '8f3c4e2  notes.md  1 file  secret'
  assert_equals "$(gh_calls)" 'gh gist list'
}

@test "hub gist with an option first inserts list before it" {
  stub_gh 'gist list *' ''
  run hub gist -L 5 --public
  assert_success
  assert_equals "$(gh_calls)" 'gh gist list -L 5 --public'
}

@test "hub gist -- inserts list before the --" {
  stub_gh 'gist list *' ''
  run hub gist -- show
  assert_success
  assert_equals "$(gh_calls)" 'gh gist list -- show'
}

@test "hub gist show runs gh gist view with the rest in place" {
  stub_gh 'gist view *' '# Notes'
  run hub gist show 8f3c4e2 --raw -f notes.md
  assert_success
  assert_output_equals '# Notes'
  assert_equals "$(gh_calls)" 'gh gist view 8f3c4e2 --raw -f notes.md'
}

@test "hub gist show without an ID runs gh gist view" {
  stub_gh 'gist view' ''
  run hub gist show
  assert_success
  assert_equals "$(gh_calls)" 'gh gist view'
}

@test "hub gist -R goes to gh, which refuses it, with list after its value" {
  stub_gh 'gist -R *' "unknown shorthand flag: 'R' in -R" 1
  run hub gist -R mislav/dotfiles
  assert_status 1
  assert_output_equals "unknown shorthand flag: 'R' in -R"
  run hub gist -R show
  assert_status 1
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh gist -R mislav/dotfiles list' \
    'gh gist -R show list')"
}

@test "hub gist hands other subcommands and options to gh unchanged" {
  stub_gh 'gist *' ''
  hub gist create -p -d Notes a.txt b.md
  hub gist create -o a.txt
  hub gist view 8f3c4e2 notes.md
  hub gist delete 8f3c4e2 --yes
  hub gist frobnicate 8f3c4e2
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh gist create -p -d Notes a.txt b.md' \
    'gh gist create -o a.txt' 'gh gist view 8f3c4e2 notes.md' 'gh gist delete 8f3c4e2 --yes' \
    'gh gist frobnicate 8f3c4e2')"
}

@test "hub gist keeps every argument whole" {
  stub_gh 'gist create *' ''
  PATH=$(recording_gh):$PATH run hub gist create -d 'two words' -f '' 'my file.txt'
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' gist create -d 'two words' -f '' 'my file.txt')"
}

@test "hub gist gives gh its standard input" {
  stub_gh 'gist create' ''
  PATH=$(recording_gh stdin):$PATH run hub gist create <<<'hello gist'
  assert_success
  assert_equals "$(<stdin)" 'hello gist'
}

@test "hub gist adds no host and keeps the user's GH_HOST" {
  stub_gh 'gist view *' ''
  make_repo work origin=https://github.com/mislav/hub.git
  GH_HOST=ghe.example.com PATH=$(recording_gh):$PATH \
    run hub gist show https://gist.github.com/mislav/8f3c4e2
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=ghe.example.com GH_REPO=unset'
  assert_equals "$(<"$HUB_TEST_TMP/args")" "$(printf '%s\n' gist view \
    https://gist.github.com/mislav/8f3c4e2)"
}

@test "hub gist leaves GH_HOST unset when the user has not set it" {
  stub_gh 'gist list' ''
  make_repo work origin=https://ghe.example.com/mislav/hub.git
  PATH=$(recording_gh):$PATH run hub gist list
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=unset GH_REPO=unset'
  assert_equals "$(<"$HUB_TEST_TMP/args")" "$(printf '%s\n' gist list)"
}

@test "hub gist runs outside a repository" {
  stub_gh 'gist *' ''
  run hub gist show 8f3c4e2
  assert_success
  assert_equals "$(gh_calls)" 'gh gist view 8f3c4e2'
}

@test "hub gist exits with gh's status and relays its messages" {
  stub_gh 'gist view 0000' 'gist not found' 4
  run hub gist show 0000
  assert_status 4
  assert_output_equals 'gist not found'
  assert_equals "$(gh_calls)" 'gh gist view 0000'
}

@test "hub gist --help and -h before the subcommand print hub's manual" {
  run hub gist --help
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit gists (gh gist).'
  assert_line_equals 1 'Usage: hub gist [SUBCOMMAND] [GH-GIST-ARGS...]'
  run hub gist -h
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit gists (gh gist).'
  assert_gh_not_called
}

@test "hub gist -R or --repo with -h or --help as the value prints hub's manual" {
  run hub gist -R --help
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit gists (gh gist).'
  run hub gist --repo -h
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit gists (gh gist).'
  assert_gh_not_called
}

@test "hub gist --help after the subcommand is gh's" {
  stub_gh 'gist view *' 'View the given gist or select from recent gists.'
  run hub gist show --help
  assert_success
  assert_output_equals 'View the given gist or select from recent gists.'
  assert_equals "$(gh_calls)" 'gh gist view --help'
}

@test "hub gist --help after an option is gh's help for list" {
  stub_gh 'gist list *' 'List gists from your user account.'
  run hub gist -L 5 --help
  assert_success
  assert_output_equals 'List gists from your user account.'
  assert_equals "$(gh_calls)" 'gh gist list -L 5 --help'
}

@test "hub help gist prints the same manual" {
  run hub gist --help
  assert_success
  local manual=$output
  assert_output_contains 'gh gist view ID --raw -f FILE'
  run hub help gist
  assert_success
  assert_output_equals "$manual"
  assert_gh_not_called
}

@test "hub --noop gist prints the gh command" {
  run hub --noop gist show 8f3c4e2
  assert_success
  assert_output_equals 'gh gist view 8f3c4e2'
  assert_gh_not_called
}

@test "hub gist without gh says gh is needed" {
  PATH=$(no_gh_path) run hub gist
  assert_status 1
  assert_output_equals 'hub gist: this command needs the GitHub CLI, gh (https://cli.github.com)'
}
