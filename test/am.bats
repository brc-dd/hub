#!/usr/bin/env bats
# hub am: GitHub pull request, commit and comparison URLs applied as patch series.

load test_helper

setup() {
  hub_test_setup
  export TMPDIR=$HUB_TEST_TMP/tmp
  mkdir -p "$TMPDIR"
  make_series
  make_repo work
  stub_gh 'api --help' 'Usage: gh api <endpoint> [flags]'
}

# make_series : add-f.patch and change-f.patch, two commits by Jingwen Owen Ou, in $HUB_TEST_TMP.
make_series() {
  (
    make_repo series
    git config user.name 'Jingwen Owen Ou' && git config user.email jingweno@example.test
    echo one >f && git add f && git commit -q -m 'add f' -m 'The body of add f.'
    git format-patch -q --stdout -1 >"$HUB_TEST_TMP/add-f.patch"
    echo two >f && git commit -q -a -m 'change f'
    git format-patch -q --stdout -1 >"$HUB_TEST_TMP/change-f.patch"
  )
}

@test "hub am URL applies a pull request's commits with their authors and messages" {
  stub_patch repos/jingweno/gh/pulls/55 patch "$HUB_TEST_TMP/add-f.patch"
  run hub am -3 https://github.com/jingweno/gh/pull/55
  assert_success
  assert_equals "$(git log -1 --format='%an <%ae>|%s|%b')" \
    'Jingwen Owen Ou <jingweno@example.test>|add f|The body of add f.'
  assert_equals "$(cat f)" one
  assert_gh_called \
    'api --hostname github.com repos/jingweno/gh/pulls/55 -H Accept: application/vnd.github.patch'
  assert_tmp_empty
}

@test "hub am downloads a commit URL as a patch even with a .diff suffix" {
  stub_patch repos/jingweno/gh/commits/fdb9921 patch "$HUB_TEST_TMP/add-f.patch"
  run hub am https://github.com/jingweno/gh/commit/fdb9921.diff
  assert_success
  assert_equals "$(git log -1 --format=%s)" 'add f'
  assert_tmp_empty
}

@test "hub am downloads a pull request's commit URL from the commits endpoint" {
  stub_patch repos/jingweno/gh/commits/fdb99210 patch "$HUB_TEST_TMP/add-f.patch"
  run hub am https://github.com/jingweno/gh/pull/55/commits/fdb99210
  assert_success
  assert_equals "$(git log -1 --format=%s)" 'add f'
  assert_equals "$(grep -c pulls/55 "$HUB_TEST_GH_LOG")" 0
}

@test "hub am reads a pull request URL with a suffix, a query, a fragment or a tab as the pull" {
  local head url
  head=$(tip main)
  stub_patch repos/o/r/pulls/8 patch "$HUB_TEST_TMP/add-f.patch"
  for url in https://github.com/o/r/pull/8.patch 'https://github.com/o/r/pull/8?w=1#diff' \
    https://github.com/o/r/pull/8/ https://github.com/o/r/pull/8/files; do
    git reset -q --hard "$head"
    : >"$HUB_TEST_GH_LOG"
    run hub am "$url"
    assert_success
    assert_equals "$(git log -1 --format=%s)" 'add f'
    assert_gh_called 'api --hostname github.com repos/o/r/pulls/8 *'
  done
}

@test "hub am downloads a comparison URL with its range kept verbatim" {
  stub_patch 'repos/jingweno/gh/compare/v1.0...jingweno:feature' patch \
    "$HUB_TEST_TMP/add-f.patch"
  run hub am 'https://github.com/jingweno/gh/compare/v1.0...jingweno:feature.patch'
  assert_success
  assert_equals "$(git log -1 --format=%s)" 'add f'
}

@test "hub am keeps local mailboxes, options and URLs in their order" {
  stub_patch repos/jingweno/gh/pulls/56 patch "$HUB_TEST_TMP/change-f.patch"
  run hub am --signoff "$HUB_TEST_TMP/add-f.patch" https://github.com/jingweno/gh/pull/56
  assert_success
  assert_equals "$(git log -2 --format=%s)" $'change f\nadd f'
  assert_gh_called 'api --hostname github.com repos/jingweno/gh/pulls/56 *'
  assert_equals "$(git log -1 --format='%(trailers:key=Signed-off-by,valueonly)')" \
    'hub tests <hub@example.test>'
}

@test "hub am applies every URL's patches in command-line order" {
  stub_patch repos/jingweno/gh/commits/aaaa1111 patch "$HUB_TEST_TMP/add-f.patch"
  stub_patch repos/jingweno/gh/commits/bbbb2222 patch "$HUB_TEST_TMP/change-f.patch"
  run hub am https://github.com/jingweno/gh/commit/aaaa1111 \
    https://github.com/jingweno/gh/commit/bbbb2222
  assert_success
  assert_equals "$(git log -2 --format=%s)" $'change f\nadd f'
  assert_equals "$(cat f)" two
  assert_tmp_empty
}

@test "hub am asks gh api once whether it takes --allow-escape-sequences, and passes it" {
  stub_gh 'api --help' '  --allow-escape-sequences   Keep escape sequences'
  local accept='-H Accept: application/vnd.github.patch --allow-escape-sequences'
  stub_gh_file "api --hostname github.com repos/o/r/commits/aaaa1111 $accept" \
    "$HUB_TEST_TMP/add-f.patch"
  stub_gh_file "api --hostname github.com repos/o/r/commits/bbbb2222 $accept" \
    "$HUB_TEST_TMP/change-f.patch"
  run hub am https://github.com/o/r/commit/aaaa1111 https://github.com/o/r/commit/bbbb2222
  assert_success
  assert_equals "$(git log -2 --format=%s)" $'change f\nadd f'
  assert_equals "$(grep -c 'api --help' "$HUB_TEST_GH_LOG")" 1
}

@test "hub am asks the URL's host" {
  export GH_HOST=ghe.example.test
  stub_patch repos/o/r/pulls/7 patch "$HUB_TEST_TMP/add-f.patch" ghe.example.test
  run hub am https://GHE.example.test/o/r/pull/7
  assert_success
  assert_equals "$(git log -1 --format=%s)" 'add f'
}

@test "hub am stops before git am when a download fails" {
  local head
  head=$(tip main)
  stub_gh 'api --hostname github.com repos/o/r/pulls/9 *' '' 1
  stub_patch repos/o/r/pulls/8 patch "$HUB_TEST_TMP/add-f.patch"
  PATH=$(failing_gh 'gh: Not Found (HTTP 404)'):$PATH run hub am https://github.com/o/r/pull/8 \
    https://github.com/o/r/pull/9
  assert_status 1
  assert_output_contains 'gh: Not Found (HTTP 404)'
  assert_output_contains 'hub am: could not download: https://github.com/o/r/pull/9'
  assert_equals "$(tip main)" "$head"
  assert_equals "$(find .git -maxdepth 1 -name rebase-apply)" ''
  assert_tmp_empty
}

@test "hub am returns git am's status and leaves a resumable session when a patch fails" {
  echo local >f && git add f && git commit -q -m 'local f'
  stub_patch repos/o/r/pulls/8 patch "$HUB_TEST_TMP/add-f.patch"
  run hub am https://github.com/o/r/pull/8
  assert_status 128
  assert_output_contains 'Patch failed at 0001 add f'
  assert_tmp_empty
  run git am --skip
  assert_success
  assert_equals "$(git log -1 --format=%s)" 'local f'
}

@test "hub am downloads nothing while an am session is in progress, and git am refuses" {
  echo local >f && git add f && git commit -q -m 'local f'
  stub_patch repos/o/r/pulls/8 patch "$HUB_TEST_TMP/add-f.patch"
  run hub am https://github.com/o/r/pull/8
  assert_status 128
  : >"$HUB_TEST_GH_LOG"
  run hub am https://github.com/o/r/pull/8
  assert_status 128
  assert_output_contains 'rebase-apply still exists but mbox given'
  assert_gh_not_called
  assert_tmp_empty
}

@test "hub am outside a repository relays git's message and downloads nothing" {
  cd "$HUB_TEST_TMP"
  run hub am https://github.com/o/r/pull/8
  assert_status 1
  assert_output_contains 'not a git repository'
  assert_gh_not_called
  assert_tmp_empty
}

@test "hub am with a URL refuses without gh, before git runs" {
  local head
  head=$(tip main)
  PATH=$(no_gh_path mktemp rm) run hub am https://github.com/o/r/pull/8
  assert_status 1
  assert_output_equals 'hub am: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_equals "$(tip main)" "$head"
  assert_equals "$(find .git -maxdepth 1 -name rebase-apply)" ''
  assert_tmp_empty
}

@test "hub am without a URL is plain git am" {
  run hub am "$HUB_TEST_TMP/add-f.patch"
  assert_success
  assert_equals "$(git log -1 --format=%an)" 'Jingwen Owen Ou'
  assert_gh_not_called
}

@test "hub am leaves URLs after -- or --end-of-options to git" {
  local url=https://github.com/o/r/pull/8
  run hub am -- "$url"
  assert_failure
  assert_output_contains "$url"
  run hub am --end-of-options "$url"
  assert_failure
  assert_output_contains "$url"
  assert_gh_not_called
}

@test "hub am leaves other GitHub URLs to git" {
  local url
  for url in https://github.com/o/r https://github.com/o/r/issues/8 \
    https://github.com/o/r/compare https://github.com/o/r/commit/main \
    https://github.com/o/r/pull/abc https://github.com/o/r/pull/abc/commits/abcd \
    https://gist.github.com/o/0123abcd \
    https://gitlab.com/o/r/pull/8 https://ghe.other.test/o/r/pull/8; do
    run hub am "$url"
    assert_failure
    assert_output_contains "$url"
  done
  assert_gh_not_called
}

@test "hub am leaves a URL that is an option's value to git" {
  local url=https://github.com/o/r/pull/8 head option expected files
  head=$(tip main)
  for option in --directory --include --exclude; do
    run git am "$option" "$url" "$HUB_TEST_TMP/add-f.patch"
    expected=$status files=$(git ls-files)
    git am --abort 2>/dev/null || true
    git reset -q --hard "$head"
    run hub am "$option" "$url" "$HUB_TEST_TMP/add-f.patch"
    assert_status "$expected"
    assert_equals "$(git ls-files)" "$files"
    git am --abort 2>/dev/null || true
    git reset -q --hard "$head"
  done
  assert_gh_not_called
  assert_tmp_empty
}

@test "hub am downloads a URL that follows an option's value" {
  stub_patch repos/o/r/pulls/8 patch "$HUB_TEST_TMP/add-f.patch"
  run hub am -p 1 --patch-format mbox https://github.com/o/r/pull/8
  assert_success
  assert_equals "$(git log -1 --format=%s)" 'add f'
  assert_gh_called 'api --hostname github.com repos/o/r/pulls/8 *'
  assert_tmp_empty
}

@test "hub am hands a line it cannot read with certainty to git untouched" {
  local head url=https://github.com/o/r/pull/8
  head=$(tip main)
  run hub am --dir "$url" "$HUB_TEST_TMP/add-f.patch"
  assert_success
  assert_equals "$(git ls-files)" https:/github.com/o/r/pull/8/f
  git reset -q --hard "$head"
  run hub am "$url" -C
  assert_status 129
  run hub am $'https://github.com/o/r/pull/8\nx'
  assert_failure
  assert_gh_not_called
  assert_equals "$(tip main)" "$head"
  assert_tmp_empty
}

@test "hub am leaves a page of one commit or a range within a pull request to git" {
  local url
  for url in https://github.com/o/r/pull/8/files/abc1234 \
    https://github.com/o/r/pull/8/changes/abc1234 \
    https://github.com/o/r/pull/8/files/abc1234..def5678; do
    run hub am "$url"
    assert_failure
    assert_output_contains "$url"
  done
  assert_gh_not_called
}

@test "hub am -h, alone or among one-letter flags, prints git am's usage" {
  run hub am -h https://github.com/o/r/pull/8
  assert_git_help am
  assert_output_contains 'usage: git am'
  run hub am -3h https://github.com/o/r/pull/8
  assert_git_help am
  assert_output_contains 'usage: git am'
  assert_gh_not_called
}

@test "hub am --help hands the line to git for its manual" {
  run hub --noop am --help https://github.com/o/r/pull/8
  assert_success
  assert_output_equals 'git am --help https://github.com/o/r/pull/8'
  assert_gh_not_called
}

@test "hub am --help-all is git's usage, before anything is downloaded" {
  run hub am --help-all https://github.com/o/r/pull/8
  assert_git_help am
  assert_gh_not_called
  assert_tmp_empty
}

@test "hub help am prints hub's manual, ending with the pointer to git's" {
  run hub help am
  assert_success
  assert_line_equals 0 \
    'Summary: Apply the commits of a GitHub pull request, commit or comparison.'
  assert_line_equals -1 "git's own manual: git am --help"
}

@test "hub --noop am downloads the patch and prints git am instead of running it" {
  local head
  head=$(tip main)
  stub_patch repos/o/r/pulls/8 patch "$HUB_TEST_TMP/add-f.patch"
  run hub --noop am -3 https://github.com/o/r/pull/8
  assert_success
  assert_output_contains "git am -3 $TMPDIR/hub-am."
  assert_output_contains /1.patch
  assert_equals "$(tip main)" "$head"
  assert_tmp_empty
}
