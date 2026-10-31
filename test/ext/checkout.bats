#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12
CHECKOUT="env GH_HOST=github.com gh pr checkout" # what runs for a github.com pull request

# git lists checkout's options, which hub reads to find the URL, only inside a repository.
setup() {
  hub_test_setup
  make_repo work
}

@test "checkout of a pull request URL hands off to gh pr checkout" {
  run hub --noop checkout "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR"
  assert_gh_not_called
  stub_gh "pr checkout $PR" ''
  run hub checkout "$PR"
  assert_success
  assert_gh_called "pr checkout $PR"
}

@test "checkout of a pull request URL into a named branch" {
  run hub --noop checkout "$PR" fix-build
  assert_success
  assert_output_equals "$CHECKOUT $PR -b fix-build"
  run hub --noop checkout -b fix-build "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR -b fix-build"
  run hub --noop checkout -bfix-build "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR -b fix-build"
  stub_gh "pr checkout $PR -b fix-build" ''
  run hub checkout "$PR" fix-build
  assert_success
  assert_gh_called "pr checkout $PR -b fix-build"
}

@test "the branch name is the last of -b BRANCH and the operand after the URL" {
  run hub --noop checkout -b one "$PR" two
  assert_success
  assert_output_equals "$CHECKOUT $PR -b two"
  run hub --noop checkout -b one -b two "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR -b two"
  run hub --noop checkout "$PR" one -b two
  assert_success
  assert_output_equals "$CHECKOUT $PR -b two"
}

@test "an empty branch name is an error, not an omitted name" {
  cd .. && make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub checkout -b '' "$PR"
  assert_failure
  assert_output_equals "Aborted: the branch name is empty"
  run hub checkout "$PR" ''
  assert_failure
  assert_output_equals "Aborted: the branch name is empty"
  run hub checkout -b chosen "$PR" ''
  assert_failure
  run hub checkout "$PR" -b
  assert_failure
  assert_output_contains "Usage: hub checkout"
  assert_gh_not_called
  [[ $(git symbolic-ref --short HEAD) == main ]]
  # an earlier empty value is overridden by a later one, as git does
  run hub --noop checkout -b '' -b chosen "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR -b chosen"
}

@test "checkout passes --detach and --recurse-submodules on to gh" {
  run hub --noop checkout --recurse-submodules "$PR" -d
  assert_success
  assert_output_equals "$CHECKOUT $PR --recurse-submodules --detach"
  run hub --noop checkout --detach "$PR"
  assert_output_equals "$CHECKOUT $PR --detach"
}

@test "checkout of any page of a pull request, or on an enterprise host, goes to gh" {
  run hub --noop checkout "$PR/files"
  assert_success
  assert_output_equals "$CHECKOUT $PR/files"
  git config --global hub.host ghe.example.com
  run hub --noop checkout https://ghe.example.com/team/app/pull/7
  assert_success
  assert_output_equals "env GH_HOST=ghe.example.com gh pr checkout https://ghe.example.com/team/app/pull/7"
}

@test "checkout -f with a pull request URL is refused, because gh's --force resets the branch" {
  run hub --noop checkout -f "$PR"
  assert_failure
  assert_output_contains "Aborted: -f can't be used with a pull request URL"
  assert_output_contains "gh pr checkout --force $PR"
  assert_gh_not_called
}

@test "checkout options gh doesn't share are refused with a pull request URL" {
  run hub --noop checkout -q "$PR"
  assert_failure
  assert_output_equals "Aborted: -q can't be used with a pull request URL (gh pr checkout accepts -b BRANCH, --detach and --recurse-submodules)"
  run hub --noop checkout --track "$PR"
  assert_failure
  run hub --noop checkout "$PR" -- README.md
  assert_failure
  run hub --noop checkout --orphan new "$PR"
  assert_failure
  assert_gh_not_called
}

@test "checkout of a pull request URL takes at most one branch name, after the URL" {
  run hub --noop checkout "$PR" one two
  assert_failure
  assert_output_equals "Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]"
  run hub --noop checkout main "$PR"
  assert_failure
  assert_output_equals "Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]"
  assert_gh_not_called
}

@test "checkout without a pull request URL is plain git checkout" {
  run hub --noop checkout main
  assert_success
  assert_output_equals "git checkout main"
  run hub --noop checkout -b feature origin/main
  assert_output_equals "git checkout -b feature origin/main"
  run hub --noop checkout
  assert_output_equals "git checkout"
  assert_gh_not_called
}

@test "checkout really runs git checkout" {
  cd .. && make_repo dotfiles
  git branch feature
  run hub checkout -q feature
  assert_success
  [[ $(git symbolic-ref --short HEAD) == feature ]]
  assert_gh_not_called
}

@test "the value of an option is never taken for the pull request URL" {
  cd .. && make_repo dotfiles
  printf 'committed\n' >file
  git add file && git commit -qm base
  mkdir -p 'https:/github.com/o/r/pull'
  printf 'file\n' >'https://github.com/o/r/pull/1'
  printf 'modified\n' >file
  run hub checkout --pathspec-from-file 'https://github.com/o/r/pull/1'
  assert_success
  [[ $(<file) == committed ]]
  printf 'modified\n' >file
  run hub checkout --pathspec-from-file='https://github.com/o/r/pull/1'
  assert_success
  [[ $(<file) == committed ]]
  printf 'modified\n' >file
  printf 'file\n' >list.txt
  run hub checkout --pathspec-from-file list.txt
  assert_success
  [[ $(<file) == committed ]]
  run hub --noop checkout -b "$PR"
  assert_output_equals "git checkout -b $PR"
  run hub --noop checkout -qB "$PR" main
  assert_output_equals "git checkout -qB $PR main"
  run hub --noop checkout --orphan "$PR"
  assert_output_equals "git checkout --orphan $PR"
  assert_gh_not_called
}

@test "checkout of other GitHub URLs, or pull requests on unknown hosts, is plain git" {
  run hub --noop checkout https://github.com/mislav/dotfiles/issues/12
  assert_output_equals "git checkout https://github.com/mislav/dotfiles/issues/12"
  run hub --noop checkout https://gitlab.com/mislav/dotfiles/pull/12
  assert_output_equals "git checkout https://gitlab.com/mislav/dotfiles/pull/12"
  assert_gh_not_called
}

@test "checkout treats a URL after -- as a path" {
  run hub --noop checkout main -- "$PR"
  assert_success
  assert_output_equals "git checkout main -- $PR"
}

@test "checkout tells gh the URL's host through GH_HOST, whatever host gh defaults to" {
  # a gh that records the host it was given, with its arguments
  mkdir -p "$HUB_TEST_TMP/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "${GH_HOST-unset}" "$*" >>"%s/gh.hosts"\n' "$HUB_TEST_TMP" >"$HUB_TEST_TMP/bin/gh"
  chmod +x "$HUB_TEST_TMP/bin/gh"
  PATH=$HUB_TEST_TMP/bin:$PATH run hub checkout "$PR"
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/gh.hosts")" "github.com|pr checkout $PR"
  # gh's own default host does not decide
  export GH_HOST=ghe.example.com
  : >"$HUB_TEST_TMP/gh.hosts"
  PATH=$HUB_TEST_TMP/bin:$PATH run hub checkout "$PR" fix-build
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/gh.hosts")" "github.com|pr checkout $PR -b fix-build"
  run hub --noop checkout "$PR"
  assert_output_equals "$CHECKOUT $PR"
  unset GH_HOST
  git config --global hub.host ghe.example.com
  : >"$HUB_TEST_TMP/gh.hosts"
  PATH=$HUB_TEST_TMP/bin:$PATH run hub checkout https://ghe.example.com/team/app/pull/7
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/gh.hosts")" "ghe.example.com|pr checkout https://ghe.example.com/team/app/pull/7"
}

@test "checkout reads abbreviated options and clusters as git does" {
  run hub --noop checkout --det "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR --detach"
  run hub --noop checkout --recurse "$PR"
  assert_output_equals "$CHECKOUT $PR --recurse-submodules"
  run hub --noop checkout -db fix-build "$PR"
  assert_output_equals "$CHECKOUT $PR --detach -b fix-build"
  run hub --noop checkout -dbfix-build "$PR"
  assert_output_equals "$CHECKOUT $PR --detach -b fix-build"
  # the value of an abbreviated option is never the URL
  printf 'file\n' >list.txt
  run hub --noop checkout --pathspec-from "$PR"
  assert_output_equals "git checkout --pathspec-from $PR"
  run hub --noop checkout --pathspec-from list.txt
  assert_output_equals "git checkout --pathspec-from list.txt"
  # an option git would refuse, ambiguous here, leaves the command line to git
  run hub --noop checkout --no "$PR"
  assert_output_equals "git checkout --no $PR"
  run hub checkout --no "$PR"
  assert_failure
  assert_output_contains "ambiguous option"
  assert_gh_not_called
}

@test "checkout --help prints the manual, while -h is left to git" {
  run hub checkout --help
  assert_success
  assert_output_contains "Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]"
  run hub --noop checkout -h
  assert_output_equals "git checkout -h"
}

@test "checkout keeps git's reading of --detach and --recurse-submodules: negations and git's boolean values" {
  local v
  for v in yes true on 1 YES True 2; do
    run hub --noop checkout "--recurse-submodules=$v" "$PR"
    assert_success
    assert_output_equals "$CHECKOUT $PR --recurse-submodules"
  done
  for v in no false off 0 NO False -0 ''; do
    run hub --noop checkout "--recurse-submodules=$v" "$PR"
    assert_success
    assert_output_equals "$CHECKOUT $PR"
  done
  run hub --noop checkout --recurse=no "$PR" -d
  assert_success
  assert_output_equals "$CHECKOUT $PR --detach"
  # the last of an option and its negation counts, as in git
  run hub --noop checkout --recurse-submodules --no-recurse-submodules "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR"
  run hub --noop checkout --no-recurse-submodules "$PR" --recurse-submodules
  assert_success
  assert_output_equals "$CHECKOUT $PR --recurse-submodules"
  run hub --noop checkout -d --no-detach "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR"
  run hub --noop checkout --no-detach -db fix "$PR"
  assert_success
  assert_output_equals "$CHECKOUT $PR --detach -b fix"
  # a value git refuses leaves the command line to git, which refuses it
  run hub --noop checkout --recurse-submodules=banana "$PR"
  assert_success
  assert_output_equals "git checkout --recurse-submodules=banana $PR"
  run hub checkout --recurse-submodules=banana "$PR"
  assert_failure
  assert_output_contains "bad recurse-submodules argument: banana"
  run hub --noop checkout --detach=oops "$PR"
  assert_success
  assert_output_equals "git checkout --detach=oops $PR"
  run hub checkout --detach=oops "$PR"
  assert_failure
  assert_output_contains "takes no value"
  run hub checkout --no-recurse-submodules=no "$PR"
  assert_failure
  assert_output_contains "takes no value"
  assert_gh_not_called
}
