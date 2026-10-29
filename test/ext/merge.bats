#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12
MSG=$'Merge pull request #12 from jingweno/fix-build\n\nFix the build'
JQ='"Merge pull request #\(.number) from \(.headRepositoryOwner.login)/\(.headRefName)\n\n\(.title)"'

# stub_pr_message [URL] : gh pr view answers with the merge message for the pull request.
stub_pr_message() {
  stub_gh "pr view ${1:-$PR} --json number,title,headRepositoryOwner,headRefName --jq *" "${MSG//$'\n'/\\n}"
}

# merge_line [ARGS...] : the git merge command hub prints for the pull request (ARGS shell-quoted).
merge_line() {
  local out='git merge FETCH_HEAD' arg
  for arg in "$@"; do out+=" $(printf '%q' "$arg")"; done
  printf '%s\n' "$out"
}

@test "merge of a pull request URL fetches its head from the base remote and merges it locally" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_pr_message
  run hub --noop merge "$PR"
  assert_success
  assert_output_equals "git fetch origin refs/pull/12/head
$(merge_line --no-ff -m "$MSG")"
  [[ $(gh_calls) == "gh pr view $PR --json number,title,headRepositoryOwner,headRefName --jq $JQ" ]]
}

@test "merge never merges on GitHub" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_pr_message
  run hub --noop merge "$PR"
  assert_success
  [[ $(gh_calls) != *"pr merge"* ]]
}

@test "merge fetches from whichever remote points at the pull request's repository" {
  make_repo dotfiles origin=https://github.com/me/dotfiles.git upstream=git@github.com:Mislav/DotFiles.git
  stub_pr_message
  run hub --noop merge "$PR"
  assert_success
  assert_line_equals 0 "git fetch upstream refs/pull/12/head"
}

@test "merge fetches from the repository's URL when no remote points at it" {
  make_repo dotfiles origin=https://github.com/me/dotfiles.git
  stub_pr_message
  run hub --noop merge "$PR"
  assert_success
  assert_line_equals 0 "git fetch https://github.com/mislav/dotfiles.git refs/pull/12/head"
  git config --global hub.protocol ssh
  run hub --noop merge "$PR"
  assert_line_equals 0 "git fetch git@github.com:mislav/dotfiles.git refs/pull/12/head"
}

@test "merge matches remotes by host too" {
  git config --global hub.host ghe.example.com
  make_repo app origin=https://github.com/team/app.git work=git@ghe.example.com:team/app.git
  stub_pr_message https://ghe.example.com/team/app/pull/7
  run hub --noop merge https://ghe.example.com/team/app/pull/7
  assert_success
  assert_line_equals 0 "git fetch work refs/pull/7/head"
  git remote remove work
  run hub --noop merge https://ghe.example.com/team/app/pull/7
  assert_line_equals 0 "git fetch https://ghe.example.com/team/app.git refs/pull/7/head"
}

@test "merge drops --no-ff when --ff, --ff-only or --squash is given" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_pr_message
  local flag
  for flag in --ff-only --ff --squash; do
    run hub --noop merge "$flag" "$PR"
    assert_success
    assert_line_equals 1 "$(merge_line -m "$MSG" "$flag")"
  done
  run hub --noop merge "$PR" --no-ff
  assert_line_equals 1 "$(merge_line -m "$MSG" --no-ff)"
}

@test "merge passes other git-merge options on" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_pr_message
  run hub --noop merge --no-edit -s ort -X theirs "$PR" -S
  assert_success
  assert_line_equals 1 "$(merge_line --no-ff -m "$MSG" --no-edit -s ort -X theirs -S)"
}

@test "merge with -m or -F keeps that message and doesn't ask gh" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop merge -m "Bring in the fix" "$PR"
  assert_success
  assert_output_equals "git fetch origin refs/pull/12/head
$(merge_line --no-ff -m "Bring in the fix")"
  run hub --noop merge "$PR" --file=msg.txt
  assert_success
  assert_line_equals 1 "$(merge_line --no-ff --file=msg.txt)"
  assert_gh_not_called
}

@test "merge doesn't mistake a message that is a URL for the pull request" {
  run hub --noop merge -m "$PR" topic
  assert_success
  assert_output_equals "git merge -m $PR topic"
  assert_gh_not_called
}

@test "merge without a pull request URL is plain git merge" {
  run hub --noop merge topic
  assert_success
  assert_output_equals "git merge topic"
  run hub --noop merge --abort
  assert_output_equals "git merge --abort"
  run hub --noop merge -h
  assert_output_equals "git merge -h"
  run hub --noop merge https://github.com/mislav/dotfiles/commit/abc1234
  assert_output_equals "git merge https://github.com/mislav/dotfiles/commit/abc1234"
  assert_gh_not_called
}

@test "merge really runs git merge" {
  make_repo dotfiles
  git checkout -q -b topic
  git commit -q --allow-empty -m "topic work"
  git checkout -q main
  run hub merge -q --no-ff --no-edit topic
  assert_success
  [[ $(git rev-parse HEAD^2) == $(git rev-parse topic) ]]
  assert_gh_not_called
}

@test "merge of a pull request URL together with other commits is refused" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop merge "$PR" topic
  assert_failure
  assert_output_contains "Aborted: a pull request URL can't be merged together with other commits (topic)"
  assert_gh_not_called
}

@test "merge aborts before fetching when the pull request can't be looked up" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh "pr view $PR *" '' 1
  run hub --noop merge "$PR"
  assert_failure
  assert_output_equals "Aborted: could not look up pull request $PR"
}

@test "merge of a pull request URL outside a repository aborts" {
  run hub --noop merge "$PR"
  assert_failure
  assert_output_contains "not a git repository"
  assert_gh_not_called
}

@test "merge of a pull request URL really merges its head with the merge button's message" {
  # The base repository on "GitHub": main, plus the pull request's head at refs/pull/12/head.
  git init -q --bare "$HUB_TEST_TMP/dotfiles.git"
  make_repo seed origin="$HUB_TEST_TMP/dotfiles.git"
  git push -q origin main
  git checkout -q -b fix-build
  echo fixed >build.txt && git add build.txt && git commit -q -m "Fix the build"
  git push -q origin fix-build:refs/pull/12/head
  local head
  head=$(git rev-parse HEAD)
  git clone -q "$HUB_TEST_TMP/dotfiles.git" "$HUB_TEST_TMP/work"
  cd "$HUB_TEST_TMP/work"
  git config --global url."$HUB_TEST_TMP/dotfiles.git".insteadOf https://github.com/mislav/dotfiles.git
  stub_pr_message
  run hub merge "$PR"
  assert_success
  [[ $(git rev-parse HEAD^2) == "$head" ]]
  [[ $(git log -1 --format=%B) == "$MSG" ]]
  [[ $(git symbolic-ref --short HEAD) == main && -f build.txt ]]
}

@test "merge --help prints the manual" {
  run hub merge --help
  assert_success
  assert_output_contains "Usage: hub merge PULLREQ-URL [git-merge options]"
}
