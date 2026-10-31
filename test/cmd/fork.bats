#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test runs in a subshell, so its exports stay local on purpose
load ../test_helper

# fake_gh_fork : a gh whose `repo fork --remote` adds the remote as gh does: the fork of GH_REPO,
# with the scheme of the remote origin points at the parent with, and records GH_REPO.
fake_gh_fork() {
  mkdir -p "$HUB_TEST_TMP/fake"
  cat >"$HUB_TEST_TMP/fake/gh" <<'SH'
#!/usr/bin/env bash
[[ $1 == repo && $2 == fork ]] || exec "$HUB_TEST_ROOT/test/stubs/gh" "$@"
printf 'gh %s\n' "$*" >>"$HUB_TEST_LOG"
printf '%s\n' "${GH_REPO-}" >"$HUB_TEST_TMP/gh.repo"
owner=mislav name=${GH_REPO##*/} remote=origin
while (($#)); do
  case $1 in
    --remote-name) remote=$2 && shift ;;
    --org) owner=$2 && shift ;;
    --fork-name) name=$2 && shift ;;
  esac
  shift
done
url=https://github.com/$owner/$name.git
[[ $(git remote get-url origin) != git@* ]] || url=git@github.com:$owner/$name.git
git remote add "$remote" "$url"
SH
  chmod +x "$HUB_TEST_TMP/fake/gh"
  export PATH=$HUB_TEST_TMP/fake:$PATH
}

@test "fork forks hub's project with gh's compound command, which adds the fork as a remote named after you" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mislav"
  fake_gh_fork
  run hub fork
  assert_success
  assert_equals "$(cat "$HUB_TEST_TMP/gh.repo")" github.com/dotcom/dotfiles
  assert_equals "$(remote_url mislav)" https://github.com/mislav/dotfiles.git
  assert_gh_called 'repo fork --remote --remote-name mislav'
}

@test "fork forks the upstream remote's repository, whatever gh's default is, and GH_REPO when set" {
  make_repo dotfiles origin=https://github.com/hubot/dotfiles.git upstream=https://github.com/dotcom/dotfiles.git
  git config remote.origin.gh-resolved base # what gh repo set-default origin records
  run hub --noop fork
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mislav"
  stub_gh 'config get user -h ghe.example.com' 'mona'
  GH_REPO=ghe.example.com/corp/app run hub --noop fork
  assert_success
  assert_output_equals "env GH_REPO=ghe.example.com/corp/app gh repo fork --remote --remote-name mona"
}

@test "fork ORGANIZATION and --org fork into the organization, with a remote named after it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --org myorg
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name myorg --org myorg"
  run hub --noop fork myorg
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name myorg --org myorg"
  run hub --noop fork --org=myorg myorg
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name myorg --org myorg"
  run hub --noop fork --org myorg other
  assert_failure
  assert_output_equals "Aborted: name the organization once (--org myorg and other)."
  run hub --noop fork 'bad org'
  assert_failure
  assert_output_equals "Aborted: not an organization name: bad org (letters, digits and - only)"
  [[ $(gh_calls) != *"config get user"* ]] # no login lookup either
}

@test "fork --remote-name, --fork-name and --default-branch-only" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --remote-name fork
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name fork"
  run hub --noop fork --fork-name dots
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mislav --fork-name dots"
  run hub --noop fork --default-branch-only --remote-name=mine --org myorg --fork-name=dots
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mine --org myorg --fork-name dots --default-branch-only"
  run hub --noop fork --fork-name 'bad name'
  assert_failure
  assert_output_equals "Aborted: not a repository name: bad name (letters, digits, -, _ and . only)"
}

@test "fork --no-remote only forks, in or outside a repository" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --no-remote
  assert_success
  assert_output_equals "gh repo fork github.com/dotcom/dotfiles --clone=false"
  run hub --noop fork --no-remote --org myorg --fork-name dots --default-branch-only
  assert_success
  assert_output_equals "gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg --fork-name dots --default-branch-only"
  run hub --noop fork --no-remote --remote-name x
  assert_failure
  assert_output_equals "Aborted: --no-remote and --remote-name cannot be used together."
  stub_gh 'repo fork github.com/dotcom/dotfiles --clone=false' 'Created fork mislav/dotfiles'
  run hub fork --no-remote
  assert_success
  assert_output_equals "Created fork mislav/dotfiles"
  [[ $(git remote) == origin ]]
  cd "$HUB_TEST_TMP"
  GH_REPO=dotcom/dotfiles run hub --noop fork --no-remote
  assert_success
  assert_output_equals "gh repo fork github.com/dotcom/dotfiles --clone=false"
  run hub --noop fork --no-remote
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
}

@test "fork checks the repository and the remote name before gh runs" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub fork --remote-name origin
  assert_failure
  assert_output_equals "Aborted: a remote named 'origin' already exists; pick another name with --remote-name NAME."
  git remote add mislav https://github.com/mislav/other.git
  run hub fork
  assert_failure
  assert_output_equals "Aborted: a remote named 'mislav' already exists; pick another name with --remote-name NAME."
  local name
  for name in 'bad name' --mirror=fetch -x 'a..b'; do
    run hub fork --remote-name "$name"
    assert_failure
    assert_output_equals "Aborted: not a remote name: '$name'"
  done
  cd "$HUB_TEST_TMP"
  GH_REPO=dotcom/dotfiles run hub fork
  assert_failure
  assert_output_equals "fatal: not a git repository (or any of the parent directories): .git"
  [[ $(gh_calls) != *"repo fork"* ]]
}

@test "fork gives the remote hub's protocol when gh's differs" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  fake_gh_fork
  git config hub.protocol ssh
  run hub --noop fork
  assert_success
  assert_output_equals $'env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mislav\ngit remote set-url mislav git@github.com:mislav/dotfiles.git'
  run hub fork --fork-name dots # the URL gh recorded names the fork
  assert_success
  assert_equals "$(remote_url mislav)" git@github.com:mislav/dots.git
  git remote remove mislav
  git config --unset hub.protocol
  git remote set-url origin git@github.com:dotcom/dotfiles.git # gh follows the parent's remote: ssh
  run hub --noop fork
  assert_success
  assert_output_equals $'env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mislav\ngit remote set-url mislav https://github.com/mislav/dotfiles.git'
  run hub fork
  assert_success
  assert_equals "$(remote_url mislav)" https://github.com/mislav/dotfiles.git
  git remote remove mislav
  stub_gh 'config get git_protocol -h github.com' 'ssh'
  run hub --noop fork
  assert_success
  assert_output_equals "env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mislav"
  run hub fork
  assert_success
  assert_equals "$(remote_url mislav)" git@github.com:mislav/dotfiles.git
}

@test "fork fails as gh fails, adding nothing" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  stub_gh 'repo fork *' '' 4
  run hub fork
  [[ $status -eq 4 ]]
  [[ $(git remote) == origin ]]
}

@test "fork refuses other options, empty values and extra arguments before running gh" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub fork --org=
  assert_failure
  assert_output_equals "Aborted: --org needs a value."
  run hub fork --remote-name
  assert_failure
  assert_output_equals "Aborted: --remote-name needs a value."
  run hub fork a b
  assert_failure
  assert_line_equals 0 "hub fork: too many arguments"
  assert_output_contains "Usage: hub fork"
  local opt
  for opt in --clone --yes --remote -x --default-branch-only=yes --no-remote=true; do
    run hub fork --org myorg "$opt"
    assert_failure
    assert_line_equals 0 "hub fork: unknown option: $opt"
  done
  assert_gh_not_called
}

@test "fork needs a GitHub project" {
  make_repo local-only
  run hub --noop fork
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
  assert_gh_not_called
}

@test "fork --help prints the manual" {
  run hub fork --help
  assert_success
  assert_output_contains "Usage: hub fork"
  assert_output_contains "--fork-name NAME"
  run hub fork -h
  assert_success
  assert_output_contains "Usage: hub fork"
}
