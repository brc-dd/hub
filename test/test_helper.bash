# shellcheck shell=bash
# shellcheck disable=SC2154  # status, output and lines are set by bats' `run`
# Shared setup for hub's bats tests: `load test_helper` (or ../test_helper).
# Each test runs in a throwaway directory with its own HOME, git and gh configuration, and
# nothing inherited from the caller's environment that could point git at another repository.
# gh is test/stubs/gh, which logs every call and replays the responses registered with stub_gh.
# Fixtures use real git; tests assert effects (refs, configuration, files) wherever the effect is
# local, and compare --noop output only for what cannot happen locally (browser URLs, gh calls).

# `run !` and `run -N` need bats 1.5; the helper is also sourced by plain bash in a harness test.
if declare -F bats_require_minimum_version >/dev/null; then bats_require_minimum_version 1.5.0; fi

HUB_TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
HUB_BIN=$HUB_TEST_ROOT/bin/hub
export HUB_TEST_ROOT HUB_BIN

setup() { hub_test_setup; } # a test file with its own setup calls hub_test_setup

hub_test_setup() {
  HUB_TEST_TMP=$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/hub-test.XXXXXX")
  export HUB_TEST_TMP
  # Nothing from the caller's environment may reach git, gh or hub: a developer's GIT_DIR,
  # GIT_INDEX_FILE or GIT_CONFIG_PARAMETERS would otherwise make the fixtures touch their repository.
  unset "${!GIT_@}" "${!GH_@}" "${!GITHUB_@}" CDPATH BROWSER
  unset HUB_NOOP HUB_VERBOSE HUB_PROTOCOL HUB_REEXEC HUB_KEEP_GIT_DIR HUB_INVOKED_PWD HUB_GIT_GLOBALS HUB_ROOT HUB_LIB HUB_VERSION HUB_GH_HOSTS
  export HOME=$HUB_TEST_TMP/home
  mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$HUB_TEST_TMP/gitconfig GIT_TERMINAL_PROMPT=0
  export XDG_CONFIG_HOME=$HOME/.config GH_CONFIG_DIR=$HUB_TEST_TMP/gh
  export PATH=$HUB_TEST_ROOT/test/stubs:$PATH
  export HUB_TEST_LOG=$HUB_TEST_TMP/gh.log HUB_TEST_GH_STUBS=$HUB_TEST_TMP/gh.stubs
  : >"$HUB_TEST_LOG"
  : >"$HUB_TEST_GH_STUBS"
  export NO_COLOR=1 GH_NO_UPDATE_NOTIFIER=1 GH_PROMPT_DISABLED=1
  # Served repositories (serve_github) are reached through stubs: test/stubs/ssh from PATH, and
  # test/stubs/git-remote-https through GIT_EXEC_PATH, which git searches before PATH for its own
  # helpers; everything else in that directory links to the real git-core.
  export HUB_TEST_SRV=$HUB_TEST_TMP/srv
  mkdir -p "$HUB_TEST_TMP/git-core"
  ln -s "$(git --exec-path)"/* "$HUB_TEST_TMP/git-core/"
  rm -f "$HUB_TEST_TMP/git-core/git-remote-https" "$HUB_TEST_TMP/git-core/git-remote-http"
  ln -s "$HUB_TEST_ROOT/test/stubs/git-remote-https" "$HUB_TEST_TMP/git-core/git-remote-https"
  ln -s "$HUB_TEST_ROOT/test/stubs/git-remote-https" "$HUB_TEST_TMP/git-core/git-remote-http"
  export GIT_EXEC_PATH=$HUB_TEST_TMP/git-core
  git config --global user.name "hub tests"
  git config --global user.email "hub@example.test"
  git config --global init.defaultBranch main
  # gh's cached login and protocol; tests override them with stub_gh.
  stub_gh 'config get user -h github.com' 'mislav'
  stub_gh 'config get git_protocol -h github.com' 'https'
  cd "$HUB_TEST_TMP" || return 1
}

teardown() {
  cd / && rm -rf "$HUB_TEST_TMP"
}

hub() { "$HUB_BIN" "$@"; }

# make_repo NAME [REMOTE=URL ...] : a repository with one commit and these remotes; cd into it.
make_repo() {
  local name=$1 spec
  shift
  git init -q -b main "$name" && cd "$name" || return 1
  git commit -q --allow-empty -m "initial commit"
  for spec in "$@"; do
    git remote add "${spec%%=*}" "${spec#*=}"
  done
}

# set_remote_head REMOTE BRANCH : make BRANCH, at HEAD, REMOTE's default branch.
set_remote_head() {
  git update-ref "refs/remotes/$1/$2" HEAD
  git symbolic-ref "refs/remotes/$1/HEAD" "refs/remotes/$1/$2"
}

# stub_gh 'ARGS GLOB' 'STDOUT' [EXIT] : answer gh calls whose space-joined arguments match the
# bash pattern ARGS GLOB; STDOUT takes printf %b escapes. Later registrations win.
stub_gh() {
  printf '%s\x1f%s\x1f%s\n' "$1" "$2" "${3:-0}" >>"$HUB_TEST_GH_STUBS"
}

# stub_gh_file 'ARGS GLOB' FILE : like stub_gh, answering with the contents of FILE.
stub_gh_file() {
  local body
  body=$(<"$2")
  body=${body//\\/\\\\}
  stub_gh "$1" "${body//$'\n'/\\n}"
}

gh_calls() { cat "$HUB_TEST_LOG"; }

assert_gh_called() {
  local line
  while IFS= read -r line; do
    # shellcheck disable=SC2053
    [[ $line == gh\ $1 ]] && return 0
  done <"$HUB_TEST_LOG"
  printf 'expected a gh call matching: gh %s\ncalls made:\n%s\n' "$1" "$(gh_calls)"
  return 1
}

assert_gh_not_called() {
  [[ ! -s $HUB_TEST_LOG ]] || {
    printf 'expected no gh calls, got:\n%s\n' "$(gh_calls)"
    return 1
  }
}

assert_success() { [[ $status -eq 0 ]] || {
  printf 'expected exit 0, got %s\noutput:\n%s\n' "$status" "$output"
  return 1
}; }
assert_failure() { [[ $status -ne 0 ]] || {
  printf 'expected a non-zero exit\noutput:\n%s\n' "$output"
  return 1
}; }
assert_output_equals() { [[ $output == "$1" ]] || {
  printf 'expected output:\n%s\nactual output:\n%s\n' "$1" "$output"
  return 1
}; }
assert_output_contains() { [[ $output == *"$1"* ]] || {
  printf 'expected output to contain:\n%s\nactual output:\n%s\n' "$1" "$output"
  return 1
}; }
assert_output_lacks() { [[ $output != *"$1"* ]] || {
  printf 'expected output not to contain:\n%s\nactual output:\n%s\n' "$1" "$output"
  return 1
}; }
assert_line_equals() { [[ ${lines[$1]} == "$2" ]] || {
  printf 'expected line %s to be:\n%s\nactual:\n%s\n' "$1" "$2" "${lines[$1]-<missing>}"
  return 1
}; }
assert_equals() { [[ $1 == "$2" ]] || {
  printf 'expected:\n%s\nactual:\n%s\n' "$2" "$1"
  return 1
}; }

# ---------------------------------------------------------------------------
# A local github.com: bare repositories reached through the ssh and https stubs
# ---------------------------------------------------------------------------
# serve_github [HOST/]OWNER/REPO... : bare repositories, each with one commit on main, that stand
# in for github.com (or HOST). git reaches them through the ssh and git-remote-https stubs, so the
# remote URLs stay the ones a user would have (https://github.com/OWNER/REPO.git,
# git@github.com:OWNER/REPO.git, ssh://git@github.com/OWNER/REPO.git) and the effects land here.
# The commit is the same in every served repository (a fixed date, not the clock's second), so
# that they share history as a fork and its parent do.
serve_github() {
  local spec dir tree
  for spec; do
    dir=$(server_dir "$spec")
    mkdir -p "$dir" && git init -q --bare "$dir" || return 1
    tree=$(git -C "$dir" hash-object -t tree -w --stdin </dev/null)
    git -C "$dir" update-ref refs/heads/main "$(GIT_AUTHOR_DATE=2020-01-01T00:00:00Z GIT_COMMITTER_DATE=2020-01-01T00:00:00Z git -C "$dir" commit-tree -m "initial commit" "$tree")"
    git -C "$dir" symbolic-ref HEAD refs/heads/main
  done
}

# server_dir [HOST/]OWNER/REPO : the served bare repository's path.
server_dir() {
  local spec=$1
  [[ $spec == */*/* ]] || spec=github.com/$spec
  printf '%s/%s.git\n' "$HUB_TEST_SRV" "$spec"
}

# server_ref [HOST/]OWNER/REPO REF : the commit REF points at on the server (empty if none).
server_ref() { git -C "$(server_dir "$1")" rev-parse --verify --quiet "$2^{commit}" 2>/dev/null; }

# server_branches [HOST/]OWNER/REPO : the server's branch names, one per line.
server_branches() { git -C "$(server_dir "$1")" for-each-ref --format='%(refname:short)' refs/heads; }

# clone_served [HOST/]OWNER/REPO [DIR] : clone a served repository over HTTPS, as a user would,
# and cd into it; origin is https://HOST/OWNER/REPO.git.
clone_served() {
  local spec=$1 dir=${2:-${1##*/}}
  [[ $spec == */*/* ]] || spec=github.com/$spec
  git clone -q "https://$spec.git" "$dir" && cd "$dir" || return 1
}

# remote_url NAME [push] : the configured URL of a remote (with push, its push URL), as git stores
# it (empty if none).
remote_url() {
  if [[ ${2-} == push ]]; then
    git config --get "remote.$1.pushurl" 2>/dev/null && return 0
  fi
  git config --get "remote.$1.url" 2>/dev/null
}

# commit_on BRANCH MESSAGE : an empty commit on BRANCH, without checking it out.
commit_on() {
  local tip
  tip=$(git rev-parse "refs/heads/$1")
  git update-ref "refs/heads/$1" "$(git commit-tree -p "$tip" -m "$2" "$tip^{tree}")"
}

# tip BRANCH : the commit a local branch points at (empty if none).
tip() { git rev-parse --verify -q "refs/heads/$1"; }

# shim_git 'ARGS GLOB' COMMAND : a git that, the first time it is run with arguments matching the
# glob, first runs COMMAND (a shell string, with the real git in PATH) and then goes on as the real
# git. hub runs one git at a time, so this slips another process in between two of them, for race
# tests. The shim goes first in SHIM_PATH (run hub with PATH=$SHIM_PATH) and into this test's exec
# path directory, which git puts first in the PATH of everything it runs.
shim_git() {
  local dir=$HUB_TEST_TMP/shim real
  real=$(command -v git)
  mkdir -p "$dir"
  printf '%s\n' "$1" >"$dir/pattern"
  printf '%s\n' "$2" >"$dir/action"
  cat >"$dir/git" <<EOF
#!/usr/bin/env bash
dir='$dir'
if [[ ! -e \$dir/done && \$* == \$(<"\$dir/pattern") ]]; then
  : >"\$dir/done"
  PATH='${real%/*}':\$PATH bash -c "\$(<"\$dir/action")" >"\$dir/action.log" 2>&1
fi
exec '$real' "\$@"
EOF
  chmod +x "$dir/git"
  ln -sf "$dir/git" "$HUB_TEST_TMP/git-core/git"
  # shellcheck disable=SC2034  # read by the tests that run hub with PATH=$SHIM_PATH
  SHIM_PATH=$dir:$PATH
}

# ---------------------------------------------------------------------------
# Temporary files made by am/apply
# ---------------------------------------------------------------------------
use_tmpdir() {
  export TMPDIR=$HUB_TEST_TMP/tmp
  mkdir -p "$TMPDIR"
}

# untmp : in $output and $lines, replace the temporary directory hub made with TMP.
untmp() {
  local i
  output=${output//"$TMPDIR"\/hub-am.??????/TMP}
  output=${output//"$TMPDIR"\/hub-apply.??????/TMP}
  for i in "${!lines[@]}"; do
    lines[i]=${lines[i]//"$TMPDIR"\/hub-am.??????/TMP}
    lines[i]=${lines[i]//"$TMPDIR"\/hub-apply.??????/TMP}
  done
}

assert_tmp_cleaned() {
  [[ -z $(ls -A "$TMPDIR") ]] || {
    printf 'temporary files left behind:\n%s\n' "$(ls -A "$TMPDIR")"
    return 1
  }
}
