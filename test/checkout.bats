#!/usr/bin/env bats
# hub checkout: a pull request URL goes to gh pr checkout, everything else to git checkout.

load test_helper

pr=https://github.com/rails/rails/pull/42

setup() {
  hub_test_setup
  serve_github rails/rails
  clone_served rails/rails
  stub_gh 'pr checkout *' ''
}

# gh_host_log : a gh in front of the stub that records the GH_HOST it was given.
gh_host_log() {
  mkdir -p "$HUB_TEST_TMP/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GH_HOST-unset}" >>"%s"\nexec "%s" "$@"\n' \
    "$HUB_TEST_TMP/gh-host.log" "$HUB_TEST_ROOT/test/stubs/gh" >"$HUB_TEST_TMP/bin/gh"
  chmod +x "$HUB_TEST_TMP/bin/gh"
  PATH=$HUB_TEST_TMP/bin:$PATH
}

@test "hub checkout with a pull request URL runs gh pr checkout on it" {
  run hub checkout "$pr"
  assert_success
  assert_equals "$(gh_calls)" "gh pr checkout $pr"
}

@test "hub checkout takes the local branch from the operand, -b or -bBRANCH" {
  run hub checkout "$pr" review
  assert_success
  run hub checkout -b review "$pr"
  assert_success
  run hub checkout "$pr" -breview
  assert_success
  run hub checkout -b first -b last "$pr"
  assert_success
  assert_equals "$(gh_calls)" "gh pr checkout $pr -b review
gh pr checkout $pr -b review
gh pr checkout $pr -b review
gh pr checkout $pr -b last"
}

@test "hub checkout passes --detach, -d and --recurse-submodules to gh once each" {
  run hub checkout --recurse-submodules "$pr" -d --detach
  assert_success
  run hub checkout "$pr" review --recurse-submodules
  assert_success
  assert_equals "$(gh_calls)" "gh pr checkout $pr --detach --recurse-submodules
gh pr checkout $pr -b review --recurse-submodules"
}

@test "hub checkout takes any page of a pull request, with a query or fragment" {
  run hub checkout "$pr/files?w=1"
  assert_success
  run hub checkout "http://github.com/rails/rails/pull/42#discussion"
  assert_success
  assert_equals "$(gh_calls)" "gh pr checkout $pr/files?w=1
gh pr checkout http://github.com/rails/rails/pull/42#discussion"
}

@test "hub checkout takes a pull request's patch, diff and commit pages" {
  run hub checkout "$pr.patch"
  assert_success
  run hub checkout "$pr.diff" review
  assert_success
  run hub checkout "$pr/commits/abc1234"
  assert_success
  assert_equals "$(gh_calls)" "gh pr checkout $pr.patch
gh pr checkout $pr.diff -b review
gh pr checkout $pr/commits/abc1234"
}

@test "hub checkout gives gh the host of the URL" {
  gh_host_log
  GH_HOST=ghe.example.test run hub checkout https://ghe.example.test/acme/app/pull/3
  assert_success
  GH_HOST=ghe.example.test run hub checkout "$pr"
  assert_success
  GH_HOST=ghe.example.test run hub checkout https://ghe.example.test/acme/app/pull/3 review
  assert_success
  assert_gh_called 'pr checkout https://ghe.example.test/acme/app/pull/3'
  assert_gh_called 'pr checkout https://ghe.example.test/acme/app/pull/3 -b review'
  assert_equals "$(cat "$HUB_TEST_TMP/gh-host.log")" "ghe.example.test
github.com
ghe.example.test"
}

@test "hub checkout relays gh's exit status" {
  stub_gh 'pr checkout *' 'could not find pull request' 4
  run hub checkout "$pr"
  assert_status 4
  assert_output_contains 'could not find pull request'
}

@test "hub checkout refuses -f and --force with a pull request URL" {
  run hub checkout -f "$pr"
  assert_status 1
  assert_output_equals "hub checkout: -f discards local changes in git; gh pr checkout --force \
resets the branch to the pull request instead (run it yourself)"
  run hub checkout "$pr" --force
  assert_status 1
  assert_output_contains 'hub checkout: --force discards local changes in git;'
  assert_gh_not_called
}

@test "hub checkout refuses git's other options with a pull request URL" {
  local word
  for word in -q --track --recurse-submodules=yes --no-detach -db -- --end-of-options; do
    run hub checkout "$pr" "$word"
    assert_status 1
    assert_output_equals \
      'hub checkout: gh pr checkout takes -b BRANCH, --detach and --recurse-submodules only'
  done
  assert_gh_not_called
}

@test "hub checkout refuses an empty branch name" {
  run hub checkout "$pr" ''
  assert_status 1
  assert_output_equals 'hub checkout: the branch name is empty'
  run hub checkout -b '' "$pr"
  assert_status 1
  assert_output_equals 'hub checkout: the branch name is empty'
  assert_gh_not_called
}

@test "hub checkout refuses an empty word before the pull request URL" {
  run hub checkout '' "$pr"
  assert_status 1
  assert_output_equals 'hub checkout: the branch name is empty'
  assert_gh_not_called
}

@test "hub checkout refuses a branch name that git would read as something else" {
  local name
  for name in -f --force --detach - -d HEAD '@{-1}' 'a..b' tags/v9 heads/x refs/heads/x \
    remotes/origin/feature; do
    run hub checkout -b "$name" "$pr"
    assert_status 1
    assert_output_equals "hub checkout: not a valid branch name: $name"
  done
  run hub checkout "$pr" -
  assert_status 1
  assert_output_equals 'hub checkout: not a valid branch name: -'
  run hub checkout "$pr" HEAD
  assert_status 1
  assert_output_equals 'hub checkout: not a valid branch name: HEAD'
  assert_gh_not_called
  assert_equals "$(git for-each-ref --format='%(refname)')" $'refs/heads/main
refs/remotes/origin/HEAD
refs/remotes/origin/main'
}

@test "hub checkout refuses a pull request URL without gh" {
  mkdir "$HUB_TEST_TMP/nogh"
  ln -s "$(command -v git)" "$HUB_TEST_TMP/nogh/git"
  ln -s "$(command -v bash)" "$HUB_TEST_TMP/nogh/bash"
  PATH=$HUB_TEST_TMP/nogh:/usr/bin:/bin run hub checkout "$pr" review
  assert_status 1
  assert_output_equals \
    'hub checkout: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_equals "$(git symbolic-ref HEAD)" refs/heads/main
  assert_equals "$(tip review)" ''
}

@test "hub checkout refuses extra operands, a doubly named branch and -b without a value" {
  run hub checkout main "$pr"
  assert_status 1
  assert_line_equals 0 'hub checkout: unexpected argument: main'
  assert_line_equals 1 \
    'Usage: hub checkout [-b BRANCH] [--detach] [--recurse-submodules] PULL-REQUEST-URL [BRANCH]'
  run hub checkout "$pr" review extra
  assert_status 1
  assert_line_equals 0 'hub checkout: unexpected argument: extra'
  run hub checkout "$pr" "$pr/files"
  assert_status 1
  assert_line_equals 0 "hub checkout: unexpected argument: $pr/files"
  run hub checkout -b one "$pr" two
  assert_status 1
  assert_line_equals 0 'hub checkout: unexpected argument: two (-b names the branch already)'
  run hub checkout "$pr" -b
  assert_status 1
  assert_line_equals 0 'hub checkout: -b needs a branch name'
  run hub checkout -b "$pr"
  assert_status 1
  assert_line_equals 0 'hub checkout: the pull request URL is missing'
  assert_gh_not_called
}

@test "hub checkout hands a line without a pull request URL to git" {
  run hub checkout -q -b topic
  assert_success
  assert_equals "$(git symbolic-ref HEAD)" refs/heads/topic
  run hub checkout -q main
  assert_success
  assert_equals "$(git symbolic-ref HEAD)" refs/heads/main
  assert_equals "$(tip topic)" "$(tip main)"
  assert_gh_not_called
}

@test "hub checkout leaves URLs that are not pull requests to git" {
  local url
  for url in https://github.com/rails/rails/issues/42 https://github.com/rails/rails \
    https://gitlab.com/rails/rails/pull/42 https://github.com/rails/rails/pull/new; do
    run hub checkout "$url"
    assert_failure
    assert_output_contains "error: pathspec '$url' did not match"
  done
  assert_gh_not_called
}

@test "hub checkout leaves a pull request URL after -- or --end-of-options to git" {
  run hub checkout -- "$pr"
  assert_failure
  assert_output_contains "error: pathspec '$pr' did not match"
  run hub checkout --end-of-options "$pr"
  assert_failure
  assert_output_contains "error: pathspec '$pr' did not match"
  assert_gh_not_called
}

@test "hub checkout -h and --help are git's, even with a pull request URL" {
  run hub checkout -h "$pr"
  assert_status 129
  assert_output_contains 'usage: git checkout'
  # git's manual opens a pager or a browser.
  run hub --noop checkout "$pr" --help
  assert_success
  assert_output_equals "git checkout $pr --help"
  assert_gh_not_called
}

@test "hub --noop checkout prints the gh command" {
  run hub --noop checkout "$pr" review
  assert_success
  assert_output_equals "gh pr checkout $pr -b review"
  assert_gh_not_called
}
