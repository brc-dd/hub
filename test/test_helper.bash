# shellcheck shell=bash
# shellcheck disable=SC2154  # status, output and lines are set by bats' `run`
# Shared setup for hub's bats tests: `load test_helper` (or ../test_helper).
# Each test runs in a throwaway directory with its own HOME and git config, and
# gh is test/stubs/gh, which logs every call and replays the responses
# registered with stub_gh. Fixtures use real git; hub's side effects are
# observed with --noop.

HUB_TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
HUB_BIN=$HUB_TEST_ROOT/bin/hub
export HUB_TEST_ROOT HUB_BIN

setup() { hub_test_setup; } # a test file with its own setup calls hub_test_setup

hub_test_setup() {
  HUB_TEST_TMP=$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/hub-test.XXXXXX")
  export HUB_TEST_TMP
  export HOME=$HUB_TEST_TMP/home
  mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$HUB_TEST_TMP/gitconfig
  export XDG_CONFIG_HOME=$HOME/.config GH_CONFIG_DIR=$HUB_TEST_TMP/gh
  export PATH=$HUB_TEST_ROOT/test/stubs:$PATH
  export HUB_TEST_LOG=$HUB_TEST_TMP/gh.log HUB_TEST_GH_STUBS=$HUB_TEST_TMP/gh.stubs
  : >"$HUB_TEST_LOG"
  : >"$HUB_TEST_GH_STUBS"
  unset GH_HOST GITHUB_HOST GH_REPO GH_TOKEN GITHUB_TOKEN HUB_VERBOSE HUB_NOOP BROWSER GIT_CONFIG_COUNT
  export NO_COLOR=1 GH_NO_UPDATE_NOTIFIER=1 GH_PROMPT_DISABLED=1
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
assert_line_equals() { [[ ${lines[$1]} == "$2" ]] || {
  printf 'expected line %s to be:\n%s\nactual:\n%s\n' "$1" "$2" "${lines[$1]-<missing>}"
  return 1
}; }

# serve_github OWNER/REPO... : local bare repositories that stand in for github.com over file://.
serve_github() {
  local repo dir tree
  git config --global url."$HUB_TEST_TMP/srv/".insteadOf https://github.com/
  export GIT_ALLOW_PROTOCOL=file
  for repo in "$@"; do
    dir=$HUB_TEST_TMP/srv/$repo.git
    git init -q --bare "$dir"
    tree=$(git -C "$dir" hash-object -t tree -w --stdin </dev/null)
    git -C "$dir" update-ref refs/heads/main "$(git -C "$dir" commit-tree -m "initial commit" "$tree")"
  done
}

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

# stub_gh_file 'ARGS GLOB' FILE : like stub_gh, answering with the contents of FILE.
stub_gh_file() {
  local body
  body=$(<"$2")
  body=${body//\\/\\\\}
  stub_gh "$1" "${body//$'\n'/\\n}"
}
