#!/usr/bin/env bats
# hub release: gh release with show as view and list for no subcommand.

load test_helper

summary='Summary: List, view, create, edit, upload and download releases (gh release).'

@test "hub release without arguments runs gh release list" {
  make_repo work origin=https://github.com/mislav/hub.git
  stub_gh 'release list' 'v2.14.2  Latest  v2.14.2  2021-03-05'
  run hub release
  assert_success
  assert_output_equals 'v2.14.2  Latest  v2.14.2  2021-03-05'
  assert_equals "$(gh_calls)" 'gh release list'
}

@test "hub release with an option first inserts list before it" {
  stub_gh 'release list *' ''
  run hub release -L 5 --exclude-drafts
  assert_success
  assert_equals "$(gh_calls)" 'gh release list -L 5 --exclude-drafts'
}

@test "hub release reads a word after an option as that option's, not as the subcommand" {
  stub_gh 'release list *' ''
  run hub release -O show
  assert_success
  assert_equals "$(gh_calls)" 'gh release list -O show'
}

@test "hub release -- inserts list before the --" {
  stub_gh 'release list *' ''
  run hub release -- v1.0.0
  assert_success
  assert_equals "$(gh_calls)" 'gh release list -- v1.0.0'
}

@test "hub release show runs gh release view with the rest in place" {
  stub_gh 'release view *' 'v2.0.0'
  run hub release show v2.0.0 --json assets
  assert_success
  assert_output_equals 'v2.0.0'
  assert_equals "$(gh_calls)" 'gh release view v2.0.0 --json assets'
}

@test "hub release keeps -R and --repo in front of the subcommand" {
  stub_gh 'release *' ''
  hub release -R cli/cli show v1
  hub release -Rcli/cli show v2
  hub release --repo cli/cli show v3
  hub release --repo=cli/cli -L 5
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh release -R cli/cli view v1' \
    'gh release -Rcli/cli view v2' 'gh release --repo cli/cli view v3' \
    'gh release --repo=cli/cli list -L 5')"
}

@test "hub release -R or --repo without a value leaves the arguments to gh" {
  stub_gh 'release -R' 'flag needs an argument: -R' 1
  run hub release -R
  assert_status 1
  assert_equals "$(gh_calls)" 'gh release -R'
  stub_gh 'release --repo' 'flag needs an argument: --repo' 1
  run hub release --repo
  assert_status 1
  assert_output_equals 'flag needs an argument: --repo'
  assert_gh_called 'release --repo'
}

@test "hub release with only an attached repository value inserts list after it" {
  stub_gh 'release *' ''
  hub release --repo=cli/cli
  hub release -Rcli/cli
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh release --repo=cli/cli list' \
    'gh release -Rcli/cli list')"
}

@test "hub release show alone runs gh release view" {
  stub_gh 'release view' 'v2.0.0'
  run hub release show
  assert_success
  assert_output_equals 'v2.0.0'
  assert_equals "$(gh_calls)" 'gh release view'
}

@test "hub release hands other subcommands and hub 2.x spellings to gh unchanged" {
  stub_gh 'release *' ''
  hub release create v1.0.0 dist/app.tgz --target main
  hub release create -a dist/app.tgz -m 'Version 1' v1.0.0
  hub release upload v1.0.0 dist/app.tgz --clobber
  hub release edit v1.0.0 --draft=false
  hub release download v1.0.0 -i '*.tgz'
  hub release delete v1.0.0 -y
  assert_equals "$(gh_calls)" "$(printf '%s\n' \
    'gh release create v1.0.0 dist/app.tgz --target main' \
    'gh release create -a dist/app.tgz -m Version 1 v1.0.0' \
    'gh release upload v1.0.0 dist/app.tgz --clobber' \
    'gh release edit v1.0.0 --draft=false' \
    'gh release download v1.0.0 -i *.tgz' \
    'gh release delete v1.0.0 -y')"
}

@test "hub release keeps every argument whole and gives gh the standard input" {
  mkdir bin
  # A gh that records one argument per line and its standard input.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >"%s/args"\ncat >"%s/stdin"\n' \
    "$HUB_TEST_TMP" "$HUB_TEST_TMP" >bin/gh
  chmod +x bin/gh
  PATH=$HUB_TEST_TMP/bin:$PATH run hub release create v1.0.0 'my app.tgz#Linux build' \
    --title 'Version 1' --notes-file - <<<'The notes'
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' release create v1.0.0 'my app.tgz#Linux build' \
    --title 'Version 1' --notes-file -)"
  assert_equals "$(<stdin)" 'The notes'
}

@test "hub release adds no repository or host and keeps the user's GH_REPO" {
  make_repo work origin=https://github.com/mislav/hub.git
  stub_gh 'release *' ''
  GH_REPO=cli/cli run hub release show v2.0.0
  assert_success
  assert_equals "$(gh_calls)" 'GH_REPO=cli/cli gh release view v2.0.0'
}

@test "hub release runs outside a repository" {
  stub_gh 'release *' ''
  run hub release -R cli/cli
  assert_success
  assert_equals "$(gh_calls)" 'gh release -R cli/cli list'
}

@test "hub release exits with gh's status and relays its messages" {
  mkdir bin
  # A gh that records its arguments, then fails on standard error with status 4.
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >"%s/args"\n%s\n' \
    "$HUB_TEST_TMP" "echo 'release not found' >&2; exit 4" >bin/gh
  chmod +x bin/gh
  PATH=$HUB_TEST_TMP/bin:$PATH run hub release show v9.9.9
  assert_status 4
  assert_output_equals 'release not found'
  assert_equals "$(<args)" "$(printf '%s\n' release view v9.9.9)"
}

@test "hub --noop release prints the gh command instead of running it" {
  run hub --noop release show 'v1 beta'
  assert_success
  assert_output_equals 'gh release view v1\ beta'
  assert_gh_not_called
}

@test "hub release --help and -h before the subcommand print hub's manual" {
  run hub release --help
  assert_success
  assert_line_equals 0 "$summary"
  assert_line_equals 1 'Usage: hub release [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-RELEASE-ARGS...]'
  run hub release -h
  assert_success
  assert_line_equals 0 "$summary"
  run hub release -R cli/cli --help
  assert_success
  assert_line_equals 0 "$summary"
  assert_gh_not_called
}

@test "hub release --help and -h after the subcommand are gh's" {
  stub_gh 'release create *' 'Create a new GitHub Release for a repository.'
  run hub release create --help
  assert_success
  assert_output_equals 'Create a new GitHub Release for a repository.'
  run hub release create -h
  assert_success
  assert_output_equals 'Create a new GitHub Release for a repository.'
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh release create --help' \
    'gh release create -h')"
}

@test "hub help release prints the same manual, naming gh's spelling of hub 2.x options" {
  run hub help release
  assert_success
  assert_line_equals 0 "$summary"
  assert_equals "$output" "$(hub release --help)"
  assert_output_contains 'release create|edit -a FILE'
  assert_output_contains 'gh release upload TAG FILE...'
  assert_output_contains 'gh release download TAG -p GLOB'
}

@test "hub release without gh says gh is needed" {
  # Only git and bash: a gh in /usr/bin or /bin (as on CI runners) must not be found.
  mkdir nogh
  ln -s "$(command -v git)" nogh/git
  ln -s "$(command -v bash)" nogh/bash
  PATH=$HUB_TEST_TMP/nogh run hub release
  assert_status 1
  assert_output_equals 'hub release: this command needs the GitHub CLI, gh (https://cli.github.com)'
}
