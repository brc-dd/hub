#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12
SHA=fdb99214a7c3b2b4b4f5c1f1f9b0e8c9d1e2f3a4
ACCEPT='-H Accept:\ application/vnd.github.v3.diff'
# ESCAPES : the line of `gh pr diff --help` and `gh api --help` in gh 2.103 and later that hub looks for.
ESCAPES='      --allow-escape-sequences   Allow printing terminal escape sequences'

@test "apply of a pull request URL downloads its combined diff with gh and runs git apply on it" {
  use_tmpdir
  run hub --noop apply "$PR"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --color=never > TMP/1.diff
git apply TMP/1.diff"
  # Nothing is downloaded: gh is only asked whether it has --allow-escape-sequences (here it does not).
  [[ $(gh_calls) == "gh pr diff --help" ]]
  assert_tmp_cleaned
}

@test "apply of a commit URL, or of one commit of a pull request, downloads that commit's diff" {
  use_tmpdir
  run hub --noop apply "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $ACCEPT > TMP/1.diff
git apply TMP/1.diff"
  run hub --noop apply "$PR/commits/abc1234"
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/mislav/dotfiles/commits/abc1234 $ACCEPT > TMP/1.diff"
}

@test "apply passes --allow-escape-sequences to gh when gh has it" {
  use_tmpdir
  stub_gh 'pr diff --help' "$ESCAPES"
  stub_gh 'api --help' "$ESCAPES"
  run hub --noop apply "$PR" "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --color=never --allow-escape-sequences > TMP/1.diff
gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $ACCEPT --allow-escape-sequences > TMP/2.diff
git apply TMP/1.diff TMP/2.diff"
  [[ $(gh_calls) == $'gh pr diff --help\ngh api --help' ]]
}

@test "apply always tells gh api the commit URL's host, whatever host gh defaults to" {
  use_tmpdir
  git config --global hub.host ghe.example.com
  run hub --noop apply https://ghe.example.com/team/app/commit/abc1234
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname ghe.example.com repos/team/app/commits/abc1234 $ACCEPT > TMP/1.diff"
  export GH_HOST=enterprise.example
  run hub --noop apply https://github.com/mislav/dotfiles/commit/abc1234
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/mislav/dotfiles/commits/abc1234 $ACCEPT > TMP/1.diff"
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

@test "apply gets a diff with terminal escape bytes through gh to git apply" {
  use_tmpdir
  make_repo dotfiles
  echo one >file.txt
  git add file.txt
  git commit -q -m "Add file"
  printf 'red: \033[31mred\033[0m\n' >>file.txt
  git diff >"$HUB_TEST_TMP/pr.diff"
  git checkout -q -- file.txt
  stub_gh 'pr diff --help' "$ESCAPES"
  # Like gh 2.103 and later: no escape bytes written without --allow-escape-sequences.
  stub_gh "pr diff $PR --color=never" '' 1
  stub_gh_file "pr diff $PR --color=never --allow-escape-sequences" "$HUB_TEST_TMP/pr.diff"
  run hub apply "$PR"
  assert_success
  [[ $(<file.txt) == $'one\nred: \e[31mred\e[0m' ]]
  assert_tmp_cleaned
}

@test "apply aborts when a download fails" {
  use_tmpdir
  stub_gh "api --hostname github.com repos/mislav/dotfiles/commits/$SHA *" '' 1
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
