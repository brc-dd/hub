#!/usr/bin/env bats
load ../test_helper

@test "pr with no subcommand word is gh pr list, options in place" {
  run hub --noop pr
  assert_success
  assert_output_equals "gh pr list"
  run hub --noop pr -s closed -L 5
  assert_success
  assert_output_equals "gh pr list -s closed -L 5"
  run hub --noop pr -R cli/cli --repo=cli/cli -L5
  assert_success
  assert_output_equals "gh pr list -R cli/cli --repo=cli/cli -L5"
  run hub --noop pr --search "is:open label:bug"
  assert_success
  assert_output_equals "gh pr list --search is:open\\ label:bug"
  assert_gh_not_called
}

@test "pr show is gh pr view, with every other argument in its place" {
  run hub --noop pr show 12 --comments
  assert_success
  assert_output_equals "gh pr view 12 --comments"
  run hub --noop pr show 1 -R cli/cli
  assert_success
  assert_output_equals "gh pr view 1 -R cli/cli"
  run hub --noop pr show
  assert_success
  assert_output_equals "gh pr view"
}

@test "pr: a repository option before the subcommand word does not hide it, and stays where it was" {
  local repo
  for repo in "-R other/project" "-Rother/project" "-R=other/project" "--repo other/project" "--repo=other/project"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pr $repo show 1
    assert_success
    assert_output_equals "gh pr $repo view 1"
  done
  run hub --noop pr --repo=other/project checkout 1 localname
  assert_success
  assert_output_equals "gh pr --repo=other/project checkout 1 localname"
  assert_gh_not_called
}

@test "pr passes gh's subcommands and options through unchanged, in order" {
  local args
  for args in "list -s closed -L 5 -H feature" "status" "checks 12 --watch" "view 12 --comments" \
    "merge 12 --squash -d" "edit 12 --add-label bug" "co 12" "list --help" "create --fill -B main" \
    "view https://github.com/cli/cli/pull/1" "checkout https://github.com/cli/cli/pull/1 -b fix --force"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pr $args
    assert_success
    assert_output_equals "gh pr $args"
  done
  assert_gh_not_called
}

@test "pr passes a subcommand gh does not know on, for gh to reject" {
  run hub --noop pr frobnicate 12 -R cli/cli
  assert_success
  assert_output_equals "gh pr frobnicate 12 -R cli/cli"
  stub_gh 'pr frobnicate 12' 'unknown command "frobnicate" for "gh pr"' 1
  run hub pr frobnicate 12
  assert_failure
  assert_output_equals 'unknown command "frobnicate" for "gh pr"'
}

@test "pr does not translate old hub's options: they reach gh as typed" {
  run hub --noop pr show -u 12
  assert_success
  assert_output_equals "gh pr view -u 12"
  run hub --noop pr show --url 12 -R cli/cli
  assert_success
  assert_output_equals "gh pr view --url 12 -R cli/cli"
  # the local branch is gh's -b; a second word is gh's to reject
  run hub --noop pr checkout 123 fix-typo
  assert_success
  assert_output_equals "gh pr checkout 123 fix-typo"
  run hub --noop pr checkout https://github.com/mislav/dotfiles/pull/12 fix-typo --force
  assert_success
  assert_output_equals "gh pr checkout https://github.com/mislav/dotfiles/pull/12 fix-typo --force"
  # a cluster is gh's to read, whichever letters it holds
  run hub --noop pr checkout -fb newbranch 123
  assert_success
  assert_output_equals "gh pr checkout -fb newbranch 123"
  run hub --noop pr checkout 123 -fb newbranch
  assert_success
  assert_output_equals "gh pr checkout 123 -fb newbranch"
  assert_gh_not_called
}

@test "pr: nothing after -- is read, not even a subcommand word" {
  run hub --noop pr -- show 12
  assert_success
  assert_output_equals "gh pr list -- show 12"
  run hub --noop pr -R cli/cli -- show
  assert_success
  assert_output_equals "gh pr list -R cli/cli -- show"
  run hub --noop pr view 12 -- show --repo=other/repo
  assert_success
  assert_output_equals "gh pr view 12 -- show --repo=other/repo"
  run hub --noop pr checkout -- 123 chosen
  assert_success
  assert_output_equals "gh pr checkout -- 123 chosen"
  run hub --noop pr checkout 123 -- chosen
  assert_success
  assert_output_equals "gh pr checkout 123 -- chosen"
  assert_gh_not_called
}

@test "pr finds the subcommand word where gh does: an option's value is never one" {
  run hub --noop pr -s show
  assert_success
  assert_output_equals "gh pr list -s show"
  run hub --noop pr --state show list
  assert_success
  assert_output_equals "gh pr --state show list"
  run hub --noop pr -R show 12
  assert_success
  assert_output_equals "gh pr -R show 12"
  run hub --noop pr -sclosed show 12
  assert_success
  assert_output_equals "gh pr -sclosed view 12"
  run hub --noop pr '' show 1
  assert_success
  assert_output_equals "gh pr '' view 1"
  run hub --noop pr -R # a missing value is gh's to report
  assert_success
  assert_output_equals "gh pr list -R"
}

@test "pr adds no repository or host of its own: gh resolves them from the remotes, GH_REPO or -R" {
  make_repo r1 origin=https://github.com/mislav/r1.git upstream=https://ghe.example.com/corp/r1.git
  run hub --noop pr view 12
  assert_success
  assert_output_equals "gh pr view 12"
  GH_REPO=ghe.example.com/corp/r1 run hub --noop pr checkout http://github.localhost/org/repo/pull/1
  assert_success
  assert_output_equals "gh pr checkout http://github.localhost/org/repo/pull/1"
  assert_gh_not_called
}

@test "pr -h and --help before the subcommand word print hub's manual; after it, gh's" {
  run hub pr --help
  assert_success
  assert_output_contains "Usage: hub pr [SUBCOMMAND] [gh pr options]"
  run hub pr -h
  assert_success
  assert_output_contains "Usage: hub pr"
  run hub pr -R cli/cli --help
  assert_success
  assert_output_contains "Usage: hub pr"
  run hub help pr
  assert_success
  assert_output_contains "Usage: hub pr"
  run hub --noop pr list --help
  assert_success
  assert_output_equals "gh pr list --help"
  run hub --noop pr view 12 -h
  assert_success
  assert_output_equals "gh pr view 12 -h"
  run hub --noop pr --help=false list # a value makes it gh's boolean, not a request for help
  assert_success
  assert_output_equals "gh pr --help=false list"
  assert_gh_not_called
}

@test "pr hands over to gh and returns its output and status" {
  stub_gh 'pr view 12 --json url --jq .url' 'https://github.com/cli/cli/pull/12'
  run hub pr show 12 --json url --jq .url
  assert_success
  assert_output_equals "https://github.com/cli/cli/pull/12"
  stub_gh 'pr list -s closed' 'no pull requests match your search' 1
  run hub pr -s closed
  assert_failure
  assert_output_equals "no pull requests match your search"
  assert_equals "$(gh_calls)" $'gh pr view 12 --json url --jq .url\ngh pr list -s closed'
}

@test "pr without gh gives hub's message" {
  mkdir nogh
  ln -s "$(command -v bash)" nogh/bash
  ln -s "$(command -v git)" nogh/git
  PATH=$PWD/nogh run hub pr list
  assert_failure
  assert_output_equals "hub: this command needs the GitHub CLI (gh): https://cli.github.com"
}
