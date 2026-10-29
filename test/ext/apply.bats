#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12
SHA=fdb99214a7c3b2b4b4f5c1f1f9b0e8c9d1e2f3a4
ACCEPT='-H Accept:\ application/vnd.github.v3.diff'

# use_tmpdir : point TMPDIR at an empty directory, so the temporary files hub makes can be found.
use_tmpdir() {
  export TMPDIR=$HUB_TEST_TMP/tmp
  mkdir -p "$TMPDIR"
}

# untmp : in $output and $lines, replace the temporary directory hub made with TMP.
untmp() {
  local i
  output=${output//"$TMPDIR"\/hub-apply.??????/TMP}
  for i in "${!lines[@]}"; do lines[i]=${lines[i]//"$TMPDIR"\/hub-apply.??????/TMP}; done
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

@test "apply of a pull request URL downloads its combined diff with gh and runs git apply on it" {
  use_tmpdir
  run hub --noop apply "$PR"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --color=never > TMP/1.diff
git apply TMP/1.diff"
  assert_gh_not_called
  assert_tmp_cleaned
}

@test "apply of a commit URL, or of one commit of a pull request, downloads that commit's diff" {
  use_tmpdir
  run hub --noop apply "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api repos/mislav/dotfiles/commits/$SHA $ACCEPT > TMP/1.diff
git apply TMP/1.diff"
  run hub --noop apply "$PR/commits/abc1234"
  untmp
  assert_line_equals 0 "gh api repos/mislav/dotfiles/commits/abc1234 $ACCEPT > TMP/1.diff"
}

@test "apply tells gh an enterprise URL's host" {
  use_tmpdir
  git config --global hub.host ghe.example.com
  run hub --noop apply https://ghe.example.com/team/app/commit/abc1234
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname ghe.example.com repos/team/app/commits/abc1234 $ACCEPT > TMP/1.diff"
}

@test "apply keeps git-apply options and other patches in place" {
  use_tmpdir
  run hub --noop apply --check -R "$PR" local.diff
  assert_success
  untmp
  assert_line_equals 1 "git apply --check -R TMP/1.diff local.diff"
}

@test "apply never takes the value of an option for a URL" {
  use_tmpdir
  run hub --noop apply --exclude "$PR" local.patch
  assert_success
  assert_output_equals "git apply --exclude $PR local.patch"
  local opt
  for opt in --include --directory --whitespace -p -C --build-fake-ancestor; do
    run hub --noop apply "$opt" "$PR" local.patch
    assert_success
    assert_output_equals "git apply $opt $PR local.patch"
  done
  assert_gh_not_called
  assert_tmp_cleaned
}

@test "apply still downloads a URL after an attached option value" {
  use_tmpdir
  run hub --noop apply --directory=x "$PR"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --color=never > TMP/1.diff
git apply --directory=x TMP/1.diff"
}

@test "apply leaves the arguments after -- alone" {
  run hub --noop apply -- "$PR"
  assert_success
  assert_output_equals "git apply -- $PR"
  assert_gh_not_called
}

@test "apply without a GitHub pull request or commit URL is plain git apply" {
  run hub --noop apply --index fix.diff
  assert_success
  assert_output_equals "git apply --index fix.diff"
  run hub --noop apply
  assert_output_equals "git apply"
  run hub --noop apply -h
  assert_output_equals "git apply -h"
  run hub --noop apply https://github.com/mislav/dotfiles
  assert_output_equals "git apply https://github.com/mislav/dotfiles"
  assert_gh_not_called
}

@test "apply really applies the downloaded diff to the working tree" {
  use_tmpdir
  make_repo dotfiles
  echo one >file.txt
  git add file.txt
  git commit -q -m "Add file"
  echo two >>file.txt
  git diff >"$HUB_TEST_TMP/pr.diff"
  git checkout -q -- file.txt
  stub_gh_file "pr diff $PR --color=never" "$HUB_TEST_TMP/pr.diff"
  run hub apply "$PR"
  assert_success
  [[ $(<file.txt) == $'one\ntwo' ]]
  [[ $(git rev-list --count HEAD) == 2 ]]
  assert_gh_called "pr diff $PR --color=never"
  assert_tmp_cleaned
}

@test "apply aborts when a download fails" {
  use_tmpdir
  stub_gh "api repos/mislav/dotfiles/commits/$SHA *" '' 1
  run hub apply "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_failure
  assert_output_equals "Aborted: could not download https://github.com/mislav/dotfiles/commit/$SHA"
  assert_tmp_cleaned
}

@test "apply --help prints apply's own manual" {
  run hub apply --help
  assert_success
  assert_output_contains "Usage: hub apply [git-apply options] [URL | PATCH]..."
  [[ $output != *"Usage: hub am"* ]]
}
