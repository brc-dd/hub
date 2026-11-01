# shellcheck shell=bash
# shellcheck disable=SC2154  # status, output and lines are set by bats' run
# Summary: shared setup, fixtures and assertions of hub's bats tests.
# Usage: load test_helper
#
# Every test runs in its own directory with its own HOME, git and gh configuration, and nothing
# of the caller's environment. gh is test/stubs/gh; github.com and other hosts are local bare
# repositories under $HUB_TEST_SRV, reached through the ssh and git-remote-https stubs.

# The harness self-test also sources this file from plain bash.
if declare -F bats_require_minimum_version >/dev/null; then
  bats_require_minimum_version 1.5.0
fi

HUB_TEST_ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd -P)
HUB_BIN=$HUB_TEST_ROOT/bin/hub
export HUB_TEST_ROOT HUB_BIN

setup_file() { hub_test_exec_path; }
setup() { hub_test_setup; }
hub() { "$HUB_BIN" "$@"; }

# hub_test_exec_path : builds $BATS_FILE_TMPDIR/git-core, git's helpers with https and http stubbed.
hub_test_exec_path() {
  local dir=$BATS_FILE_TMPDIR/git-core real
  [[ ! -d $dir ]] || return 0
  real=$(env -u GIT_EXEC_PATH git --exec-path) || return 1
  mkdir -p "$dir" && ln -s "$real"/* "$dir/" || return 1
  # git looks for its helpers in GIT_EXEC_PATH before PATH; http:// URLs use git-remote-http.
  ln -sf "$HUB_TEST_ROOT/test/stubs/git-remote-https" "$dir/git-remote-https"
  ln -sf "$HUB_TEST_ROOT/test/stubs/git-remote-https" "$dir/git-remote-http"
}

hub_test_setup() {
  local root=$HUB_TEST_ROOT tmp
  tmp=$(cd "$BATS_TEST_TMPDIR" && pwd -P) || return 1
  # A caller's GIT_DIR, GIT_INDEX_FILE or GIT_CONFIG_PARAMETERS would point the fixtures at the
  # caller's repository, CDPATH would move their cd, BROWSER would open a real browser, and every
  # bash started (hub, the stubs) would source BASH_ENV, and sh ENV, again.
  unset "${!GIT_@}" "${!GH_@}" "${!GITHUB_@}" "${!HUB_@}" CDPATH BROWSER BASH_ENV ENV
  export HUB_TEST_ROOT=$root HUB_BIN=$root/bin/hub HUB_TEST_TMP=$tmp
  export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$tmp/gitconfig GIT_TERMINAL_PROMPT=0
  export GH_CONFIG_DIR=$tmp/gh NO_COLOR=1 GH_NO_UPDATE_NOTIFIER=1 GH_PROMPT_DISABLED=1
  export GH_BROWSER=$root/test/stubs/browser PATH=$root/test/stubs:$PATH
  export HUB_TEST_SRV=$tmp/srv HUB_TEST_GH_LOG=$tmp/gh.log HUB_TEST_GH_STUBS=$tmp/gh.stubs
  hub_test_exec_path || return 1
  export GIT_EXEC_PATH=$BATS_FILE_TMPDIR/git-core
  mkdir -p "$HOME" && : >"$HUB_TEST_GH_LOG" && : >"$HUB_TEST_GH_STUBS" || return 1
  git config --global user.name 'hub tests'
  git config --global user.email hub@example.test
  git config --global init.defaultBranch main
  stub_gh 'config get user -h github.com' mislav
  stub_gh 'config get git_protocol -h github.com' https
  cd "$tmp" || return 1
}

# make_repo NAME [REMOTE=URL...] : a repository with one commit and these remotes; cd into it.
make_repo() {
  local spec
  git init -q -b main "$1" && cd "$1" || return 1
  shift
  git commit -q --allow-empty -m 'initial commit' || return 1
  for spec; do
    git remote add "${spec%%=*}" "${spec#*=}" || return 1
  done
}

# serve_github [HOST/]OWNER/REPO... : bare repositories served as HOST (default github.com).
serve_github() {
  local spec dir tree commit
  for spec; do
    dir=$(server_dir "$spec")
    git init -q --bare "$dir" || return 1
    git -C "$dir" config uploadpack.allowAnySHA1InWant true
    tree=$(git -C "$dir" hash-object -t tree -w --stdin </dev/null) || return 1
    # A fixed date gives every served repository the same root commit, as a fork shares history.
    commit=$(GIT_AUTHOR_DATE=2020-01-01T00:00:00Z GIT_COMMITTER_DATE=2020-01-01T00:00:00Z \
      git -C "$dir" commit-tree -m 'initial commit' "$tree") || return 1
    git -C "$dir" update-ref refs/heads/main "$commit" || return 1
    git -C "$dir" symbolic-ref HEAD refs/heads/main || return 1
  done
}

# server_dir [HOST/]OWNER/REPO : the path of that served repository.
server_dir() {
  local spec=$1
  [[ $spec == */*/* ]] || spec=github.com/$spec
  printf '%s\n' "$HUB_TEST_SRV/$spec.git"
}

# server_ref [HOST/]OWNER/REPO REF : the commit REF names on the server; empty when none.
server_ref() {
  git -C "$(server_dir "$1")" rev-parse --verify --quiet "$2^{commit}" 2>/dev/null
}

# server_branches [HOST/]OWNER/REPO : the server's branch names, one per line.
server_branches() {
  git -C "$(server_dir "$1")" for-each-ref --format='%(refname:short)' refs/heads
}

# clone_served [HOST/]OWNER/REPO [DIR] : clone it over https and cd in; origin keeps the URL.
clone_served() {
  local spec=$1 dir=${2:-${1##*/}}
  [[ $spec == */*/* ]] || spec=github.com/$spec
  git clone -q "https://$spec.git" "$dir" && cd "$dir" || return 1
}

# set_remote_head REMOTE BRANCH : REMOTE/BRANCH at HEAD, and REMOTE/HEAD pointing at it.
set_remote_head() {
  git update-ref "refs/remotes/$1/$2" HEAD || return 1
  git symbolic-ref "refs/remotes/$1/HEAD" "refs/remotes/$1/$2"
}

# commit_on BRANCH MSG : an empty commit on BRANCH, without checking it out.
commit_on() {
  local commit
  commit=$(git commit-tree -p "refs/heads/$1" -m "$2" "refs/heads/$1^{tree}") || return 1
  git update-ref "refs/heads/$1" "$commit"
}

# tip BRANCH : the commit of a local branch; empty when none.
tip() { git rev-parse --verify --quiet "refs/heads/$1"; }

# stub_gh 'ARGS GLOB' 'STDOUT' [STATUS] : answer gh calls whose space-joined arguments match the
# glob with STDOUT (printf %b escapes) and STATUS. Later registrations win.
stub_gh() {
  printf '%s\x1f%s\x1f%s\n' "$1" "${2//$'\n'/\\n}" "${3:-0}" >>"$HUB_TEST_GH_STUBS"
}

# stub_gh_file 'ARGS GLOB' FILE : stub_gh answering with FILE, verbatim when it ends in a newline.
stub_gh_file() {
  local body
  body=$(cat "$2" && printf x) || return 1
  # The stub prints a newline after the answer.
  body=${body%x} body=${body%$'\n'}
  stub_gh "$1" "${body//\\/\\\\}"
}

# gh_calls : the gh calls made so far, one per line, GH_REPO=VALUE in front when it was set.
gh_calls() { cat "$HUB_TEST_GH_LOG"; }

# assert_gh_called GLOB : a call matched "gh GLOB", or GLOB as a whole line (GH_REPO=... gh ...).
assert_gh_called() {
  local line
  while IFS= read -r line; do
    # shellcheck disable=SC2053  # the argument is a glob
    if [[ $line == "gh "$1 || $line == $1 ]]; then return 0; fi
  done <"$HUB_TEST_GH_LOG"
  printf 'expected a gh call matching: gh %s\ncalls made:\n%s\n' "$1" "$(gh_calls)"
  return 1
}

assert_gh_not_called() {
  [[ ! -s $HUB_TEST_GH_LOG ]] || {
    printf 'expected no gh calls, got:\n%s\n' "$(gh_calls)"
    return 1
  }
}

assert_success() { assert_status 0; }

assert_failure() {
  ((status != 0)) || {
    printf 'expected a non-zero exit status, got 0\noutput:\n%s\n' "$output"
    return 1
  }
}

assert_status() {
  ((status == $1)) || {
    printf 'expected exit status %s, got %s\noutput:\n%s\n' "$1" "$status" "$output"
    return 1
  }
}

assert_output_equals() {
  [[ $output == "$1" ]] || {
    printf 'expected output:\n%s\nactual output:\n%s\n' "$1" "$output"
    return 1
  }
}

assert_output_contains() {
  [[ $output == *"$1"* ]] || {
    printf 'expected output to contain:\n%s\nactual output:\n%s\n' "$1" "$output"
    return 1
  }
}

assert_output_lacks() {
  [[ $output != *"$1"* ]] || {
    printf 'expected output not to contain:\n%s\nactual output:\n%s\n' "$1" "$output"
    return 1
  }
}

assert_line_equals() {
  [[ ${lines[$1]-} == "$2" && -n ${lines[$1]+set} ]] || {
    printf 'expected line %s:\n%s\nactual line:\n%s\n' "$1" "$2" "${lines[$1]-<missing>}"
    return 1
  }
}

assert_equals() {
  [[ $1 == "$2" ]] || {
    printf 'expected:\n%s\nactual:\n%s\n' "$2" "$1"
    return 1
  }
}
