#!/usr/bin/env bats
# hub delete: gh repo delete with the repository named in full.

load test_helper

@test "hub delete -y NAME deletes your repository of that name without asking" {
  stub_gh 'repo delete *' 'Deleted repository mislav/dotfiles'
  run hub delete -y dotfiles
  assert_success
  assert_output_equals 'Deleted repository mislav/dotfiles'
  local calls=$'gh config get user -h github.com\ngh repo delete github.com/mislav/dotfiles --yes'
  assert_equals "$(gh_calls)" "$calls"
}

@test "hub delete OWNER/NAME lets gh ask, and looks up no login" {
  stub_gh 'repo delete *' ''
  run hub delete octo-org/old-site
  assert_success
  assert_equals "$(gh_calls)" 'gh repo delete github.com/octo-org/old-site'
}

@test "hub delete passes HOST/OWNER/NAME and repository URLs with their host" {
  stub_gh 'repo delete *' ''
  run hub delete --yes GitHub.com/octo/site
  assert_success
  assert_equals "$(gh_calls)" 'gh repo delete github.com/octo/site --yes'
  : >"$HUB_TEST_GH_LOG"
  local name
  for name in https://github.com/octo/site.git git@github.com:octo/site.git \
    ssh://git@GitHub.com/octo/site octo/site.git github.com/octo/site.git; do
    : >"$HUB_TEST_GH_LOG"
    run hub delete "$name"
    assert_success
    assert_equals "$(gh_calls)" 'gh repo delete github.com/octo/site'
  done
}

@test "hub delete NAME is your login's on GH_HOST" {
  stub_gh 'config get user -h ghe.example.com' alice
  stub_gh 'repo delete *' ''
  GH_HOST=ghe.example.com run hub delete -y tools
  assert_success
  assert_gh_called 'repo delete ghe.example.com/alice/tools --yes'
  GH_HOST=ghe.example.com run hub delete bob/tools
  assert_success
  assert_gh_called 'repo delete ghe.example.com/bob/tools'
}

@test "hub delete NAME takes a mixed-case GH_HOST in lowercase" {
  stub_gh 'config get user -h ghe.example.com' alice
  stub_gh 'repo delete *' ''
  GH_HOST=GHE.Example.com run hub delete -y tools
  assert_success
  assert_gh_called 'repo delete ghe.example.com/alice/tools --yes'
  : >"$HUB_TEST_GH_LOG"
  GH_HOST=GHE.Example.com run hub delete bob/tools.git
  assert_success
  assert_equals "$(gh_calls)" 'gh repo delete ghe.example.com/bob/tools'
}

@test "hub delete NAME is your login's on gh's only host when GH_HOST is unset" {
  mkdir -p "$GH_CONFIG_DIR"
  printf 'ghe.example.com:\n    user: alice\n' >"$GH_CONFIG_DIR/hosts.yml"
  stub_gh 'config get user -h ghe.example.com' alice
  stub_gh 'repo delete *' ''
  run hub delete -y tools
  assert_success
  assert_equals "$(gh_calls | head -n 1)" 'gh config get user -h ghe.example.com'
  assert_gh_called 'repo delete ghe.example.com/alice/tools --yes'
}

@test "hub delete NAME asks the API for your login when a token variable is set" {
  stub_gh 'api --hostname github.com user --jq .login' tokenuser
  stub_gh 'repo delete *' ''
  GH_TOKEN=t0ken run hub delete -y dotfiles
  assert_success
  assert_equals "$(gh_calls | head -n 1)" 'gh api --hostname github.com user --jq .login'
  assert_gh_called 'repo delete github.com/tokenuser/dotfiles --yes'
}

@test "hub delete takes options after the name and a name after --" {
  stub_gh 'repo delete *' ''
  run hub delete dotfiles -y
  assert_success
  assert_gh_called 'repo delete github.com/mislav/dotfiles --yes'
  : >"$HUB_TEST_GH_LOG"
  run hub delete -- octo/-y
  assert_success
  assert_equals "$(gh_calls)" 'gh repo delete github.com/octo/-y'
}

@test "hub delete NAME inside a clone of another owner's repository is still yours" {
  make_repo site origin=https://github.com/octo/site.git upstream=https://github.com/octo/site.git
  stub_gh 'repo delete *' ''
  GH_REPO=octo/site run hub delete -y site
  assert_success
  assert_gh_called 'GH_REPO=octo/site gh repo delete github.com/mislav/site --yes'
}

@test "hub delete works outside a repository and exits with gh's status" {
  stub_gh 'repo delete *' 'HTTP 403: Must have admin rights to Repository.' 1
  run hub delete -y octo/site
  assert_status 1
  assert_output_equals 'HTTP 403: Must have admin rights to Repository.'
  assert_gh_called 'repo delete github.com/octo/site --yes'
}

@test "hub delete refuses no name, two names and unknown options" {
  run hub delete
  assert_status 1
  assert_line_equals 0 'hub delete: name the repository to delete'
  assert_line_equals 1 'Usage: hub delete [-y] [[HOST/]OWNER/]NAME'
  run hub delete -y octo/a octo/b
  assert_status 1
  assert_line_equals 0 'hub delete: unexpected argument: octo/b'
  local option
  for option in -f:-f --force:--force --confirm:--confirm --yes=1:--yes=1 -yf:-f; do
    run hub delete "${option%%:*}" octo/site
    assert_status 1
    assert_line_equals 0 "hub delete: unknown option: ${option#*:}"
    assert_line_equals 1 'Usage: hub delete [-y] [[HOST/]OWNER/]NAME'
  done
  assert_gh_not_called
}

@test "hub delete refuses what is not a repository before asking gh anything" {
  local name forms='NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL'
  for name in 'a b' . .. 'octo/' 'octo//site' 'octo/site/' 'a/b/c/d' -x/octo/site 'o_o/site' \
    'octo/../site' 'https://example.com/octo/site' 'octo/site/tree' -x .git 'octo/.git'; do
    run hub delete -y -- "$name"
    assert_status 1
    assert_output_equals "hub delete: not a repository: $name (use $forms)"
  done
  assert_gh_not_called
}

@test "hub delete NAME stops when your login is unknown" {
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user --jq .login' '' 1
  run hub delete -y dotfiles
  assert_status 1
  local fix='run: gh auth login -h github.com'
  assert_output_equals "hub delete: could not determine your GitHub login for github.com ($fix)"
  assert_equals "$(gh_calls | grep -c 'repo delete')" 0
}

@test "hub delete needs gh" {
  mkdir nogh
  ln -s "$(command -v git)" nogh/git
  ln -s "$(command -v bash)" nogh/bash
  local name gh_url=https://cli.github.com
  for name in octo/site dotfiles; do
    PATH=$HUB_TEST_TMP/nogh:/usr/bin:/bin run hub delete -y "$name"
    assert_status 1
    assert_output_equals "hub delete: this command needs the GitHub CLI, gh ($gh_url)"
  done
  assert_gh_not_called
}

@test "hub delete --help prints its manual with the scope it needs" {
  run hub delete --help
  assert_success
  assert_line_equals 0 'Summary: Delete a repository on GitHub.'
  assert_output_contains 'gh auth refresh -s delete_repo'
  run hub delete -h octo/site
  assert_success
  assert_line_equals 0 'Summary: Delete a repository on GitHub.'
  run hub help delete
  assert_success
  assert_line_equals 0 'Summary: Delete a repository on GitHub.'
  assert_gh_not_called
}
