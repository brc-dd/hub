#!/usr/bin/env bats
# hub compare: the compare page of a range, or of the current branch where it is pushed.

load test_helper

page=https://github.com/mislav/dotfiles/compare

@test "hub compare opens the page of a range, with A..B written A...B" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare v1.0..v1.1
  assert_success
  assert_output_equals ''
  assert_equals "$(opened)" "$page/v1.0...v1.1"
  run hub compare v1.0...v1.1
  assert_success
  run hub compare feature
  assert_success
  assert_equals "$(opened)" "$page/v1.0...v1.1
$page/v1.0...v1.1
$page/feature"
  assert_gh_not_called
}

@test "hub compare -u prints the URL, -c copies it, and both print then copy" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare -u v1..v2
  assert_success
  assert_output_equals "$page/v1...v2"
  run hub compare -c v2..v3
  assert_success
  assert_output_equals ''
  assert_equals "$(copied)" "$page/v2...v3"
  run hub compare -uc v3..v4
  assert_success
  assert_output_equals "$page/v3...v4"
  assert_equals "$(copied)" "$page/v3...v4"
  run hub compare -u -c v4..v5
  assert_success
  assert_output_equals "$page/v4...v5"
  assert_equals "$(copied)" "$page/v4...v5"
  assert_equals "$(opened)" ''
}

@test "hub compare takes hub 2.x's long options --url, --copy and --base" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare --url a..b
  assert_success
  assert_output_equals "$page/a...b"
  run hub compare --copy b..c
  assert_success
  assert_output_equals ''
  assert_equals "$(copied)" "$page/b...c"
  run hub compare --url --base=develop feature
  assert_success
  assert_output_equals "$page/develop...feature"
  run hub compare --url --base main alice feature
  assert_success
  assert_output_equals https://github.com/alice/dotfiles/compare/main...feature
  run hub compare --base
  assert_status 1
  assert_line_equals 0 'hub compare: --base needs a value'
  run hub compare --base= feature
  assert_status 1
  assert_line_equals 0 'hub compare: --base needs a branch name'
  run hub compare --base=a..b feature
  assert_status 1
  assert_line_equals 0 'hub compare: use either -b BASE or a range, not both: a..b'
  assert_equals "$(opened)" ''
}

@test "hub compare exits with the browser's or the clipboard's status" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  HUB_TEST_BROWSER_STATUS=3 run hub compare a..b
  assert_status 3
  assert_equals "$(opened)" "$page/a...b"
  HUB_TEST_CLIPBOARD_STATUS=4 run hub compare -u -c a..b
  assert_status 4
  assert_output_equals "$page/a...b"
  HUB_TEST_CLIPBOARD_STATUS=5 run hub compare -c c..d
  assert_status 5
  assert_output_equals ''
  assert_equals "$(opened)" "$page/a...b"
}

@test "hub compare escapes the range but keeps slashes and colons" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare -u 'fix/a+b#1'
  assert_success
  assert_output_equals "$page/fix/a%2Bb%231"
  run hub compare -u 'main...alice:my branch'
  assert_success
  assert_output_equals "$page/main...alice:my%20branch"
}

@test "hub compare OWNER RANGE opens OWNER's copy of the project" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare -u alice v1..v2
  assert_success
  assert_output_equals https://github.com/alice/dotfiles/compare/v1...v2
}

@test "hub compare -b BASE HEAD compares HEAD with BASE" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare -u -b develop feature
  assert_success
  assert_output_equals "$page/develop...feature"
  run hub compare -u -b develop alice feature
  assert_success
  assert_output_equals https://github.com/alice/dotfiles/compare/develop...feature
  run hub compare -ubdevelop -- -x
  assert_success
  assert_output_equals "$page/develop...-x"
}

@test "hub compare refuses a range with an empty side or two separators" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  local range
  for range in v1.0.. ..v1.1 v1.0... ...v1.1 a..b..c a...b...c a....b; do
    run hub compare "$range"
    assert_status 1
    assert_line_equals 0 "hub compare: not a range: $range"
    assert_line_equals 1 'Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]'
  done
  assert_equals "$(opened)" ''
}

@test "hub compare refuses -b with a range, a bad OWNER, extra words and unknown options" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare -b develop a..b
  assert_status 1
  assert_line_equals 0 'hub compare: use either -b BASE or a range, not both: a..b'
  assert_line_equals 1 'Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]'
  run hub compare -b develop a...b
  assert_status 1
  assert_line_equals 0 'hub compare: use either -b BASE or a range, not both: a...b'
  run hub compare -b main..x
  assert_status 1
  assert_line_equals 0 'hub compare: use either -b BASE or a range, not both: main..x'
  run hub compare -b a...b feature
  assert_status 1
  assert_line_equals 0 'hub compare: use either -b BASE or a range, not both: a...b'
  run hub compare alice/dotfiles a..b
  assert_status 1
  assert_line_equals 0 'hub compare: not an owner: alice/dotfiles'
  run hub compare x.y a..b
  assert_status 1
  assert_line_equals 0 'hub compare: not an owner: x.y'
  run hub compare alice a..b c
  assert_status 1
  assert_line_equals 0 'hub compare: unexpected argument: c'
  run hub compare -x a..b
  assert_status 1
  assert_line_equals 0 'hub compare: unknown option: -x'
  run hub compare --url=yes a..b
  assert_status 1
  assert_line_equals 0 'hub compare: unknown option: --url=yes'
  run hub compare -b
  assert_status 1
  assert_line_equals 0 'hub compare: -b needs a value'
  run hub compare -b '' feature
  assert_status 1
  assert_line_equals 0 'hub compare: -b needs a branch name'
  run hub compare ''
  assert_status 1
  assert_line_equals 0 'hub compare: empty range'
  assert_equals "$(opened)" ''
}

@test "hub compare --help prints its manual" {
  run hub compare --help
  assert_success
  assert_line_equals 0 'Summary: Open a GitHub compare page for a branch or a range.'
  assert_line_equals 1 'Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]'
  run hub compare -h
  assert_success
  assert_line_equals 0 'Summary: Open a GitHub compare page for a branch or a range.'
}

@test "hub compare uses GH_REPO, outside a repository too" {
  GH_REPO=cli/cli run hub compare -u v1..v2
  assert_success
  assert_output_equals https://github.com/cli/cli/compare/v1...v2
  GH_REPO=git.example.com/o/r run hub compare -u v1..v2
  assert_output_equals https://git.example.com/o/r/compare/v1...v2
}

@test "hub compare without a GitHub remote says so" {
  make_repo work origin=https://example.com/o/r.git
  run hub compare a..b
  assert_status 1
  assert_output_equals 'hub compare: no GitHub remote found (looked for upstream, github, origin)'
}

@test "hub compare under --noop prints the open or copy command" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare a..b
  assert_success
  assert_output_equals "open $page/a...b"
  run hub --noop compare -c a..b
  assert_success
  assert_output_equals "copy $page/a...b"
  assert_equals "$(opened)" ''
  assert_equals "$(copied)" ''
}

@test "hub compare without a range opens the pushed current branch" {
  pushed_feature
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  run hub compare
  assert_success
  assert_equals "$(opened)" "$page/feature"
  run hub compare -u -b develop
  assert_success
  assert_output_equals "$page/develop...feature"
}

@test "hub compare matches a mixed-case GH_HOST with the push remote's host" {
  pushed_feature
  GH_HOST=GitHub.com GH_REPO=mislav/dotfiles run hub compare -u
  assert_success
  assert_output_equals "$page/feature"
}

@test "hub compare accepts a pushed branch with local commits on top" {
  pushed_feature
  commit_on feature 'not pushed yet'
  run hub compare -u
  assert_success
  assert_output_equals "$page/feature"
}

@test "hub compare refuses a branch that is not pushed, an unborn branch and a detached HEAD" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c feature
  run hub compare
  assert_status 1
  assert_output_equals \
    'hub compare: feature is not pushed to origin (push it first, or name a range)'
  git switch -q --orphan unborn
  run hub compare -u
  assert_status 1
  assert_output_equals \
    'hub compare: unborn is not pushed to origin (push it first, or name a range)'
  git switch -q --detach feature
  run hub compare -u
  assert_status 1
  assert_output_equals 'hub compare: not on a branch (check out a branch, or name a range)'
  assert_equals "$(opened)" ''
}

@test "hub compare writes a branch on your fork as OWNER:BRANCH against the upstream project" {
  serve_github github/dotfiles mislav/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/github/dotfiles.git
  git switch -q -c feature
  git push -q origin refs/heads/feature:refs/heads/feature 2>/dev/null
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  # No upstream: of two remotes, the one on your login's account is where it pushes.
  run hub compare -u
  assert_success
  assert_output_equals https://github.com/github/dotfiles/compare/mislav:feature
  assert_gh_called 'config get user -h github.com'
}

@test "hub compare -b BASE escapes the current branch as a head on your fork" {
  serve_github github/dotfiles mislav/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/github/dotfiles.git
  git switch -q -c fix/a+b
  git push -q -u origin refs/heads/fix/a+b:refs/heads/fix/a+b 2>/dev/null
  assert_equals "$(server_ref mislav/dotfiles refs/heads/fix/a+b)" "$(tip fix/a+b)"
  run hub compare -u -b develop
  assert_success
  assert_output_equals https://github.com/github/dotfiles/compare/develop...mislav:fix/a%2Bb
}

@test "hub compare follows remote.pushDefault to a remote without the branch" {
  serve_github github/dotfiles mislav/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/github/dotfiles.git
  git switch -q -c feature
  git push -q -u origin refs/heads/feature:refs/heads/feature 2>/dev/null
  git config remote.pushDefault upstream
  run hub compare -u
  assert_status 1
  local refusal='hub compare: feature is not pushed to upstream (push it first, or name a range)'
  assert_output_equals "$refusal"
}

@test "hub compare reads the owner of the push remote case-insensitively" {
  serve_github github/dotfiles mislav/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/github/dotfiles.git
  git switch -q -c feature
  git push -q -u origin refs/heads/feature:refs/heads/feature 2>/dev/null
  git remote set-url --push origin https://github.com/Mislav/dotfiles.git
  run hub compare -u
  assert_output_equals https://github.com/github/dotfiles/compare/Mislav:feature
  GH_REPO=mislav/dotfiles run hub compare -u
  assert_success
  assert_output_equals "$page/feature"
}

@test "hub compare follows branch.BRANCH.pushRemote" {
  serve_github mislav/dotfiles alice/dotfiles
  clone_served mislav/dotfiles
  git remote add alice https://github.com/alice/dotfiles.git
  git switch -q -c feature
  git config branch.feature.pushRemote alice
  git push -q alice refs/heads/feature:refs/heads/feature 2>/dev/null
  assert_equals "$(server_ref alice/dotfiles refs/heads/feature)" "$(tip feature)"
  run hub compare -u
  assert_success
  assert_output_equals "$page/alice:feature"
  git config branch.feature.pushRemote origin
  run hub compare -u
  assert_status 1
  assert_output_equals \
    'hub compare: feature is not pushed to origin (push it first, or name a range)'
}

@test "hub compare refuses a push remote that is not on the project's host" {
  make_repo work origin=https://github.com/mislav/dotfiles.git other=https://example.com/o/r.git
  git switch -q -c feature
  git config branch.feature.pushRemote other
  git update-ref refs/remotes/other/feature HEAD
  run hub compare -u
  assert_status 1
  assert_output_equals 'hub compare: other does not push to a GitHub repository (name a range)'
  git remote set-url other https://ghe.example.com/mislav/dotfiles.git
  GH_HOST=ghe.example.com run hub compare -u
  assert_status 1
  assert_output_equals \
    'hub compare: other pushes to ghe.example.com, not to github.com (name a range)'
}

@test "hub compare refuses a branch without a push remote" {
  make_repo work github=https://github.com/alice/dotfiles.git other=https://example.com/o/r.git
  git switch -q -c feature
  run hub compare -u
  assert_status 1
  local hint='(git push -u REMOTE feature first, or name a range)'
  assert_output_equals "hub compare: cannot tell where feature pushes $hint"
}

@test "hub compare names a pushRemote or pushDefault that is no remote as the reason" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  git switch -q -c feature
  git update-ref refs/remotes/origin/feature HEAD
  git config remote.pushDefault ''
  run hub compare -u
  assert_status 1
  local hint='(set it to a remote, or name a range)'
  assert_output_equals "hub compare: remote.pushDefault names no remote $hint"
  git config branch.feature.pushRemote ''
  run hub compare -u
  assert_status 1
  assert_output_equals "hub compare: branch.feature.pushRemote names no remote $hint"
  git config remote.pushDefault origin
  run hub compare -u
  assert_status 1
  assert_output_equals "hub compare: branch.feature.pushRemote names no remote $hint"
  git config branch.feature.pushRemote https://github.com/mislav/dotfiles.git
  run hub compare -u
  assert_status 1
  assert_output_equals "hub compare: branch.feature.pushRemote names no remote $hint"
  assert_equals "$(opened)" ''
}

@test "hub compare outside a repository without a range needs GH_REPO and a work tree" {
  run hub compare
  assert_status 1
  assert_output_equals 'hub compare: no GitHub remote found (looked for upstream, github, origin)'
  GH_REPO=cli/cli run hub compare
  assert_status 1
  assert_output_contains 'not a git repository'
}

@test "hub compare shows an empty or multi-line word in its refusals quoted" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  run hub compare '' v1..v2
  assert_status 1
  assert_line_equals 0 "hub compare: not an owner: ''"
  run hub compare $'al\nice' v1..v2
  assert_status 1
  assert_line_equals 0 "hub compare: not an owner: \$'al\\nice'"
  run hub compare -b $'x\n..y'
  assert_status 1
  assert_line_equals 0 "hub compare: use either -b BASE or a range, not both: \$'x\\n..y'"
  run hub compare -b develop $'a\n..b'
  assert_status 1
  assert_line_equals 0 "hub compare: use either -b BASE or a range, not both: \$'a\\n..b'"
  run hub compare $'a\n..'
  assert_status 1
  assert_line_equals 0 "hub compare: not a range: \$'a\\n..'"
  assert_line_equals 1 'Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]'
  assert_equals "$(opened)" ''
}
