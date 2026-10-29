# shellcheck shell=bash
# shellcheck disable=SC2154  # status, output and lines are set by bats' `run`
# Shared setup for hub's bats tests. Load from a .bats file with:
#   load test_helper          (tests in test/)
#   load ../test_helper       (tests in test/cmd/ or test/ext/)
#
# Every test runs in a throwaway directory with an isolated HOME and git
# config, and with `gh` replaced by test/stubs/gh, which records every call
# and replays responses registered with stub_gh. Real git is used for
# repository setup; hub's own git/gh side effects are observed with --noop.

HUB_TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
HUB_BIN=$HUB_TEST_ROOT/bin/hub
export HUB_TEST_ROOT HUB_BIN

setup() {
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
  # Default identity and protocol, as the gh stub reports them. Tests may override with stub_gh.
  stub_gh 'config get user -h github.com' 'mislav'
  stub_gh 'config get git_protocol -h github.com' 'https'
  cd "$HUB_TEST_TMP" || return 1
}

teardown() {
  cd / && rm -rf "$HUB_TEST_TMP"
}

# hub ARGS... : run the hub under test (use with bats' `run`).
hub() { "$HUB_BIN" "$@"; }

# make_repo NAME [REMOTE=URL ...] : create a repo with one commit and the given remotes, and cd into it.
make_repo() {
  local name=$1 spec
  shift
  git init -q -b main "$name" && cd "$name" || return 1
  git commit -q --allow-empty -m "initial commit"
  for spec in "$@"; do
    git remote add "${spec%%=*}" "${spec#*=}"
  done
}

# set_remote_head REMOTE BRANCH : pretend REMOTE's default branch is BRANCH (refs/remotes/REMOTE/HEAD), pointing at HEAD.
set_remote_head() {
  git update-ref "refs/remotes/$1/$2" HEAD
  git symbolic-ref "refs/remotes/$1/HEAD" "refs/remotes/$1/$2"
}

# stub_gh 'ARGS GLOB' 'STDOUT' [EXIT] : register a response for the gh stub. Later registrations win.
# ARGS GLOB is a bash pattern matched against the space-joined arguments, e.g. 'api repos/*/dotfiles *'.
# STDOUT may use printf %b escapes such as \n.
stub_gh() {
  printf '%s\x1f%s\x1f%s\n' "$1" "$2" "${3:-0}" >>"$HUB_TEST_GH_STUBS"
}

# gh_calls : every gh invocation so far, one per line, as "gh ARGS".
gh_calls() { cat "$HUB_TEST_LOG"; }

# assert_gh_called 'ARGS GLOB' : a gh call matching the pattern happened.
assert_gh_called() {
  local line
  while IFS= read -r line; do
    # shellcheck disable=SC2053
    [[ $line == gh\ $1 ]] && return 0
  done <"$HUB_TEST_LOG"
  printf 'expected a gh call matching: gh %s\ncalls made:\n%s\n' "$1" "$(gh_calls)"
  return 1
}

# assert_gh_not_called : no gh call happened at all.
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
