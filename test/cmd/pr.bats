#!/usr/bin/env bats
load ../test_helper

@test "pr passes other subcommands and options to gh pr unchanged" {
  local args
  for args in "" "list -s closed -L 5 -H feature" "status" "checks 12 --watch" "view 12 --comments" \
    "merge 12 --squash -d" "edit 12 --add-label bug" "-R cli/cli list" "list --help" \
    "view https://github.com/cli/cli/pull/1"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pr $args
    assert_success
    assert_output_equals "gh pr${args:+ $args}"
  done
  assert_gh_not_called
}

@test "pr show is gh pr view, with gh's options" {
  local args
  for args in "" "12" "12 -w" "feature --web" "12 -c"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pr show $args
    assert_success
    assert_output_equals "gh pr view${args:+ $args}"
  done
}

@test "pr show -u prints only the URL, with hub's flags ahead of --" {
  run hub --noop pr show -u
  assert_success
  assert_output_equals "gh pr view --json url --jq .url"
  run hub --noop pr show --url 12 -R cli/cli
  assert_success
  assert_output_equals "gh pr view --json url --jq .url 12 -R cli/cli"
  run hub --noop pr show -u -- 123
  assert_success
  assert_output_equals "gh pr view --json url --jq .url -- 123"
  run hub --noop pr show -- -u
  assert_success
  assert_output_equals "gh pr view -- -u"
}

@test "pr show leaves the values of gh's options alone" {
  run hub --noop pr show 1 --json title --template -u
  assert_success
  assert_output_equals "gh pr view 1 --json title --template -u"
  run hub --noop pr show 1 -q -u -t --url -R -u
  assert_success
  assert_output_equals "gh pr view 1 -q -u -t --url -R -u"
}

@test "pr checkout N BRANCH turns the branch into -b" {
  run hub --noop pr checkout 12
  assert_success
  assert_output_equals "gh pr checkout 12"
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
  run hub --noop pr checkout --worktree ../wt -R cli/cli 12 local -u
  assert_success
  assert_output_equals "gh pr checkout --worktree ../wt -R cli/cli 12 -b local -u"
}

@test "pr --help and -h print hub's manual" {
  run hub pr --help
  assert_success
  assert_output_contains "Usage: hub pr"
  run hub pr -h
  assert_success
  assert_output_contains "Usage: hub pr"
}

@test "pr without --noop hands over to gh" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'pr view --json url --jq .url 12' 'https://github.com/mislav/dotfiles/pull/12'
  run hub pr show -u 12
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/pull/12"
  assert_gh_called 'pr view --json url --jq .url 12'
}
