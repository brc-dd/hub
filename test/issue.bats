#!/usr/bin/env bats
# hub issue: gh issue with show as view and list for no subcommand.

load test_helper

@test "hub issue without arguments runs gh issue list" {
  make_repo work origin=https://github.com/mislav/hub.git
  stub_gh 'issue list' '#7  Crash on start  bug'
  run hub issue
  assert_success
  assert_output_equals '#7  Crash on start  bug'
  assert_equals "$(gh_calls)" 'gh issue list'
}

@test "hub issue with an option first inserts list before it" {
  stub_gh 'issue list *' ''
  run hub issue -s closed -L 5
  assert_success
  assert_equals "$(gh_calls)" 'gh issue list -s closed -L 5'
}

@test "hub issue reads a word after an option as that option's, not as the subcommand" {
  stub_gh 'issue *' ''
  hub issue -s show
  hub issue --label show list
  hub issue -sclosed show 12
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh issue list -s show' \
    'gh issue list --label show list' 'gh issue list -sclosed show 12')"
}

@test "hub issue -- inserts list before the --" {
  stub_gh 'issue *' ''
  run hub issue -- show 12
  assert_success
  run hub issue -R cli/cli -- show
  assert_success
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh issue list -- show 12' \
    'gh issue -R cli/cli list -- show')"
}

@test "hub issue show runs gh issue view with the rest in place" {
  stub_gh 'issue view *' 'Crash on start #7'
  run hub issue show 7 --comments
  assert_success
  assert_output_equals 'Crash on start #7'
  assert_equals "$(gh_calls)" 'gh issue view 7 --comments'
}

@test "hub issue keeps -R and --repo in front of the subcommand" {
  stub_gh 'issue *' ''
  hub issue -R cli/cli show 12
  hub issue -Rcli/cli show 13
  hub issue --repo cli/cli show 14
  hub issue --repo=cli/cli -s open
  hub issue -R cli/cli
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh issue -R cli/cli view 12' \
    'gh issue -Rcli/cli view 13' 'gh issue --repo cli/cli view 14' \
    'gh issue --repo=cli/cli list -s open' 'gh issue -R cli/cli list')"
}

@test "hub issue -R or --repo without a value leaves the arguments to gh" {
  stub_gh 'issue -R' 'flag needs an argument: -R' 1
  stub_gh 'issue --repo' 'flag needs an argument: --repo' 1
  run hub issue -R
  assert_status 1
  assert_output_equals 'flag needs an argument: -R'
  run hub issue --repo
  assert_status 1
  assert_output_equals 'flag needs an argument: --repo'
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh issue -R' 'gh issue --repo')"
}

@test "hub issue hands other subcommands and hub 2.x spellings to gh unchanged" {
  stub_gh 'issue *' ''
  hub issue create -t Crash -b 'It crashes.'
  hub issue close 12 --duplicate-of 7
  hub issue update 12 -s closed
  hub issue labels
  hub issue create -m 'Crash' -o
  assert_equals "$(gh_calls)" "$(printf '%s\n' "gh issue create -t Crash -b It crashes." \
    'gh issue close 12 --duplicate-of 7' 'gh issue update 12 -s closed' 'gh issue labels' \
    'gh issue create -m Crash -o')"
}

@test "hub issue keeps every argument whole and an empty word as the subcommand" {
  stub_gh 'issue*' ''
  bin=$(recording_gh)
  PATH=$bin:$PATH run hub issue create --title 'two words' --body '' -l 'a,b c'
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' issue create --title 'two words' --body '' \
    -l 'a,b c')"
  PATH=$bin:$PATH run hub issue '' show 12
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' issue '' show 12)"
}

@test "hub issue gives gh its standard input" {
  stub_gh 'issue create *' ''
  PATH=$(recording_gh stdin):$PATH run hub issue create -t Crash -F - <<<'It crashes on start.'
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' issue create -t Crash -F -)"
  assert_equals "$(<stdin)" 'It crashes on start.'
}

@test "hub issue adds no repository or host and keeps the user's GH_REPO and GH_HOST" {
  make_repo work origin=https://github.com/mislav/hub.git
  stub_gh 'issue*' ''
  bin=$(recording_gh)
  PATH=$bin:$PATH run hub issue show 12
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/args")" "$(printf '%s\n' issue view 12)"
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=unset GH_REPO=unset'
  GH_REPO=cli/cli GH_HOST=ghe.example.com PATH=$bin:$PATH run hub issue
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=ghe.example.com GH_REPO=cli/cli'
}

@test "hub issue passes hub 2.x's GITHUB_HOST to gh as GH_HOST unless GH_HOST is set" {
  stub_gh 'issue*' ''
  bin=$(recording_gh)
  GITHUB_HOST=ghe.example.com PATH=$bin:$PATH run hub issue
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=ghe.example.com GH_REPO=unset'
  GITHUB_HOST=ghe.example.com GH_HOST=github.com PATH=$bin:$PATH run hub issue
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=github.com GH_REPO=unset'
}

# gh's parent is git (hub's re-entry through git's alias) only when hub's process became gh.
@test "hub issue hands its process over to gh" {
  stub_gh 'issue*' ''
  bin=$(recording_gh)
  PATH=$bin:$PATH run hub issue
  assert_success
  assert_equals "$(basename "$(<"$HUB_TEST_TMP/parent")")" git
}

@test "hub issue runs outside a repository" {
  stub_gh 'issue *' ''
  run hub issue -R cli/cli show 3
  assert_success
  assert_equals "$(gh_calls)" 'gh issue -R cli/cli view 3'
}

@test "hub issue exits with gh's status and relays its messages" {
  stub_gh 'issue view 99' 'GraphQL: Could not resolve to an issue with the number of 99.' 1
  run hub issue show 99
  assert_status 1
  assert_output_equals 'GraphQL: Could not resolve to an issue with the number of 99.'
  assert_equals "$(gh_calls)" 'gh issue view 99'
}

@test "hub --noop issue prints the gh command instead of running it" {
  run hub --noop issue show 12
  assert_success
  assert_output_equals 'gh issue view 12'
  run hub --noop issue create -t 'two words' -b ''
  assert_success
  assert_output_equals "gh issue create -t two\\ words -b ''"
  assert_gh_not_called
}

@test "hub issue --help and -h before the subcommand print hub's manual" {
  run hub issue --help
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit issues (gh issue).'
  assert_line_equals 1 'Usage: hub issue [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-ISSUE-ARGS...]'
  run hub issue -h
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit issues (gh issue).'
  run hub issue -R cli/cli --help
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit issues (gh issue).'
  run hub issue -R cli/cli -h
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit issues (gh issue).'
  assert_gh_not_called
}

@test "hub issue -R or --repo with -h or --help as the value prints hub's manual" {
  run hub issue -R --help
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit issues (gh issue).'
  run hub issue --repo -h
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit issues (gh issue).'
  assert_gh_not_called
}

@test "hub issue -R --help before a subcommand goes to gh, which refuses the value" {
  stub_gh 'issue *' ''
  run hub issue -R --help list
  assert_success
  assert_equals "$(gh_calls)" 'gh issue -R --help list'
}

@test "hub issue --help and -h after the subcommand are gh's" {
  stub_gh 'issue view *' 'Display the title, body, and other information about an issue.'
  stub_gh 'issue list -h' 'List issues in a GitHub repository.'
  run hub issue show --help
  assert_success
  assert_output_equals 'Display the title, body, and other information about an issue.'
  run hub issue list -h
  assert_success
  assert_output_equals 'List issues in a GitHub repository.'
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh issue view --help' 'gh issue list -h')"
}

@test "hub help issue prints the same manual, naming gh's spellings" {
  run hub help issue
  assert_success
  assert_line_equals 0 'Summary: List, view, create and edit issues (gh issue).'
  assert_output_contains 'gh issue edit N'
  assert_output_contains 'gh label list'
}

@test "hub issue without gh says gh is needed" {
  PATH=$(no_gh_path) run hub issue
  assert_status 1
  assert_output_equals 'hub issue: this command needs the GitHub CLI, gh (https://cli.github.com)'
}
