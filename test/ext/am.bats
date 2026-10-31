#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12
SHA=fdb99214a7c3b2b4b4f5c1f1f9b0e8c9d1e2f3a4
PATCH='-H Accept:\ application/vnd.github.v3.patch'
# ESCAPES : the line of `gh api --help` in gh 2.103 and later that hub looks for.
ESCAPES='      --allow-escape-sequences   Allow printing terminal escape sequences'

@test "am of a pull request URL downloads its patch series through gh's API and runs git am on it" {
  use_tmpdir
  run hub --noop am -3 "$PR"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls/12 $PATCH > TMP/1.patch
git am -3 TMP/1.patch"
  # Nothing is downloaded: gh is only asked whether it has --allow-escape-sequences (here it does not).
  [[ $(gh_calls) == "gh api --help" ]]
  assert_tmp_cleaned
}

@test "am of a commit URL, or of one commit of a pull request, downloads that commit's patch" {
  use_tmpdir
  run hub --noop am "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $PATCH > TMP/1.patch
git am TMP/1.patch"
  run hub --noop am "$PR/commits/abc1234"
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/mislav/dotfiles/commits/abc1234 $PATCH > TMP/1.patch"
}

@test "am of a compare URL downloads the patch series between its two ends" {
  use_tmpdir
  run hub --noop am https://github.com/mislav/dotfiles/compare/main...topic
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/compare/main...topic $PATCH > TMP/1.patch
git am TMP/1.patch"
  run hub --noop am https://github.com/mislav/dotfiles/compare/v1.0...jingweno:feature.patch
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/mislav/dotfiles/compare/v1.0...jingweno:feature $PATCH > TMP/1.patch"
  run hub --noop am https://github.com/mislav/dotfiles/compare
  assert_output_equals "git am https://github.com/mislav/dotfiles/compare"
}

@test "the raw .patch and .diff forms of the URLs are accepted, and am always downloads the patch form" {
  use_tmpdir
  local url
  for url in "$PR.patch" "$PR.diff"; do
    run hub --noop am "$url"
    assert_success
    untmp
    assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls/12 $PATCH > TMP/1.patch
git am TMP/1.patch"
  done
  run hub --noop am "https://github.com/mislav/dotfiles/commit/$SHA.patch"
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $PATCH > TMP/1.patch"
  run hub --noop am "$PR/commits/abc1234.diff"
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/mislav/dotfiles/commits/abc1234 $PATCH > TMP/1.patch"
  run hub --noop am "$PR.txt"
  assert_output_equals "git am $PR.txt"
  assert_tmp_cleaned
}

@test "am always tells gh api the commit URL's host" {
  use_tmpdir
  git config --global hub.host ghe.example.com
  run hub --noop am https://ghe.example.com/team/app/commit/abc1234
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname ghe.example.com repos/team/app/commits/abc1234 $PATCH > TMP/1.patch"
  # Also when that host is gh's default anyway.
  export GH_HOST=ghe.example.com
  run hub --noop am https://ghe.example.com/team/app/pull/7
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname ghe.example.com repos/team/app/pulls/7 $PATCH > TMP/1.patch"
}

@test "am looks up a github.com commit on github.com, whatever host gh defaults to" {
  use_tmpdir
  export GH_HOST=enterprise.example
  run hub --noop am https://github.com/org/repo/commit/abcdef0
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/org/repo/commits/abcdef0 $PATCH > TMP/1.patch
git am TMP/1.patch"
  # No GH_HOST, and gh is logged in to enterprise.example only, which makes that gh's default host.
  unset GH_HOST
  mkdir -p "$GH_CONFIG_DIR"
  printf 'enterprise.example:\n    user: me\n' >"$GH_CONFIG_DIR/hosts.yml"
  run hub --noop am https://github.com/org/repo/commit/abcdef0
  assert_success
  untmp
  assert_line_equals 0 "gh api --hostname github.com repos/org/repo/commits/abcdef0 $PATCH > TMP/1.patch"
}

@test "am passes --allow-escape-sequences to gh when gh has it, asking gh once" {
  use_tmpdir
  stub_gh 'api --help' "$ESCAPES"
  run hub --noop am "$PR" "https://github.com/mislav/dotfiles/commit/$SHA" "$PR/commits/abc1234" https://github.com/mislav/dotfiles/pull/13
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls/12 $PATCH --allow-escape-sequences > TMP/1.patch
gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $PATCH --allow-escape-sequences > TMP/2.patch
gh api --hostname github.com repos/mislav/dotfiles/commits/abc1234 $PATCH --allow-escape-sequences > TMP/3.patch
gh api --hostname github.com repos/mislav/dotfiles/pulls/13 $PATCH --allow-escape-sequences > TMP/4.patch
git am TMP/1.patch TMP/2.patch TMP/3.patch TMP/4.patch"
  [[ $(gh_calls) == "gh api --help" ]]
  assert_tmp_cleaned
}

@test "am leaves --allow-escape-sequences out for a gh that does not have it" {
  use_tmpdir
  stub_gh 'api --help' 'FLAGS\n      -H, --header key:value   Add a HTTP request header\n      --hostname string        The GitHub hostname'
  run hub --noop am "$PR" "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls/12 $PATCH > TMP/1.patch
gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $PATCH > TMP/2.patch
git am TMP/1.patch TMP/2.patch"
  [[ $(gh_calls) == "gh api --help" ]]
}

@test "am replaces each URL in place and keeps every other argument" {
  use_tmpdir
  make_repo dotfiles # git lists am's options, which hub reads to find the URLs, only inside a repository
  run hub --noop am --signoff local.patch "$PR" -3 "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls/12 $PATCH > TMP/1.patch
gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $PATCH > TMP/2.patch
git am --signoff local.patch TMP/1.patch -3 TMP/2.patch"
}

@test "am never takes the value of an option for a URL" {
  use_tmpdir
  make_repo dotfiles
  run hub --noop am --exclude "$PR" local.patch
  assert_success
  assert_output_equals "git am --exclude $PR local.patch"
  local opt
  for opt in --include --directory --whitespace -p -C -3p -3C --patch-format --quoted-cr --empty --resolvemsg; do
    run hub --noop am "$opt" "$PR" local.patch
    assert_success
    assert_output_equals "git am $opt $PR local.patch"
  done
  run hub --noop am --exclude "$PR" "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/commits/$SHA $PATCH > TMP/1.patch
git am --exclude $PR TMP/1.patch"
  assert_tmp_cleaned
}

@test "am still downloads a URL after an attached option value or -S" {
  use_tmpdir
  make_repo dotfiles
  run hub --noop am --directory=x -p1 "$PR"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls/12 $PATCH > TMP/1.patch
git am --directory=x -p1 TMP/1.patch"
  run hub --noop am -S "$PR"
  assert_success
  untmp
  assert_line_equals 1 "git am -S TMP/1.patch"
  run hub --noop am --gpg-sign "$PR"
  assert_success
  untmp
  assert_line_equals 1 "git am --gpg-sign TMP/1.patch"
  # an attached key id is -S's value to its end, whatever letters it ends in
  run hub --noop am -Skeyp "$PR"
  assert_success
  untmp
  assert_line_equals 1 "git am -Skeyp TMP/1.patch"
  run hub --noop am -3S "$PR"
  assert_success
  untmp
  assert_line_equals 1 "git am -3S TMP/1.patch"
}

@test "am reads abbreviated options as git does" {
  use_tmpdir
  make_repo dotfiles
  run hub --noop am --excl "$PR" local.patch
  assert_success
  assert_output_equals "git am --excl $PR local.patch"
  run hub --noop am --sign "$PR"
  assert_success
  untmp
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls/12 $PATCH > TMP/1.patch
git am --sign TMP/1.patch"
  # an option git would refuse, ambiguous here, leaves the command line to git
  run hub --noop am --in "$PR"
  assert_success
  assert_output_equals "git am --in $PR"
  run hub am --in "$PR"
  assert_failure
  assert_output_contains "ambiguous option"
  assert_tmp_cleaned
}

@test "am leaves the arguments after -- alone" {
  run hub --noop am -3 -- "$PR"
  assert_success
  assert_output_equals "git am -3 -- $PR"
  assert_gh_not_called
}

@test "am without a GitHub pull request, commit or compare URL is plain git am" {
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
  run hub --noop am https://github.com/mislav/dotfiles
  assert_output_equals "git am https://github.com/mislav/dotfiles"
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
  stub_gh_file "api --hostname github.com repos/mislav/dotfiles/pulls/12 -H Accept: application/vnd.github.v3.patch" "$HUB_TEST_TMP/pr.patch"
  run hub am "$PR"
  assert_success
  [[ $(git log -1 --format='%an <%ae>|%s|%b') == "Jingwen Owen Ou <jingweno@example.test>|Fix the build|It was broken." ]]
  [[ $(git symbolic-ref --short HEAD) == main && -f build.txt ]]
  assert_gh_called "api --hostname github.com repos/mislav/dotfiles/pulls/12 -H Accept: application/vnd.github.v3.patch"
  assert_tmp_cleaned
  # the raw .patch URL of a commit applies the same way
  git reset -q --hard HEAD~1
  stub_gh_file "api --hostname github.com repos/mislav/dotfiles/commits/$SHA -H Accept: application/vnd.github.v3.patch" "$HUB_TEST_TMP/pr.patch"
  run hub am "https://github.com/mislav/dotfiles/commit/$SHA.patch"
  assert_success
  [[ $(git log -1 --format=%s) == "Fix the build" && -f build.txt ]]
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
  stub_gh 'api --help' "$ESCAPES"
  # Like gh 2.103 and later: no escape bytes written without --allow-escape-sequences.
  stub_gh "api --hostname github.com repos/mislav/dotfiles/pulls/12 -H Accept: application/vnd.github.v3.patch" '' 1
  stub_gh_file "api --hostname github.com repos/mislav/dotfiles/pulls/12 -H Accept: application/vnd.github.v3.patch --allow-escape-sequences" "$HUB_TEST_TMP/pr.patch"
  run hub am "$PR"
  assert_success
  [[ $(git log -1 --format=%s) == "Add colors" && $(<colors.txt) == $'red: \e[31mred\e[0m' ]]
  assert_tmp_cleaned
}

@test "am aborts when a download fails, without running git am" {
  use_tmpdir
  make_repo dotfiles
  stub_gh "api --hostname github.com repos/mislav/dotfiles/pulls/12 *" '' 1
  run hub am "$PR"
  assert_failure
  assert_output_equals "Aborted: could not download $PR"
  [[ ! -d .git/rebase-apply ]]
  assert_tmp_cleaned
}

@test "am --help prints the manual" {
  run hub am --help
  assert_success
  assert_line_equals 0 "Summary: Apply the commits behind a GitHub pull request, commit or compare URL."
  assert_output_contains "Usage: hub am [<git-am options>] (URL | MBOX)..."
  run hub am -3 --help
  assert_success
  assert_output_contains "Usage: hub am"
}
