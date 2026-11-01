#!/usr/bin/env bats
# hub pr: gh pr with show as view and list for no subcommand.

load test_helper

@test "hub pr without arguments runs gh pr list" {
  make_repo work origin=https://github.com/mislav/hub.git
  stub_gh 'pr list' '#12  Fix the docs  fix-docs'
  run hub pr
  assert_success
  assert_output_equals '#12  Fix the docs  fix-docs'
  assert_equals "$(gh_calls)" 'gh pr list'
}

@test "hub pr with an option first inserts list before it" {
  stub_gh 'pr list *' ''
  run hub pr -s closed -L 5
  assert_success
  assert_equals "$(gh_calls)" 'gh pr list -s closed -L 5'
}

@test "hub pr with an option first leaves a later show alone" {
  stub_gh 'pr list *' ''
  run hub pr -s show
  assert_success
  assert_equals "$(gh_calls)" 'gh pr list -s show'
}

@test "hub pr -- inserts list before the --" {
  stub_gh 'pr list *' ''
  run hub pr -- 12
  assert_success
  assert_equals "$(gh_calls)" 'gh pr list -- 12'
}

@test "hub pr show runs gh pr view with the rest in place" {
  stub_gh 'pr view *' 'Fix the docs #12'
  run hub pr show 12 --comments
  assert_success
  assert_output_equals 'Fix the docs #12'
  assert_equals "$(gh_calls)" 'gh pr view 12 --comments'
}

@test "hub pr keeps -R and --repo in front of the subcommand" {
  stub_gh 'pr *' ''
  hub pr -R cli/cli show 12
  hub pr -Rcli/cli show 13
  hub pr --repo cli/cli show 14
  hub pr --repo=cli/cli -s open
  hub pr --repo=cli/cli show
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh pr -R cli/cli view 12' \
    'gh pr -Rcli/cli view 13' 'gh pr --repo cli/cli view 14' \
    'gh pr --repo=cli/cli list -s open' 'gh pr --repo=cli/cli view')"
}

@test "hub pr -R or --repo without a value leaves the arguments to gh" {
  stub_gh 'pr *' '' 1
  PATH=$(failing_gh 'flag needs an argument: -R'):$PATH run --separate-stderr hub pr -R
  assert_status 1
  assert_equals "$stderr" 'flag needs an argument: -R'
  PATH=$(failing_gh 'flag needs an argument: --repo'):$PATH run --separate-stderr hub pr --repo
  assert_status 1
  assert_equals "$stderr" 'flag needs an argument: --repo'
  run hub pr -R cli/cli -R
  assert_status 1
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh pr -R' 'gh pr --repo' 'gh pr -R cli/cli -R')"
}

@test "hub pr hands other subcommands and options to gh unchanged" {
  stub_gh 'pr *' ''
  hub pr checkout 12 -b fix
  hub pr view 12 -c
  hub pr checkout 12 fix
  hub pr merge 12 --squash
  hub pr frobnicate 12
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh pr checkout 12 -b fix' 'gh pr view 12 -c' \
    'gh pr checkout 12 fix' 'gh pr merge 12 --squash' 'gh pr frobnicate 12')"
}

@test "hub pr keeps every argument whole" {
  stub_gh 'pr create *' ''
  PATH=$(recording_gh):$PATH run hub pr create --title 'two words' --body '' -l 'a,b c'
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' pr create --title 'two words' --body '' -l 'a,b c')"
}

@test "hub pr adds no repository or host and keeps the user's GH_REPO" {
  make_repo work origin=https://github.com/mislav/hub.git
  stub_gh 'pr *' ''
  GH_REPO=cli/cli run hub pr show 12
  assert_success
  assert_equals "$(gh_calls)" 'GH_REPO=cli/cli gh pr view 12'
}

@test "hub pr runs outside a repository" {
  stub_gh 'pr *' ''
  run hub pr -R cli/cli
  assert_success
  assert_equals "$(gh_calls)" 'gh pr -R cli/cli list'
}

@test "hub pr exits with gh's status and relays its messages" {
  stub_gh 'pr view' '' 4
  PATH=$(failing_gh 'no pull requests found for branch "main"'):$PATH \
    run --separate-stderr hub pr show
  assert_status 4
  assert_equals "$stderr" 'no pull requests found for branch "main"'
  assert_output_equals ''
  assert_equals "$(gh_calls)" 'gh pr view'
}

@test "hub --noop pr prints the gh command without running it" {
  run hub --noop pr -R cli/cli show 12
  assert_success
  assert_output_equals 'gh pr -R cli/cli view 12'
  run hub --noop pr
  assert_success
  assert_output_equals 'gh pr list'
  assert_gh_not_called
}

@test "hub pr --help and -h before the subcommand print hub's manual" {
  run hub pr --help
  assert_success
  assert_line_equals 0 'Summary: List, view and check out pull requests (gh pr).'
  assert_line_equals 1 'Usage: hub pr [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-PR-ARGS...]'
  assert_output_contains 'gh pr checkout PR -b BRANCH'
  local manual=$output
  local -a cases=('-h' '-R cli/cli --help' '-R cli/cli -h' '--repo=cli/cli -h' '-Rcli/cli --help')
  local words
  for words in "${cases[@]}"; do
    read -ra argv <<<"$words"
    run hub pr "${argv[@]}"
    assert_success
    assert_output_equals "$manual"
  done
  assert_gh_not_called
}

@test "hub pr -R --help and --repo -h print hub's manual" {
  run hub pr --help
  assert_success
  local manual=$output
  run hub pr -R --help
  assert_success
  assert_output_equals "$manual"
  run hub pr --repo -h
  assert_success
  assert_output_equals "$manual"
  assert_gh_not_called
}

@test "hub pr --help and -h after the subcommand are gh's" {
  stub_gh 'pr *' 'Display the title, body, and other information about a pull request.'
  run hub pr show --help
  assert_success
  assert_output_equals 'Display the title, body, and other information about a pull request.'
  hub pr view -h
  hub pr --repo=cli/cli show -h
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh pr view --help' 'gh pr view -h' \
    'gh pr --repo=cli/cli view -h')"
}

@test "hub help pr prints the same manual" {
  run hub pr --help
  assert_success
  local manual=$output
  run hub help pr
  assert_success
  assert_output_equals "$manual"
}

@test "hub pr without gh says gh is needed" {
  PATH=$(no_gh_path) run hub pr
  assert_status 1
  assert_output_equals 'hub pr: this command needs the GitHub CLI, gh (https://cli.github.com)'
}
