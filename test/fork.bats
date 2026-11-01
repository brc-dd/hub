#!/usr/bin/env bats
# hub fork: GitHub's fork API through gh, the remote hub adds, and hub's checks before gh.

load test_helper

# dotfiles : a clone of the served dotcom/dotfiles, and gh forking it to mislav/dotfiles.
dotfiles() {
  serve_github dotcom/dotfiles mislav/dotfiles
  clone_served dotcom/dotfiles
  stub_forks mislav/dotfiles
}

# stub_forks ANSWER [STATUS] [HOST] : the fork API's .full_name answer from gh api for HOST.
stub_forks() {
  stub_gh "api --hostname ${3:-github.com} --method POST repos/*/forks*" "$1" "${2:-0}"
}

# forks PROJECT [FIELDS] : the arguments of gh's fork API call for PROJECT on github.com.
forks() {
  printf 'api --hostname github.com --method POST repos/%s/forks %s--jq .full_name' "$1" "${2:+$2 }"
}

@test "hub fork names the project to gh and adds the fork as a remote named after you" {
  dotfiles
  run hub fork
  assert_success
  assert_equals "$(gh_calls | grep forks)" "gh $(forks dotcom/dotfiles)"
  assert_equals "$(git remote get-url mislav)" https://github.com/mislav/dotfiles.git
  assert_equals "$(git remote get-url origin)" https://github.com/dotcom/dotfiles.git
  assert_equals "$(git for-each-ref refs/remotes/mislav)" ''
  git fetch -q mislav
  assert_equals "$(git rev-parse refs/remotes/mislav/main)" "$(server_ref mislav/dotfiles main)"
}

@test "hub fork forks the upstream remote's repository, and GH_REPO when it is set" {
  make_repo dotfiles origin=https://github.com/hubot/dotfiles.git \
    upstream=https://github.com/dotcom/dotfiles.git
  stub_forks mislav/dotfiles
  run hub fork
  assert_success
  assert_gh_called "$(forks dotcom/dotfiles)"
  assert_equals "$(git remote get-url mislav)" https://github.com/mislav/dotfiles.git
  stub_gh 'config get user -h ghe.example.com' mona
  stub_forks mona/app 0 ghe.example.com
  GH_REPO=ghe.example.com/corp/app run hub fork
  assert_success
  local fork='api --hostname ghe.example.com --method POST repos/corp/app/forks --jq .full_name'
  assert_gh_called "GH_REPO=ghe.example.com/corp/app gh $fork"
  assert_equals "$(git remote get-url mona)" https://ghe.example.com/mona/app.git
}

@test "hub fork runs in the directory hub was started in, under -C and in a subdirectory" {
  dotfiles
  mkdir sub
  cd ..
  run hub -C dotfiles/sub fork
  assert_success
  assert_equals "$(git -C dotfiles remote get-url mislav)" https://github.com/mislav/dotfiles.git
}

@test "hub fork ORG and --org fork into the organization, with a remote named after it" {
  dotfiles
  stub_forks acme/dotfiles
  run hub fork acme
  assert_success
  assert_gh_called "$(forks dotcom/dotfiles '-f organization=acme')"
  assert_equals "$(git remote get-url acme)" https://github.com/acme/dotfiles.git
  git remote remove acme
  : >"$HUB_TEST_GH_LOG"
  run hub fork --org=acme ACME
  assert_success
  assert_gh_called "$(forks dotcom/dotfiles '-f organization=acme')"
  assert_equals "$(git remote get-url acme)" https://github.com/acme/dotfiles.git
  run gh_calls
  assert_output_lacks 'config get user'
}

@test "hub fork sends --org, --fork-name and --default-branch-only as the API's fields" {
  dotfiles
  stub_forks acme/dots
  run hub fork --default-branch-only --fork-name=dots --remote-name mine --org acme
  assert_success
  local fields='-f organization=acme -f name=dots -F default_branch_only=true'
  assert_gh_called "$(forks dotcom/dotfiles "$fields")"
  assert_equals "$(git remote get-url mine)" https://github.com/acme/dots.git
  run git remote get-url acme
  assert_failure
}

@test "hub fork leaves organization and fork names to gh, which judges them" {
  dotfiles
  stub_forks 'HTTP 422: invalid organization' 1
  run hub fork --remote-name mine --fork-name 'a/b' -- -acme
  assert_status 1
  assert_gh_called "$(forks dotcom/dotfiles '-f organization=-acme -f name=a/b')"
  assert_equals "$(git remote)" origin
}

@test "hub fork adds the fork GitHub answers with, an existing fork with another name too" {
  dotfiles
  stub_forks mislav/dotfiles-1
  run hub fork
  assert_success
  assert_equals "$(git remote get-url mislav)" https://github.com/mislav/dotfiles-1.git
  git remote remove mislav
  # With --fork-name, an existing fork keeps its own name.
  run hub fork --fork-name dots
  assert_success
  assert_gh_called "$(forks dotcom/dotfiles '-f name=dots')"
  assert_equals "$(git remote get-url mislav)" https://github.com/mislav/dotfiles-1.git
}

@test "hub fork does not read gh repo fork, which prints nothing for an existing fork" {
  dotfiles
  stub_gh 'repo fork *' ''
  run hub fork
  assert_success
  assert_equals "$(git remote get-url mislav)" https://github.com/mislav/dotfiles.git
  run gh_calls
  assert_output_lacks 'repo fork'
}

@test "hub fork gives the remote gh's git_protocol for the fork's host" {
  dotfiles
  stub_gh 'config get git_protocol -h github.com' ssh
  run hub fork
  assert_success
  assert_equals "$(git remote get-url mislav)" git@github.com:mislav/dotfiles.git
}

@test "hub fork uses the protocol and the tenant's ssh user of a ghe.com host GH_REPO names" {
  make_repo app
  stub_gh 'config get user -h acme.ghe.com' mona
  stub_gh 'config get git_protocol -h acme.ghe.com' ssh
  stub_forks mona/app 0 acme.ghe.com
  GH_REPO=acme.ghe.com/corp/app run hub fork
  assert_success
  assert_gh_called 'GH_REPO=acme.ghe.com/corp/app gh api --hostname acme.ghe.com *corp/app/forks*'
  assert_equals "$(git remote get-url mona)" acme@acme.ghe.com:mona/app.git
}

@test "hub fork stops when GitHub names no fork, and adds no remote" {
  dotfiles
  stub_forks ''
  run hub fork
  assert_status 1
  assert_output_equals \
    "hub fork: GitHub did not name the fork: '' (add the remote with git remote add)"
  assert_equals "$(git remote)" origin
  for answer in null mislav 'mislav/dot files' '-x/dotfiles'; do
    stub_forks "$answer"
    run hub fork
    assert_status 1
    assert_output_contains 'hub fork: GitHub did not name the fork: '
    assert_output_contains ' (add the remote with git remote add)'
  done
  assert_equals "$(git remote)" origin
}

@test "hub fork fails as gh fails, and changes nothing after it" {
  dotfiles
  PATH=$(failing_gh 'HTTP 403: forking is disabled'):$PATH
  stub_forks '' 4
  run hub fork
  assert_status 4
  assert_output_equals 'HTTP 403: forking is disabled'
  assert_equals "$(git remote)" origin
}

@test "hub fork --no-remote only forks, in a repository or outside one with GH_REPO" {
  dotfiles
  run hub fork --no-remote --default-branch-only
  assert_success
  assert_output_equals mislav/dotfiles
  assert_gh_called "$(forks dotcom/dotfiles '-F default_branch_only=true')"
  assert_equals "$(git remote)" origin
  cd "$HUB_TEST_TMP"
  : >"$HUB_TEST_GH_LOG"
  stub_forks acme/app 0 ghe.example.com
  GH_REPO=ghe.example.com/corp/app run hub fork --no-remote acme
  assert_success
  assert_output_equals acme/app
  local fork='api --hostname ghe.example.com --method POST repos/corp/app/forks'
  fork+=' -f organization=acme --jq .full_name'
  assert_equals "$(gh_calls)" "GH_REPO=ghe.example.com/corp/app gh $fork"
  : >"$HUB_TEST_GH_LOG"
  GH_REPO=dotcom/dotfiles run hub fork --no-remote --org acme --fork-name dots
  assert_success
  assert_gh_called "GH_REPO=dotcom/dotfiles gh $(forks dotcom/dotfiles \
    '-f organization=acme -f name=dots')"
}

@test "hub fork --no-remote outside a repository without GH_REPO relays git's error" {
  run hub fork --no-remote
  assert_status 1
  assert_output_contains 'fatal: not a git repository'
  assert_output_lacks 'no GitHub remote'
  assert_gh_not_called
}

@test "hub fork --no-remote refuses --remote-name" {
  dotfiles
  run hub fork --no-remote --remote-name mine
  assert_status 1
  assert_line_equals 0 'hub fork: --no-remote adds no remote to name (drop --remote-name)'
  local usage='Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME]'
  assert_line_equals 1 "$usage"
  assert_gh_not_called
}

@test "hub fork needs a repository, a GitHub project, and a free and valid remote name" {
  run hub fork
  assert_status 1
  assert_output_contains 'fatal: not a git repository'
  assert_gh_not_called
  make_repo local
  stub_forks mislav/local
  run hub fork
  assert_status 1
  assert_output_equals 'hub fork: no GitHub remote found (looked for upstream, github, origin)'
  git remote add origin https://github.com/dotcom/local.git
  git remote add mislav https://example.com/elsewhere.git
  run hub fork
  assert_status 1
  assert_output_equals \
    'hub fork: remote already exists: mislav (name another with --remote-name NAME)'
  run hub fork --remote-name origin
  assert_status 1
  assert_output_equals \
    'hub fork: remote already exists: origin (name another with --remote-name NAME)'
  run hub fork --remote-name 'my fork'
  assert_status 1
  assert_output_equals 'hub fork: not a remote name: my\ fork'
  run hub fork --remote-name=-x
  assert_status 1
  assert_output_equals 'hub fork: not a remote name: -x'
  run hub fork -- -acme
  assert_status 1
  assert_output_equals 'hub fork: not a remote name: -acme'
  run gh_calls
  assert_output_lacks forks
  assert_equals "$(git remote get-url mislav)" https://example.com/elsewhere.git
}

@test "hub fork refuses a remote named after you in another case, before gh forks" {
  dotfiles
  git remote add Mislav https://github.com/mislav/dotfiles.git
  run hub fork
  assert_status 1
  assert_output_equals \
    'hub fork: remote already exists: Mislav (name another with --remote-name NAME)'
  assert_equals "$(gh_calls)" 'gh config get user -h github.com'
  assert_equals "$(git remote)" $'Mislav\norigin'
}

@test "hub fork stops before gh when your login is unknown" {
  dotfiles
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user --jq .login' '' 1
  run hub fork
  assert_status 1
  local hint='(run: gh auth login -h github.com)'
  assert_output_equals "hub fork: could not determine your GitHub login for github.com $hint"
  # Without a token variable the API is not asked.
  assert_equals "$(gh_calls)" 'gh config get user -h github.com'
  assert_equals "$(git remote)" origin
}

@test "hub fork without gh on PATH says so once and changes nothing" {
  dotfiles
  local needs='hub fork: this command needs the GitHub CLI, gh (https://cli.github.com)'
  for args in '' --no-remote '--remote-name x' '--remote-name origin' origin; do
    # shellcheck disable=SC2086  # the words of args are separate arguments
    PATH=$(no_gh_path) run hub fork $args
    assert_status 1
    assert_output_equals "$needs"
  done
  cd "$HUB_TEST_TMP"
  PATH=$(no_gh_path) run hub fork
  assert_status 1
  assert_output_equals "$needs"
  assert_gh_not_called
  assert_equals "$(git -C "$HUB_TEST_TMP/dotfiles" remote)" origin
}

@test "hub fork refuses unknown options, extra arguments, missing values and two organizations" {
  dotfiles
  local usage='Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME]'
  run hub fork --clone
  assert_status 1
  assert_line_equals 0 'hub fork: unknown option: --clone'
  assert_line_equals 1 "$usage"
  assert_line_equals 2 '                [--default-branch-only] [ORG]'
  run hub fork --no-remote=1
  assert_status 1
  assert_line_equals 0 'hub fork: unknown option: --no-remote=1'
  run hub fork acme other
  assert_status 1
  assert_line_equals 0 'hub fork: unexpected argument: other'
  run hub fork --org
  assert_status 1
  assert_line_equals 0 'hub fork: --org needs a value'
  run hub fork --fork-name
  assert_status 1
  assert_line_equals 0 'hub fork: --fork-name needs a value'
  run hub fork --fork-name=
  assert_status 1
  assert_line_equals 0 'hub fork: empty fork name'
  assert_line_equals 1 "$usage"
  run hub fork --org ''
  assert_status 1
  assert_line_equals 0 'hub fork: empty organization'
  assert_line_equals 1 "$usage"
  run hub fork --remote-name ''
  assert_status 1
  assert_output_equals "hub fork: not a remote name: ''"
  run hub fork ''
  assert_status 1
  assert_line_equals 0 'hub fork: empty organization'
  assert_line_equals 1 "$usage"
  run hub fork --org acme other
  assert_status 1
  assert_line_equals 0 'hub fork: two organizations: --org acme and other (name one)'
  assert_line_equals 1 "$usage"
  assert_line_equals 2 '                [--default-branch-only] [ORG]'
  run hub fork --org a 'b c'
  assert_status 1
  assert_line_equals 0 "hub fork: two organizations: --org a and b\\ c (name one)"
  run hub fork --org $'x\ny' acme
  assert_status 1
  assert_line_equals 0 "hub fork: two organizations: --org \$'x\\ny' and acme (name one)"
  assert_gh_not_called
  assert_equals "$(git remote)" origin
}

# What gh would do cannot happen locally: --noop shows the commands hub would run.
@test "hub --noop fork prints the gh and git commands and changes nothing" {
  dotfiles
  run hub --noop fork --fork-name dots
  assert_success
  assert_line_equals 0 "gh $(forks dotcom/dotfiles '-f name=dots')"
  assert_line_equals 1 'git remote add -- mislav https://github.com/mislav/dots.git'
  run hub --noop fork --no-remote --org acme
  assert_success
  assert_output_equals "gh $(forks dotcom/dotfiles '-f organization=acme')"
  run gh_calls
  assert_output_lacks forks
  assert_equals "$(git remote)" origin
}

@test "hub --noop fork predicts the fork from the names as given, which GitHub may normalize" {
  dotfiles
  run hub --noop fork --fork-name 'my fork'
  assert_success
  assert_line_equals 0 "gh $(forks dotcom/dotfiles '-f name=my\ fork')"
  assert_line_equals 1 "git remote add -- mislav https://github.com/mislav/my\\ fork.git"
  run hub --noop fork --org 'Acme Corp' --remote-name y
  assert_success
  assert_line_equals 1 "git remote add -- y https://github.com/Acme\\ Corp/dotfiles.git"
  assert_equals "$(git remote)" origin
}

@test "hub fork --help prints its manual" {
  run hub fork --help
  assert_success
  assert_line_equals 0 'Summary: Fork the project on GitHub and add the fork as a remote.'
  run hub fork -h
  assert_line_equals 0 'Summary: Fork the project on GitHub and add the fork as a remote.'
  assert_gh_not_called
}
