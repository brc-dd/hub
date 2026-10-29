#!/usr/bin/env bats
load ../test_helper

@test "browse opens the current repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles"
  assert_gh_not_called
}

@test "browse prefers the upstream remote" {
  make_repo dotfiles origin=git@github.com:mislav/dotfiles.git upstream=https://github.com/dotcom/dotfiles.git
  set_remote_head upstream main
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles"
}

@test "browse on a branch other than the default opens its tree" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature/x
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature/x"
}

@test "browse uses the default branch reported by the remote HEAD" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin trunk
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/main"
  git checkout -q -b trunk
  run hub --noop browse
  assert_output_equals "open https://github.com/mislav/dotfiles"
}

@test "browse asks gh for the default branch when the remote HEAD is unknown" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef *' 'main'
  git checkout -q -b feature
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  assert_gh_called 'repo view github.com/mislav/dotfiles --json defaultBranchRef *'
}

@test "browse opens a branch that pushes to a fork in the fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote mislav
  git config branch.feature.merge refs/heads/feature
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
}

@test "browse -- commits and -- tree follow a branch other than the default" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feat
  run hub --noop browse -- commits
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/commits/feat"
  run hub --noop browse -- tree
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feat"
  git checkout -q -b 'fix#12'
  run hub browse -u -- commits
  assert_output_equals "https://github.com/mislav/dotfiles/commits/fix%2312"
  assert_gh_not_called
}

@test "browse -- commits and -- tree on the default branch open the history and the front page" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub --noop browse -- commits
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/commits"
  run hub --noop browse -- tree
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles"
}

@test "browse -- commits and -- tree open a branch that pushes to a fork in the fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote mislav
  git config branch.feature.merge refs/heads/feature
  run hub --noop browse -- commits
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/commits/feature"
  run hub --noop browse -- tree
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  run hub --noop browse -- issues
  assert_output_equals "open https://github.com/dotcom/dotfiles/issues"
}

@test "browse REPO tree, and tree with GH_REPO, open the front page" {
  run hub --noop browse cli/cli tree
  assert_success
  assert_output_equals "open https://github.com/cli/cli"
  run hub --noop browse cli/cli commits
  assert_output_equals "open https://github.com/cli/cli/commits"
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git checkout -q -b feature
  GH_REPO=cli/cli run hub --noop browse -- tree
  assert_output_equals "open https://github.com/cli/cli"
  GH_REPO=cli/cli run hub --noop browse -- commits
  assert_output_equals "open https://github.com/cli/cli/commits"
  assert_gh_not_called
}

@test "browse escapes branch names" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b 'fix#12+more'
  run hub browse -u
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/tree/fix%2312%2Bmore"
}

@test "browse -- SUBPAGE opens a page of the current repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git checkout -q -b feature
  run hub --noop browse -- issues
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/issues"
  run hub --noop browse -- tree/main/lib
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/main/lib"
  assert_gh_not_called
}

@test "browse OWNER/REPO SUBPAGE works outside a repository" {
  run hub --noop browse cli/cli releases
  assert_success
  assert_output_equals "open https://github.com/cli/cli/releases"
  run hub --noop browse cli/cli
  assert_output_equals "open https://github.com/cli/cli"
  assert_gh_not_called
}

@test "browse REPO means your own repository" {
  run hub --noop browse dotfiles wiki
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
  assert_gh_called 'config get user -h github.com'
}

@test "browse -u prints the URL instead of opening it" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub browse -u -- pulls
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/pulls"
  run hub browse --url
  assert_output_equals "https://github.com/mislav/dotfiles"
}

@test "browse -c copies the URL instead of opening it" {
  run hub --noop browse -c cli/cli actions
  assert_success
  assert_output_equals "copy to clipboard: https://github.com/cli/cli/actions"
  run hub --noop browse -u -c cli/cli
  assert_output_equals $'https://github.com/cli/cli\ncopy to clipboard: https://github.com/cli/cli'
}

@test "browse opens URLs with BROWSER" {
  export BROWSER="printf 'BROWSER %s\n'"
  run hub browse cli/cli
  assert_success
  assert_output_equals "BROWSER https://github.com/cli/cli"
}

@test "browse uses the enterprise host of the remote" {
  make_repo app origin=git@ghe.example.com:corp/app.git
  set_remote_head origin main
  run hub --noop browse
  assert_failure
  assert_output_contains "could not find a GitHub remote"
  export GH_HOST=ghe.example.com
  run hub --noop browse -- settings
  assert_success
  assert_output_equals "open https://ghe.example.com/corp/app/settings"
}

@test "browse OWNER/REPO uses GH_HOST, and HOST/OWNER/REPO names the host" {
  GH_HOST=ghe.example.com run hub --noop browse corp/app pulls
  assert_success
  assert_output_equals "open https://ghe.example.com/corp/app/pulls"
  stub_gh 'config get user -h ghe.example.com' 'mona'
  GH_HOST=ghe.example.com run hub --noop browse app
  assert_output_equals "open https://ghe.example.com/mona/app"
  run hub --noop browse ghe.example.com/corp/app issues
  assert_output_equals "open https://ghe.example.com/corp/app/issues"
}

@test "browse honours GH_REPO and does not guess a branch for it" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git checkout -q -b feature
  GH_REPO=cli/cli run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/cli/cli"
}

@test "browse outside a GitHub repository fails" {
  make_repo local-only
  run hub --noop browse
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
}

@test "browse rejects unknown options and extra arguments" {
  run hub browse --bogus
  assert_failure
  assert_output_contains "unknown option: --bogus"
  run hub browse a/b c d
  assert_failure
  assert_output_contains "Usage: hub browse"
}

@test "browse --help prints the manual" {
  run hub browse --help
  assert_success
  assert_output_contains "Usage: hub browse [-u] [-c]"
}
