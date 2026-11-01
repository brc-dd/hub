#!/usr/bin/env bats
# hub apply: GitHub URLs downloaded through gh and applied with git apply.

load test_helper

setup() {
  hub_test_setup
  export TMPDIR=$HUB_TEST_TMP/tmp
  mkdir "$TMPDIR"
  stub_gh 'api --help' '  --allow-escape-sequences   Keep escape sequences in the output'
  make_repo work
  printf 'one\n' >a.txt
  printf 'one\n' >b.txt
  git add a.txt b.txt
  git commit -q -m 'add a and b'
}

# change FILE TEXT NAME : the diff (NAME.diff) and the patch (NAME.patch) of setting FILE to TEXT.
change() {
  printf '%s\n' "$2" >"$1"
  git diff >"$HUB_TEST_TMP/$3.diff"
  git commit -q -a -m "set $1 to $2"
  git format-patch -q --stdout HEAD~ >"$HUB_TEST_TMP/$3.patch"
  git reset -q --hard HEAD~
}

# assert_downloaded ENDPOINT FORMAT [FLAG] : gh api downloaded ENDPOINT from github.com as FORMAT.
assert_downloaded() {
  assert_gh_called "api --hostname github.com $1 -H Accept: application/vnd.github.$2${3:+ $3}"
}

@test "hub apply PULL-URL applies the pull request's diff to the work tree without a commit" {
  change a.txt two pr
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  local head
  head=$(tip main)
  run hub apply https://github.com/octo/proj/pull/7
  assert_success
  assert_equals "$(<a.txt)" two
  assert_equals "$(tip main)" "$head"
  assert_equals "$(git diff --cached --name-only)" ''
  assert_downloaded repos/octo/proj/pulls/7 diff --allow-escape-sequences
  assert_tmp_empty
}

@test "hub apply takes any page of a pull request" {
  change a.txt two pr
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  run hub apply 'https://github.com/octo/proj/pull/7/files?w=1#diff'
  assert_success
  assert_equals "$(<a.txt)" two
  git checkout -q a.txt
  run hub apply https://github.com/octo/proj/pull/7/commits/
  assert_success
  assert_equals "$(<a.txt)" two
}

@test "hub apply downloads a URL ending in .patch or .diff as one diff" {
  change a.txt two pr
  change b.txt two c
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  stub_patch repos/octo/proj/commits/1a2b3c4 diff "$HUB_TEST_TMP/c.diff"
  local head
  head=$(tip main)
  run hub apply https://github.com/octo/proj/pull/7.patch \
    https://github.com/octo/proj/commit/1a2b3c4.diff
  assert_success
  assert_equals "$(<a.txt)" two
  assert_equals "$(<b.txt)" two
  assert_equals "$(tip main)" "$head"
  assert_equals "$(grep -c 'vnd.github.patch' "$HUB_TEST_GH_LOG")" 0
}

@test "hub apply removes a file that a pull request adds in one commit and deletes in another" {
  printf 'new\n' >c.txt
  git add c.txt
  git commit -q -m 'add c'
  git rm -q c.txt
  git commit -q -m 'remove c'
  printf 'two\n' >a.txt
  git commit -q -a -m 'set a.txt to two'
  git diff HEAD~3 >"$HUB_TEST_TMP/pr.diff"
  git reset -q --hard HEAD~3
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  run hub apply https://github.com/octo/proj/pull/7.patch
  assert_success
  assert_equals "$(<a.txt)" two
  assert_equals "$(ls)" $'a.txt\nb.txt'
}

@test "hub apply downloads commit, pull request commit and compare URLs from their endpoints" {
  change a.txt two c
  change b.txt two pc
  stub_patch repos/octo/proj/commits/1a2b3c4 diff "$HUB_TEST_TMP/c.diff"
  stub_patch repos/octo/proj/commits/abcdef0 diff "$HUB_TEST_TMP/pc.diff"
  run hub apply https://github.com/octo/proj/commit/1a2b3c4 \
    https://github.com/octo/proj/pull/7/commits/abcdef0
  assert_success
  assert_equals "$(<a.txt)" two
  assert_equals "$(<b.txt)" two
  git checkout -q a.txt b.txt
  stub_patch 'repos/octo/proj/compare/v1.0...fork:feature' diff "$HUB_TEST_TMP/c.diff"
  run hub apply 'https://github.com/octo/proj/compare/v1.0...fork:feature'
  assert_success
  assert_equals "$(<a.txt)" two
  assert_gh_called 'api --hostname github.com repos/octo/proj/compare/v1.0...fork:feature -H *'
}

@test "hub apply keeps the other words in place and asks gh api --help once" {
  change a.txt two local
  printf 'two\n' >a.txt
  git commit -q -a -m 'set a.txt to two'
  change a.txt three pr
  git reset -q --hard HEAD~
  change b.txt two c
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  stub_patch repos/octo/proj/commits/1a2b3c4 diff "$HUB_TEST_TMP/c.diff"
  run hub apply --index "$HUB_TEST_TMP/local.diff" https://github.com/octo/proj/pull/7 \
    https://github.com/octo/proj/commit/1a2b3c4
  assert_success
  assert_equals "$(<a.txt)" three
  assert_equals "$(git diff --cached --name-only)" $'a.txt\nb.txt'
  assert_equals "$(grep -c -- 'api --help' "$HUB_TEST_GH_LOG")" 1
  git reset -q --hard
  run hub apply https://github.com/octo/proj/pull/7 "$HUB_TEST_TMP/local.diff"
  assert_failure
  assert_equals "$(git status --porcelain)" ''
  assert_tmp_empty
}

@test "hub apply makes its temporary directory under TMPDIR" {
  change a.txt two pr
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  TMPDIR=$HUB_TEST_TMP/missing run hub apply https://github.com/octo/proj/pull/7
  assert_status 1
  assert_equals "$(<a.txt)" one
  assert_gh_not_called
}

@test "hub apply leaves out --allow-escape-sequences when gh does not know it" {
  stub_gh 'api --help' 'Usage: gh api <endpoint> [flags]'
  change a.txt two pr
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  run hub apply https://github.com/octo/proj/pull/7
  assert_success
  assert_downloaded repos/octo/proj/pulls/7 diff
}

@test "hub apply asks gh on the URL's host" {
  change a.txt two pr
  export GH_HOST=ghe.example.test
  stub_gh_file 'api --hostname ghe.example.test repos/octo/proj/pulls/3 -H *' \
    "$HUB_TEST_TMP/pr.diff"
  run hub apply https://ghe.example.test/octo/proj/pull/3
  assert_success
  assert_equals "$(<a.txt)" two
  git checkout -q a.txt
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  run hub apply https://github.com/octo/proj/pull/7
  assert_success
  assert_gh_called 'api --hostname github.com repos/octo/proj/pulls/7 -H *'
}

@test "hub apply stops before git when a download fails" {
  change a.txt two pr
  change b.txt two other
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  stub_gh 'api --hostname github.com repos/octo/proj/pulls/8 -H *' 'HTTP 404: Not Found' 1
  run hub apply https://github.com/octo/proj/pull/7 https://github.com/octo/proj/pull/8
  assert_status 1
  assert_output_contains 'hub apply: could not download: https://github.com/octo/proj/pull/8'
  assert_equals "$(<a.txt)" one
  assert_equals "$(git status --porcelain)" ''
  assert_tmp_empty
}

@test "hub apply relays git apply's failure and status and removes the downloads" {
  printf 'diff --git a/c.txt b/c.txt\n--- a/c.txt\n+++ b/c.txt\n@@ -1 +1 @@\n-x\n+y\n' \
    >"$HUB_TEST_TMP/bad.diff"
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/bad.diff"
  run hub apply https://github.com/octo/proj/pull/7
  assert_status 1
  assert_output_contains 'c.txt'
  assert_equals "$(git status --porcelain)" ''
  assert_tmp_empty
  printf 'not a patch\n' >"$HUB_TEST_TMP/bad.diff"
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/bad.diff"
  run hub apply https://github.com/octo/proj/pull/7
  assert_status 128
  assert_equals "$(git status --porcelain)" ''
  assert_tmp_empty
}

@test "hub apply without a GitHub URL is plain git apply" {
  change a.txt two local
  run hub apply "$HUB_TEST_TMP/local.diff"
  assert_success
  assert_equals "$(<a.txt)" two
  for url in https://github.com/octo/proj https://github.com/octo/proj/issues/7 \
    https://github.com/octo/proj/commit/main https://github.com/octo/proj/compare \
    https://gitlab.com/octo/proj/pull/7 \
    https://github.com/octo/proj/pull https://github.com/octo/proj/pull/ \
    https://github.com/octo/proj/commit https://github.com/octo/proj/pull/x/commits/abcdef0; do
    run hub apply "$url"
    assert_failure
    assert_output_contains "can't open patch '$url'"
  done
  assert_gh_not_called
}

@test "hub apply leaves URLs after -- or --end-of-options to git" {
  local url=https://github.com/octo/proj/pull/7
  run hub apply -- "$url"
  assert_failure
  assert_output_contains "can't open patch '$url'"
  run hub apply --end-of-options "$url"
  assert_failure
  assert_output_contains "can't open patch '$url'"
  assert_gh_not_called
  change a.txt two c
  stub_patch repos/octo/proj/commits/1a2b3c4 diff "$HUB_TEST_TMP/c.diff"
  run hub apply https://github.com/octo/proj/commit/1a2b3c4 -- "$url"
  assert_failure
  assert_output_contains "can't open patch '$url'"
  assert_downloaded repos/octo/proj/commits/1a2b3c4 diff --allow-escape-sequences
  assert_equals "$(grep -c 'pulls/7' "$HUB_TEST_GH_LOG")" 0
  assert_tmp_empty
}

@test "hub apply leaves a URL that is an option's value to git" {
  local url=https://github.com/octo/proj/pull/7 option expected tree
  change a.txt two local
  for option in --include --directory --exclude; do
    run git apply "$option" "$url" "$HUB_TEST_TMP/local.diff"
    expected=$status tree=$(git status --porcelain && cat a.txt)
    git reset -q --hard
    run hub apply "$option" "$url" "$HUB_TEST_TMP/local.diff"
    assert_status "$expected"
    assert_equals "$(git status --porcelain && cat a.txt)" "$tree"
    git reset -q --hard
  done
  assert_gh_not_called
  assert_tmp_empty
}

@test "hub apply downloads a URL that follows an option's value" {
  change a.txt two pr
  stub_patch repos/octo/proj/pulls/7 diff "$HUB_TEST_TMP/pr.diff"
  run hub apply -p 1 --whitespace nowarn https://github.com/octo/proj/pull/7
  assert_success
  assert_equals "$(<a.txt)" two
  assert_downloaded repos/octo/proj/pulls/7 diff --allow-escape-sequences
  assert_tmp_empty
}

@test "hub apply hands a line it cannot read with certainty to git untouched" {
  local url=https://github.com/octo/proj/pull/7
  change a.txt two local
  run hub apply --dir "$url" "$HUB_TEST_TMP/local.diff"
  assert_failure
  assert_output_contains "https:/github.com/octo/proj/pull/7/a.txt"
  run hub apply "$url" -p
  assert_status 129
  assert_output_contains "switch \`p' requires a value"
  run hub apply $'https://github.com/octo/proj/pull/7\nx'
  assert_failure
  assert_output_contains "can't open patch 'https://github.com/octo/proj/pull/7"
  assert_gh_not_called
  assert_equals "$(git status --porcelain)" ''
}

@test "hub apply leaves a page of one commit or a range within a pull request to git" {
  local url
  for url in https://github.com/octo/proj/pull/7/files/abc1234 \
    https://github.com/octo/proj/pull/7/changes/abc1234 \
    https://github.com/octo/proj/pull/7/files/abc1234..def5678; do
    run hub apply "$url"
    assert_failure
    assert_output_contains "can't open patch '$url'"
  done
  assert_gh_not_called
}

@test "hub apply --help is git's manual" {
  run hub --noop apply --help https://github.com/octo/proj/pull/7
  assert_success
  assert_output_equals 'git apply --help https://github.com/octo/proj/pull/7'
  assert_gh_not_called
}

@test "hub apply --help-all is git's usage, before anything is downloaded" {
  run hub apply --help-all https://github.com/octo/proj/pull/7
  assert_git_help apply
  assert_gh_not_called
  assert_tmp_empty
}

@test "hub apply -h is git's usage, with nothing downloaded" {
  local word
  for word in -h -Rh; do
    run hub apply "$word" https://github.com/octo/proj/pull/7
    assert_git_help apply
    assert_line_equals 0 'usage: git apply [<options>] [<patch>...]'
  done
  assert_gh_not_called
}

@test "hub apply refuses a URL without gh" {
  PATH=$(no_gh_path mktemp rm) run hub apply https://github.com/octo/proj/pull/7
  assert_status 1
  assert_output_equals 'hub apply: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_tmp_empty
}

@test "hub help apply prints hub's manual ending with git's" {
  run hub help apply
  assert_success
  assert_line_equals 0 'Summary: Apply the changes of a GitHub pull request, commit or comparison.'
  assert_equals "${lines[${#lines[@]} - 1]}" "git's own manual: git apply --help"
}
