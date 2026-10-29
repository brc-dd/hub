#!/usr/bin/env bats
load ../test_helper

@test "pr list is gh pr list, options unchanged" {
  run hub --noop pr list -s closed -L 5 -H feature
  assert_success
  assert_output_equals "gh pr list -s closed -L 5 -H feature"
  assert_gh_not_called
}

@test "pr with no subcommand runs gh pr" {
  run hub --noop pr
  assert_success
  assert_output_equals "gh pr"
}

@test "pr show is gh pr view, in the terminal" {
  run hub --noop pr show
  assert_success
  assert_output_equals "gh pr view"
  run hub --noop pr show 12
  assert_success
  assert_output_equals "gh pr view 12"
}

@test "pr show -w opens the browser through gh" {
  run hub --noop pr show 12 -w
  assert_success
  assert_output_equals "gh pr view 12 -w"
  run hub --noop pr show feature --web
  assert_success
  assert_output_equals "gh pr view feature --web"
}

@test "pr show -u prints only the URL" {
  run hub --noop pr show -u
  assert_success
  assert_output_equals "gh pr view --json url --jq .url"
  run hub --noop pr show --url 12 -R cli/cli
  assert_success
  assert_output_equals "gh pr view 12 -R cli/cli --json url --jq .url"
}

@test "pr show keeps gh's own options, such as -c for comments" {
  run hub --noop pr show 12 -c
  assert_success
  assert_output_equals "gh pr view 12 -c"
}

@test "pr checkout N is gh pr checkout" {
  run hub --noop pr checkout 12
  assert_success
  assert_output_equals "gh pr checkout 12"
}

@test "pr checkout N BRANCH turns the branch into -b" {
  run hub --noop pr checkout 12 fix-typo
  assert_success
  assert_output_equals "gh pr checkout 12 -b fix-typo"
  run hub --noop pr checkout https://github.com/mislav/dotfiles/pull/12 fix-typo --force
  assert_success
  assert_output_equals "gh pr checkout https://github.com/mislav/dotfiles/pull/12 -b fix-typo --force"
  run hub --noop pr co 12 fix-typo
  assert_success
  assert_output_equals "gh pr co 12 -b fix-typo"
}

@test "pr checkout does not mistake option values for the branch" {
  run hub --noop pr checkout -b mine 12 --detach
  assert_success
  assert_output_equals "gh pr checkout -b mine 12 --detach"
  run hub --noop pr checkout --worktree ../wt -R cli/cli 12 local
  assert_success
  assert_output_equals "gh pr checkout --worktree ../wt -R cli/cli 12 -b local"
}

@test "pr merge is gh pr merge, which merges on GitHub" {
  run hub --noop pr merge 12 --squash -d
  assert_success
  assert_output_equals "gh pr merge 12 --squash -d"
}

@test "other subcommands pass through to gh pr unchanged" {
  run hub --noop pr status
  assert_success
  assert_output_equals "gh pr status"
  run hub --noop pr checks 12 --watch
  assert_success
  assert_output_equals "gh pr checks 12 --watch"
  run hub --noop pr view 12 --comments
  assert_success
  assert_output_equals "gh pr view 12 --comments"
  run hub --noop pr edit 12 --add-label bug
  assert_success
  assert_output_equals "gh pr edit 12 --add-label bug"
  run hub --noop pr comment 12 -b "Looks good"
  assert_success
  assert_output_equals "gh pr comment 12 -b Looks\\ good"
}

@test "options before the subcommand pass through" {
  run hub --noop pr -R cli/cli list
  assert_success
  assert_output_equals "gh pr -R cli/cli list"
}

@test "pr --help prints hub's manual; subcommand help is gh's" {
  run hub pr --help
  assert_success
  assert_output_contains "Usage: hub pr"
  run hub pr -h
  assert_success
  assert_output_contains "Usage: hub pr"
  run hub --noop pr list --help
  assert_success
  assert_output_equals "gh pr list --help"
}

@test "pr works outside a repository" {
  run hub --noop pr view https://github.com/cli/cli/pull/1
  assert_success
  assert_output_equals "gh pr view https://github.com/cli/cli/pull/1"
}

@test "pr without --noop hands over to gh" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'pr view 12 --json url --jq .url' 'https://github.com/mislav/dotfiles/pull/12'
  run hub pr show -u 12
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/pull/12"
  assert_gh_called 'pr view 12 --json url --jq .url'
}
