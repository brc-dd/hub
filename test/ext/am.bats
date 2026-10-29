#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12
SHA=fdb99214a7c3b2b4b4f5c1f1f9b0e8c9d1e2f3a4
ACCEPT='-H Accept:\ application/vnd.github.v3.patch'
# ESCAPES : the line of `gh pr diff --help` and `gh api --help` in gh 2.103 and later that hub looks for.
ESCAPES='      --allow-escape-sequences   Allow printing terminal escape sequences'

# use_tmpdir : point TMPDIR at an empty directory, so the temporary files hub makes can be found.
use_tmpdir() {
  export TMPDIR=$HUB_TEST_TMP/tmp
  mkdir -p "$TMPDIR"
}

# untmp : in $output and $lines, replace the temporary directory hub made with TMP.
untmp() {
  local i
  output=${output//"$TMPDIR"\/hub-am.??????/TMP}
  for i in "${!lines[@]}"; do lines[i]=${lines[i]//"$TMPDIR"\/hub-am.??????/TMP}; done
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

@test "am of a pull request URL downloads its patch series with gh and runs git am on it" {
  use_tmpdir
  run hub --noop am -3 "$PR"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --patch --color=never > TMP/1.patch
git am -3 TMP/1.patch"
  # Nothing is downloaded: gh is only asked whether it has --allow-escape-sequences (here it does not).
  [[ $(gh_calls) == "gh pr diff --help" ]]
  assert_tmp_cleaned
}

@test "am of a commit URL downloads that commit's patch from the API" {
  use_tmpdir
  run hub --noop am "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api repos/mislav/dotfiles/commits/$SHA $ACCEPT > TMP/1.patch
git am TMP/1.patch"
}

@test "am of one commit of a pull request downloads just that commit" {
  use_tmpdir
  run hub --noop am "$PR/commits/abc1234"
  assert_success
  untmp
  assert_line_equals 0 "gh api repos/mislav/dotfiles/commits/abc1234 $ACCEPT > TMP/1.patch"
}

@test "am tells gh the URL's host when gh would default to another" {
  use_tmpdir
  git config --global hub.host ghe.example.com
  run hub --noop am https://ghe.example.com/team/app/commit/abc1234
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname ghe.example.com repos/team/app/commits/abc1234 $ACCEPT > TMP/1.patch"
  export GH_HOST=ghe.example.com
  run hub --noop am https://ghe.example.com/team/app/commit/abc1234
  untmp
  assert_line_equals 0 "gh api repos/team/app/commits/abc1234 $ACCEPT > TMP/1.patch"
  run hub --noop am https://github.com/mislav/dotfiles/commit/abc1234
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/mislav/dotfiles/commits/abc1234 $ACCEPT > TMP/1.patch"
}

@test "am passes --allow-escape-sequences to gh when gh has it, asking gh once per command" {
  use_tmpdir
  stub_gh 'pr diff --help' "$ESCAPES"
  stub_gh 'api --help' "$ESCAPES"
  run hub --noop am "$PR" "https://github.com/mislav/dotfiles/commit/$SHA" "$PR/commits/abc1234" https://github.com/mislav/dotfiles/pull/13
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --patch --color=never --allow-escape-sequences > TMP/1.patch
gh api repos/mislav/dotfiles/commits/$SHA $ACCEPT --allow-escape-sequences > TMP/2.patch
gh api repos/mislav/dotfiles/commits/abc1234 $ACCEPT --allow-escape-sequences > TMP/3.patch
gh pr diff https://github.com/mislav/dotfiles/pull/13 --patch --color=never --allow-escape-sequences > TMP/4.patch
git am TMP/1.patch TMP/2.patch TMP/3.patch TMP/4.patch"
  [[ $(gh_calls) == $'gh pr diff --help\ngh api --help' ]]
  assert_tmp_cleaned
}

@test "am leaves --allow-escape-sequences out for a gh that does not have it" {
  use_tmpdir
  # This gh pr diff --help does not list the flag, and gh api --help fails (the stub has no answer).
  stub_gh 'pr diff --help' 'FLAGS\n      --color string   Use color in diff output\n      --patch          Display diff in patch format'
  run hub --noop am "$PR" "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --patch --color=never > TMP/1.patch
gh api repos/mislav/dotfiles/commits/$SHA $ACCEPT > TMP/2.patch
git am TMP/1.patch TMP/2.patch"
  [[ $(gh_calls) == $'gh pr diff --help\ngh api --help' ]]
}

@test "am replaces each URL in place and keeps every other argument" {
  use_tmpdir
  run hub --noop am --signoff local.patch "$PR" -3 "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --patch --color=never > TMP/1.patch
gh api repos/mislav/dotfiles/commits/$SHA $ACCEPT > TMP/2.patch
git am --signoff local.patch TMP/1.patch -3 TMP/2.patch"
}

@test "am never takes the value of an option for a URL" {
  use_tmpdir
  run hub --noop am --exclude "$PR" local.patch
  assert_success
  assert_output_equals "git am --exclude $PR local.patch"
  local opt
  for opt in --include --directory --whitespace -p -C --patch-format --quoted-cr --empty --resolvemsg; do
    run hub --noop am "$opt" "$PR" local.patch
    assert_success
    assert_output_equals "git am $opt $PR local.patch"
  done
  run hub --noop am --exclude "$PR" "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api repos/mislav/dotfiles/commits/$SHA $ACCEPT > TMP/1.patch
git am --exclude $PR TMP/1.patch"
  assert_tmp_cleaned
}

@test "am still downloads a URL after an attached option value or -S" {
  use_tmpdir
  run hub --noop am --directory=x -p1 "$PR"
  assert_success
  untmp
  assert_output_equals "gh pr diff $PR --patch --color=never > TMP/1.patch
git am --directory=x -p1 TMP/1.patch"
  run hub --noop am -S "$PR"
  assert_success
  untmp
  assert_line_equals 1 "git am -S TMP/1.patch"
  run hub --noop am --gpg-sign "$PR"
  assert_success
  untmp
  assert_line_equals 1 "git am --gpg-sign TMP/1.patch"
}

@test "am leaves the arguments after -- alone" {
  run hub --noop am -3 -- "$PR"
  assert_success
  assert_output_equals "git am -3 -- $PR"
  assert_gh_not_called
}

@test "am without a GitHub pull request or commit URL is plain git am" {
  run hub --noop am file.patch
  assert_success
  assert_output_equals "git am file.patch"
  run hub --noop am -3 0001-fix.patch
  assert_output_equals "git am -3 0001-fix.patch"
  run hub --noop am -h
  assert_output_equals "git am -h"
  run hub --noop am --continue
  assert_output_equals "git am --continue"
  run hub --noop am
  assert_output_equals "git am"
  run hub --noop am https://github.com/mislav/dotfiles/issues/12
  assert_output_equals "git am https://github.com/mislav/dotfiles/issues/12"
  run hub --noop am https://gitlab.com/mislav/dotfiles/commit/abc1234
  assert_output_equals "git am https://gitlab.com/mislav/dotfiles/commit/abc1234"
  assert_gh_not_called
}

@test "am really applies the downloaded commits, keeping their author and message" {
  use_tmpdir
  make_repo dotfiles
  git checkout -q -b fix-build
  echo fixed >build.txt
  git add build.txt
  git -c user.name="Jingwen Owen Ou" -c user.email=jingweno@example.test commit -q -m "Fix the build" -m "It was broken."
  git format-patch -1 --stdout >"$HUB_TEST_TMP/pr.patch"
  git checkout -q main
  stub_gh_file "pr diff $PR --patch --color=never" "$HUB_TEST_TMP/pr.patch"
  run hub am "$PR"
  assert_success
  [[ $(git log -1 --format='%an <%ae>|%s|%b') == "Jingwen Owen Ou <jingweno@example.test>|Fix the build|It was broken." ]]
  [[ $(git symbolic-ref --short HEAD) == main && -f build.txt ]]
  assert_gh_called "pr diff $PR --patch --color=never"
  assert_tmp_cleaned
}

@test "am gets a patch with terminal escape bytes through gh to git am" {
  use_tmpdir
  make_repo dotfiles
  git checkout -q -b colors
  printf 'red: \033[31mred\033[0m\n' >colors.txt
  git add colors.txt
  git commit -q -m "Add colors"
  git format-patch -1 --stdout >"$HUB_TEST_TMP/pr.patch"
  git checkout -q main
  stub_gh 'pr diff --help' "$ESCAPES"
  # Like gh 2.103 and later: no escape bytes written without --allow-escape-sequences.
  stub_gh "pr diff $PR --patch --color=never" '' 1
  stub_gh_file "pr diff $PR --patch --color=never --allow-escape-sequences" "$HUB_TEST_TMP/pr.patch"
  run hub am "$PR"
  assert_success
  [[ $(git log -1 --format=%s) == "Add colors" && $(<colors.txt) == $'red: \e[31mred\e[0m' ]]
  assert_tmp_cleaned
}

@test "am aborts when a download fails, without running git am" {
  use_tmpdir
  make_repo dotfiles
  stub_gh "pr diff $PR *" '' 1
  run hub am "$PR"
  assert_failure
  assert_output_equals "Aborted: could not download $PR"
  [[ ! -d .git/rebase-apply ]]
  assert_tmp_cleaned
}

@test "am --help prints the manual" {
  run hub am --help
  assert_success
  assert_output_contains "Usage: hub am [git-am options] [URL | MBOX]..."
}
