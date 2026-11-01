#!/usr/bin/env bats
# hub pull-request: the head where the current branch pushes, the -p push, the message and
# gh pr create.
# Not testable here: gh's prompts and editor themselves (the stub stands in for gh; the
# refusals without a terminal are tested).

load test_helper

# feature_repo [BRANCH] : a clone of mislav/dotfiles on BRANCH (feature), one commit ahead.
feature_repo() {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git checkout -q -b "${1:-feature}"
  git commit -q --allow-empty -m 'Fix the bug' -m 'It was broken.'
}

# fork_repo : origin is octocat/dotfiles, the remote mislav is your fork; on feature.
fork_repo() {
  serve_github octocat/dotfiles mislav/dotfiles
  clone_served octocat/dotfiles
  git remote add mislav https://github.com/mislav/dotfiles.git
  git checkout -q -b feature
  git commit -q --allow-empty -m 'Fix the bug'
}

# record_gh_create : keep the arguments of the last gh pr create call, NUL-separated.
record_gh_create() {
  mkdir -p "$HUB_TEST_TMP/rec"
  cat >"$HUB_TEST_TMP/rec/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == 'pr create' ]]; then printf '%s\0' "$@" >"$HUB_TEST_TMP/gh-create.args"; fi
exec "$HUB_TEST_ROOT/test/stubs/gh" "$@"
EOF
  chmod +x "$HUB_TEST_TMP/rec/gh"
  PATH=$HUB_TEST_TMP/rec:$PATH
}

# create_arg FLAG : the value after FLAG in the recorded gh pr create call.
create_arg() {
  local -a args
  local i
  mapfile -d '' args <"$HUB_TEST_TMP/gh-create.args"
  for ((i = 0; i < ${#args[@]} - 1; i++)); do
    if [[ ${args[i]} == "$1" ]]; then
      printf '%s' "${args[i + 1]}"
      return 0
    fi
  done
  return 1
}

# in_terminal CMD... : run CMD with its standard input and output on a terminal.
in_terminal() {
  if script --version >/dev/null 2>&1; then
    script -qec "$(printf '%q ' "$@")" /dev/null
  else
    script -q /dev/null "$@"
  fi
}

DOTFILES='pr create --repo github.com/mislav/dotfiles'
USAGE='Usage: hub pull-request [-fpdoc] [-b [OWNER[/REPO]:]BASE] [-h [OWNER:]HEAD] [-m MESSAGE]...'

stub_create() { stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/1'; }

# pulls_api HOST/OWNER/REPO HEAD : the gh api call that looks a pull request up by its head.
pulls_api() {
  printf 'api --hostname %s repos/%s/pulls?head=%s&state=open --jq .[0].html_url' \
    "${1%%/*}" "${1#*/}" "$2"
}

# stub_pulls HOST/OWNER/REPO HEAD URL [STATUS] : answer that lookup with URL.
stub_pulls() {
  local glob
  glob=$(pulls_api "$1" "$2")
  glob=${glob//\?/\\?} glob=${glob//[/\\[}
  stub_gh "$glob" "$3" "${4-}"
}

@test "hub pull-request -p pushes a new branch with an upstream and opens the pull request" {
  feature_repo
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(git config branch.feature.remote)" origin
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
  assert_gh_called "$DOTFILES --head feature --title Fix the bug --body "
  assert_output_contains 'https://github.com/mislav/dotfiles/pull/1'
}

@test "hub pull-request -p pushes the branch, not a tag of the same name" {
  feature_repo
  git tag feature HEAD~1
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref mislav/dotfiles refs/tags/feature)" ''
}

@test "hub pull-request -p replaces a start point upstream with the branch on that remote" {
  feature_repo
  git branch -q --set-upstream-to=origin/main feature
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
}

@test "hub pull-request -p pushes again under the upstream it set before" {
  feature_repo
  git push -q -u origin feature
  git commit -q --allow-empty -m 'Fix it more'
  stub_create
  run hub --noop pull-request -p -m 'Fix the bug'
  assert_line_equals 0 'git push -- origin HEAD:refs/heads/feature'
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
}

@test "hub pull-request -p replaces a local upstream with the branch on the push remote" {
  feature_repo
  git branch -q --set-upstream-to=main feature
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(git config branch.feature.remote)" origin
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
}

@test "hub pull-request -p pushes to the fork pushDefault names and keeps the upstream" {
  fork_repo
  git push -q -u origin feature
  git commit -q --allow-empty -m 'Fix it more'
  git config remote.pushDefault mislav
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref octocat/dotfiles refs/heads/feature)" "$(tip feature~1)"
  assert_equals "$(git config branch.feature.remote)" origin
  assert_gh_called 'pr create --repo github.com/octocat/dotfiles --head mislav:feature --title *'
}

@test "hub pull-request -p pushes a new branch to your fork rather than to origin" {
  fork_repo
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches octocat/dotfiles)" main
  assert_equals "$(git config branch.feature.remote)" mislav
  assert_gh_called 'pr create --repo github.com/octocat/dotfiles --head mislav:feature --title *'
}

@test "hub pull-request -p replaces a start point on origin with the branch on your fork" {
  fork_repo
  git branch -q --set-upstream-to=origin/main feature
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(git config branch.feature.remote)" mislav
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
  git commit -q --allow-empty -m 'Fix it more'
  run git push -q
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
}

@test "hub pull-request -p keeps a start point on origin when pushDefault names your fork" {
  fork_repo
  git branch -q --set-upstream-to=origin/main feature
  git config remote.pushDefault mislav
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(git config branch.feature.remote)" origin
  assert_equals "$(git config branch.feature.merge)" refs/heads/main
}

@test "hub pull-request -p pushes to a remote whose name starts with a dash" {
  feature_repo
  git remote add -- --all https://github.com/mislav/dotfiles.git
  git config branch.feature.pushRemote --all
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(git config branch.feature.remote)" --all
}

@test "hub pull-request spells the head's owner as the push URL does" {
  serve_github octocat/dotfiles Mislav/dotfiles
  clone_served octocat/dotfiles
  git remote add fork https://github.com/Mislav/dotfiles.git
  git checkout -q -b feature
  git push -q -u fork feature
  stub_create
  run hub pull-request -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/octocat/dotfiles --head Mislav:feature --title *'
}

@test "hub pull-request names the head without an owner when it is the base, whatever the case" {
  serve_github Octocat/dotfiles
  clone_served Octocat/dotfiles
  git checkout -q -b feature
  git push -q -u origin feature
  stub_gh 'pr create *' ''
  run hub pull-request -b octocat:dev -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/octocat/dotfiles --base dev --head feature *'
}

@test "hub pull-request refuses a branch that is not pushed, or not all of it" {
  feature_repo
  stub_create
  run hub pull-request -m 'Fix the bug'
  assert_status 1
  assert_output_equals \
    'hub pull-request: feature is not pushed to origin (use -p to push it, or -f to skip the check)'
  git push -q -u origin feature
  git commit -q --allow-empty -m 'Two'
  run hub pull-request -m 'Fix the bug'
  assert_status 1
  local expected='hub pull-request: 1 commit of feature is not pushed to origin/feature'
  expected+=' (use -p to push it, or -f to skip the check)'
  assert_output_equals "$expected"
  git commit -q --allow-empty -m 'Three'
  run hub pull-request -m 'Fix the bug'
  assert_status 1
  expected='hub pull-request: 2 commits of feature are not pushed to origin/feature'
  expected+=' (use -p to push them, or -f to skip the check)'
  assert_output_equals "$expected"
  assert_gh_not_called
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature~2)"
}

@test "hub pull-request calls an unborn branch not pushed, also when the remote has its name" {
  feature_repo
  git push -q origin feature
  git checkout -q main
  git branch -q -D feature
  git checkout -q --orphan feature
  stub_create
  run hub pull-request -m 'Fix the bug'
  assert_status 1
  assert_output_equals \
    'hub pull-request: feature is not pushed to origin (use -p to push it, or -f to skip the check)'
  assert_gh_not_called
}

@test "hub pull-request opens the pull request for a pushed branch, and -f skips the check" {
  feature_repo
  git push -q -u origin feature
  stub_create
  run hub pull-request -m 'Fix the bug'
  assert_success
  assert_gh_called "$DOTFILES --head feature --title Fix the bug --body "
  git commit -q --allow-empty -m 'Two'
  : >"$HUB_TEST_GH_LOG"
  run hub pull-request -f -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --head feature *'
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature~1)"
}

@test "hub pull-request -b names the base branch, OWNER's copy or another repository" {
  feature_repo
  git push -q -u origin feature
  stub_gh 'pr create *' ''
  run hub pull-request -b develop -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base develop --head feature *'
  run hub pull-request -b alice:develop -m 'Fix the bug'
  assert_success
  assert_gh_called \
    'pr create --repo github.com/alice/dotfiles --base develop --head mislav:feature *'
  run hub pull-request --base=alice/fork:main -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/alice/fork --base main --head mislav:feature *'
}

@test "hub pull-request refuses a base it cannot read, before anything is pushed" {
  feature_repo
  local base shown
  for base in alice: 'a b:main' -x:main alice/..:main :main $'al\nice:main'; do
    case $base in
      'a b:main') shown='a\ b:main' ;;
      *$'\n'*) shown="\$'al\\nice:main'" ;;
      *) shown=$base ;;
    esac
    run hub pull-request -p -b "$base" -m 'Fix the bug'
    assert_status 1
    assert_line_equals 0 \
      "hub pull-request: not a base: $shown (use -b [OWNER[/REPO]:]BRANCH)"
    assert_output_contains 'Usage: hub pull-request'
  done
  assert_gh_not_called
  assert_equals "$(server_branches mislav/dotfiles)" main
}

@test "hub pull-request refuses an empty -b or -h instead of leaving it to gh" {
  feature_repo
  run hub pull-request -p -b '' -m 'Fix the bug'
  assert_status 1
  assert_line_equals 0 'hub pull-request: -b needs a branch name'
  assert_line_equals 1 "$USAGE"
  run hub pull-request -p --head= -m 'Fix the bug'
  assert_status 1
  assert_line_equals 0 'hub pull-request: --head needs a branch name'
  run hub pull-request --no-edit -h ''
  assert_status 1
  assert_line_equals 0 'hub pull-request: -h needs a branch name'
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request without -b leaves the base to gh, which reads gh-merge-base" {
  feature_repo
  git push -q -u origin feature
  git config branch.feature.gh-merge-base release
  record_gh_create
  stub_create
  run hub pull-request -m 'Fix the bug'
  assert_success
  assert_gh_called "$DOTFILES --head feature --title Fix the bug --body "
  run create_arg --base
  assert_status 1
}

@test "hub pull-request -h names the head as given, unchecked and from a detached HEAD" {
  feature_repo
  git checkout -q --detach
  stub_gh 'pr create *' ''
  run hub pull-request -h alice:topic -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --head alice:topic *'
  run hub pull-request --head=topic -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --head topic *'
}

@test "hub pull-request -h works under GH_REPO outside a repository" {
  stub_gh 'pr create *' ''
  GH_REPO=octocat/dotfiles run hub pull-request -h mislav:topic -m 'Fix the bug'
  assert_success
  assert_gh_called \
    'GH_REPO=octocat/dotfiles gh pr create --repo github.com/octocat/dotfiles --head mislav:topic *'
}

@test "hub pull-request under GH_REPO names the head with its owner when it is not the base" {
  feature_repo
  git push -q -u origin feature
  stub_create
  GH_REPO=octocat/dotfiles run hub pull-request -m 'Fix the bug'
  assert_success
  local expected='GH_REPO=octocat/dotfiles gh pr create --repo github.com/octocat/dotfiles'
  assert_gh_called "$expected --head mislav:feature --title Fix the bug --body "
}

@test "hub pull-request outside a work tree without -h relays git's refusal" {
  mkdir plain
  cd plain
  run hub pull-request -f -m 'Fix the bug'
  assert_status 1
  assert_output_equals 'fatal: not a git repository (or any of the parent directories): .git'
  assert_gh_not_called
}

@test "hub pull-request refuses a detached HEAD without -h" {
  feature_repo
  git checkout -q --detach
  run hub pull-request -p -m 'Fix the bug'
  assert_status 1
  assert_output_equals \
    'hub pull-request: not on a branch (name the head with -h [OWNER:]BRANCH)'
  assert_gh_not_called
}

@test "hub pull-request refuses -p with -h" {
  feature_repo
  run hub pull-request -p -h feature -m 'Fix the bug'
  assert_status 1
  assert_output_equals \
    'hub pull-request: -p pushes the current branch (push the head yourself, and name it with -h)'
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request refuses a branch whose push remote it cannot tell" {
  serve_github octocat/dotfiles alice/dotfiles
  make_repo work upstream=https://github.com/octocat/dotfiles.git \
    alice=https://github.com/alice/dotfiles.git
  git checkout -q -b feature
  run hub pull-request -p -m 'Fix the bug'
  assert_status 1
  local expected='hub pull-request: cannot tell where feature pushes'
  expected+=' (git push -u REMOTE feature first, or name the head with -h)'
  assert_output_equals "$expected"
  assert_equals "$(server_branches octocat/dotfiles)" main
  assert_equals "$(server_branches alice/dotfiles)" main
}

@test "hub pull-request refuses a push remote that is not on GitHub or on another host" {
  serve_github octocat/dotfiles
  git init -q --bare elsewhere.git
  make_repo work upstream=https://github.com/octocat/dotfiles.git \
    origin="$HUB_TEST_TMP/elsewhere.git"
  run hub pull-request -p -m 'Fix the bug'
  assert_status 1
  assert_output_equals \
    'hub pull-request: origin does not push to a GitHub repository (name the head with -h)'
  git remote set-url origin https://ghe.example.com/mislav/dotfiles.git
  stub_gh 'config get user -h ghe.example.com' mislav
  GH_HOST=ghe.example.com run hub pull-request -p -m 'Fix the bug'
  assert_status 1
  assert_output_equals \
    'hub pull-request: origin pushes to ghe.example.com, not to github.com (name the head with -h)'
  assert_equals "$(server_branches octocat/dotfiles)" main
  assert_equals "$(gh_calls | grep -c 'pr create')" 0
}

@test "hub pull-request names the host of the project in every gh call" {
  serve_github ghe.example.com/mislav/dotfiles
  clone_served ghe.example.com/mislav/dotfiles
  git checkout -q -b feature
  stub_gh 'pr create *' ''
  stub_pulls ghe.example.com/mislav/dotfiles mislav:feature \
    'https://ghe.example.com/mislav/dotfiles/pull/2'
  GH_HOST=ghe.example.com run hub pull-request -p -o -m 'Fix the bug'
  assert_success
  assert_equals "$(server_ref ghe.example.com/mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_gh_called 'pr create --repo ghe.example.com/mislav/dotfiles --head feature *'
  assert_equals "$(gh_calls | tail -n 1)" \
    "gh $(pulls_api ghe.example.com/mislav/dotfiles mislav:feature)"
  assert_equals "$(opened)" 'https://ghe.example.com/mislav/dotfiles/pull/2'
}

@test "hub pull-request takes the title from the first paragraph and keeps the body as written" {
  feature_repo
  git push -q -u origin feature
  record_gh_create
  stub_create
  run hub pull-request -m $'Fix\nthe bug' -m $'\n    code one\n    code two\n' -m 'Done.'
  assert_success
  assert_equals "$(create_arg --title)" 'Fix the bug'
  assert_equals "$(create_arg --body)" $'    code one\n    code two\n\n\nDone.'
  printf '\n\nFix the bug\n\n\n  indented\nsecond\n\n\n' >message.txt
  mkdir sub
  cd sub
  run hub pull-request -F ../message.txt
  assert_success
  assert_equals "$(create_arg --title)" 'Fix the bug'
  assert_equals "$(create_arg --body)" $'  indented\nsecond'
}

@test "hub pull-request joins the title's lines trimmed and drops carriage returns" {
  feature_repo
  git push -q -u origin feature
  record_gh_create
  stub_create
  run hub pull-request -m $'  Fix\t\n   the bug  '
  assert_success
  assert_equals "$(create_arg --title)" 'Fix the bug'
  printf 'Fix\r\nthe bug\r\n\r\n  body\r\nend\r\n' >message.txt
  run hub pull-request -F message.txt
  assert_success
  assert_equals "$(create_arg --title)" 'Fix the bug'
  assert_equals "$(create_arg --body)" $'  body\nend'
}

@test "hub pull-request -F - reads the message from standard input" {
  feature_repo
  git push -q -u origin feature
  record_gh_create
  stub_create
  run hub pull-request -F - <<<$'Fix the bug\n\nIt was broken.'
  assert_success
  assert_equals "$(create_arg --title)" 'Fix the bug'
  assert_equals "$(create_arg --body)" 'It was broken.'
}

@test "hub pull-request -e opens gh's editor in a terminal, with the message when one is given" {
  feature_repo
  git push -q -u origin feature
  unset GH_PROMPT_DISABLED
  record_gh_create
  stub_create
  run in_terminal "$HUB_BIN" pull-request -e </dev/null
  assert_success
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --head feature --editor'
  run in_terminal "$HUB_BIN" pull-request --edit -m 'Fix the bug' </dev/null
  assert_success
  assert_gh_called 'pr create --repo * --head feature --title Fix the bug --body  --editor'
  run in_terminal "$HUB_BIN" pull-request -e -m '' </dev/null
  assert_success
  assert_equals "$(gh_calls | tail -n 1)" \
    'gh pr create --repo github.com/mislav/dotfiles --head feature --editor'
  printf 'Fix the bug\n\nIt was broken.\n' >message.txt
  run in_terminal "$HUB_BIN" pull-request -e -F message.txt </dev/null
  assert_success
  assert_equals "$(create_arg --title)" 'Fix the bug'
  assert_equals "$(create_arg --body)" 'It was broken.'
  assert_equals "$(gh_calls | tail -n 1)" \
    "gh $DOTFILES --head feature --title Fix the bug --body It was broken. --editor"
}

@test "hub pull-request -e without a terminal refuses before pushing, as gh would" {
  feature_repo
  stub_create
  local expected="hub pull-request: -e opens gh's editor, which needs a terminal"
  expected+=' (give the message with -m or -F)'
  run hub pull-request -p -e -m 'Fix the bug' </dev/null
  assert_status 1
  assert_output_equals "$expected"
  run in_terminal "$HUB_BIN" pull-request -p -e -m 'Fix the bug' </dev/null
  assert_status 1
  assert_output_contains "$expected"
  unset GH_PROMPT_DISABLED
  run in_terminal bash -o pipefail -c '"$HUB_BIN" pull-request -p -e -m Fix | cat' </dev/null
  assert_status 1
  assert_output_contains "$expected"
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request --no-edit lets gh take the first commit's message" {
  feature_repo
  git push -q -u origin feature
  stub_create
  run hub pull-request --no-edit
  assert_success
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --head feature --fill-first'
}

@test "hub pull-request refuses an empty title and an unreadable file before pushing" {
  feature_repo
  run hub pull-request -p -m ''
  assert_status 1
  assert_output_equals 'hub pull-request: the title is empty (give it with -m or -F)'
  run hub pull-request -p -F missing.txt
  assert_status 1
  assert_line_equals 1 'hub pull-request: cannot read the message from missing.txt'
  mkdir dir
  run hub pull-request -p -F dir
  assert_status 1
  assert_output_contains 'hub pull-request: cannot read the message from dir'
  run hub pull-request -p -F $'no\nsuch'
  assert_status 1
  assert_output_contains "hub pull-request: cannot read the message from \$'no\\nsuch'"
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request without a message and without a terminal refuses before pushing" {
  feature_repo
  run hub pull-request -p </dev/null
  assert_status 1
  local expected='hub pull-request: gh prompts for the title and body, which needs a terminal'
  expected+=' (give the message with -m or -F)'
  assert_output_equals "$expected"
  run in_terminal "$HUB_BIN" pull-request -p </dev/null
  assert_status 1
  assert_output_contains "$expected"
  unset GH_PROMPT_DISABLED
  run hub pull-request -p </dev/null
  assert_status 1
  assert_output_equals "$expected"
  run in_terminal bash -o pipefail -c '"$HUB_BIN" pull-request -p | cat' </dev/null
  assert_status 1
  assert_output_contains "$expected"
  run in_terminal bash -c '"$HUB_BIN" pull-request -p </dev/null' </dev/null
  assert_status 1
  assert_output_contains "$expected"
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request without a message in a terminal leaves the prompts to gh" {
  feature_repo
  unset GH_PROMPT_DISABLED
  stub_create
  stub_gh 'config get prompt' enabled
  run in_terminal "$HUB_BIN" pull-request -p </dev/null
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_equals "$(gh_calls)" \
    $'gh config get prompt\ngh pr create --repo github.com/mislav/dotfiles --head feature'
}

@test "hub pull-request refuses before pushing when gh's configuration disables prompts" {
  feature_repo
  unset GH_PROMPT_DISABLED
  stub_gh 'config get prompt' disabled
  stub_create
  local expected='hub pull-request: gh prompts for the title and body, which needs a terminal'
  expected+=' (give the message with -m or -F)'
  run in_terminal "$HUB_BIN" pull-request -p </dev/null
  assert_status 1
  assert_output_contains "$expected"
  expected="hub pull-request: -e opens gh's editor, which needs a terminal"
  expected+=' (give the message with -m or -F)'
  run in_terminal "$HUB_BIN" pull-request -p -e -m 'Fix the bug' </dev/null
  assert_status 1
  assert_output_contains "$expected"
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_equals "$(gh_calls)" $'gh config get prompt\ngh config get prompt'
}

@test "hub pull-request asks gh's prompt setting only when gh would prompt" {
  feature_repo
  git push -q -u origin feature
  unset GH_PROMPT_DISABLED
  stub_gh 'config get prompt' disabled
  stub_create
  run in_terminal "$HUB_BIN" pull-request -m 'Fix the bug' </dev/null
  assert_success
  run in_terminal "$HUB_BIN" pull-request --no-edit </dev/null
  assert_success
  assert_equals "$(gh_calls | grep -c 'config get prompt')" 0
}

@test "hub pull-request refuses message options that contradict each other" {
  feature_repo
  run hub pull-request -p -m Fix -F message.txt
  assert_status 1
  assert_line_equals 0 'hub pull-request: -m and -F cannot be combined'
  assert_line_equals 1 "$USAGE"
  run hub pull-request -p -e --no-edit
  assert_status 1
  assert_line_equals 0 'hub pull-request: -e and --no-edit cannot be combined'
  assert_line_equals 1 "$USAGE"
  run hub pull-request -p --no-edit -m Fix
  assert_status 1
  assert_line_equals 0 \
    'hub pull-request: --no-edit takes the message from the first commit (drop -m and -F)'
  assert_line_equals 1 "$USAGE"
  run hub pull-request -p -F ''
  assert_status 1
  assert_line_equals 0 'hub pull-request: -F needs a file name'
  assert_line_equals 1 "$USAGE"
  run hub pull-request --no-edit -h feature
  assert_status 1
  assert_line_equals 0 \
    'hub pull-request: --no-edit cannot be used with -h (give the message with -m or -F)'
  assert_line_equals 1 "$USAGE"
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request passes draft, reviewers, assignees, milestone and labels to gh" {
  feature_repo
  git push -q -u origin feature
  record_gh_create
  stub_create
  run hub pull-request -l bug,ui -r alice,org/team -d -a bob -M 'Version 1.0' -r carol \
    --no-maintainer-edits -l 'good first issue' -b 'release 1' -m 'Fix the bug'
  assert_success
  local expected="$DOTFILES --base release 1 --head feature --title Fix the bug --body  --draft"
  expected+=' --reviewer alice,org/team --reviewer carol --assignee bob --milestone Version 1.0'
  expected+=' --label bug,ui --label good first issue --no-maintainer-edit'
  assert_gh_called "$expected"
  assert_equals "$(create_arg --milestone)" 'Version 1.0'
  assert_equals "$(create_arg --base)" 'release 1'
  local -a args
  mapfile -d '' args <"$HUB_TEST_TMP/gh-create.args"
  assert_equals "${#args[@]}" 26
  assert_equals "${args[24]}" 'good first issue'
}

@test "hub pull-request reads long, attached and clustered option spellings alike" {
  feature_repo
  git push -q -u origin feature
  stub_create
  run hub pull-request --draft --reviewer=alice --assign bob --milestone v1 --labels=bug \
    --message 'Fix the bug' --base=develop
  assert_success
  local expected="$DOTFILES --base develop --head feature --title Fix the bug --body  --draft"
  expected+=' --reviewer alice --assignee bob --milestone v1 --label bug'
  assert_gh_called "$expected"
  : >"$HUB_TEST_GH_LOG"
  run hub pull-request -dralice -abob -Mv1 -lbug -bdevelop -m'Fix the bug'
  assert_success
  assert_gh_called "$expected"
  run hub pull-request --message '-pd'
  assert_success
  assert_gh_called 'pr create --repo * --head feature --title -pd --body '
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(tip feature)"
}

@test "hub pull-request -o and -c open and copy the URL gh reports afterwards" {
  feature_repo
  git push -q -u origin feature
  stub_create
  stub_pulls github.com/mislav/dotfiles mislav:feature 'https://github.com/mislav/dotfiles/pull/1'
  run hub pull-request -o -c -m 'Fix the bug'
  assert_success
  assert_equals "$(opened)" 'https://github.com/mislav/dotfiles/pull/1'
  assert_equals "$(copied)" 'https://github.com/mislav/dotfiles/pull/1'
}

@test "hub pull-request -o and -c look a numeric branch up by its head, not as a number" {
  feature_repo 123
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/456'
  stub_gh 'pr view *' 'https://github.com/mislav/dotfiles/pull/123'
  stub_pulls github.com/mislav/dotfiles mislav:123 'https://github.com/mislav/dotfiles/pull/456'
  run hub pull-request -f -o -c -m 'Fix the bug'
  assert_success
  assert_equals "$(opened)" 'https://github.com/mislav/dotfiles/pull/456'
  assert_equals "$(copied)" 'https://github.com/mislav/dotfiles/pull/456'
  assert_equals "$(gh_calls | grep -c 'pr view')" 0
}

@test "hub pull-request -o looks a fork's head up under the fork's owner" {
  fork_repo
  git push -q -u mislav feature
  stub_create
  stub_pulls github.com/octocat/dotfiles mislav:feature \
    'https://github.com/octocat/dotfiles/pull/3'
  run hub pull-request -o -m 'Fix the bug'
  assert_success
  assert_gh_called 'pr create --repo github.com/octocat/dotfiles --head mislav:feature *'
  assert_equals "$(opened)" 'https://github.com/octocat/dotfiles/pull/3'
  rm "$HUB_TEST_TMP/browser.log"
  stub_pulls github.com/octocat/dotfiles alice:a%2Bb%23c \
    'https://github.com/octocat/dotfiles/pull/4'
  run hub pull-request -h 'alice:a+b#c' -o -m 'Fix the bug'
  assert_success
  assert_equals "$(opened)" 'https://github.com/octocat/dotfiles/pull/4'
}

@test "hub pull-request -o still opens the browser when -c finds no clipboard tool" {
  feature_repo
  git push -q -u origin feature
  stub_create
  stub_pulls github.com/mislav/dotfiles mislav:feature 'https://github.com/mislav/dotfiles/pull/1'
  local bin=$HUB_TEST_TMP/noclip dir
  local -a dirs
  mkdir "$bin"
  IFS=: read -ra dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    if [[ -d $dir ]]; then ln -s "$dir"/* "$bin"/ 2>/dev/null || true; fi
  done
  rm -f "$bin/pbcopy" "$bin/wl-copy" "$bin/xclip"
  PATH=$bin run hub pull-request -o -c -m 'Fix the bug'
  assert_status 1
  assert_output_contains 'hub pull-request: no clipboard tool found'
  assert_equals "$(opened)" 'https://github.com/mislav/dotfiles/pull/1'
}

@test "hub pull-request --noop -o -c prints the lookup, the copy and the open" {
  feature_repo
  run hub --noop pull-request -f -o -c -m 'Fix the bug'
  assert_success
  local expected='gh api --hostname github.com'
  expected+=' repos/mislav/dotfiles/pulls\?head=mislav:feature\&state=open --jq .\[0\].html_url'
  assert_line_equals 1 "$expected"
  assert_line_equals 2 'copy URL'
  assert_line_equals 3 'open URL'
  assert_gh_not_called
  assert_equals "$(opened)" ''
  assert_equals "$(copied)" ''
}

@test "hub pull-request returns the browser's or clipboard's failure after the URL was shown" {
  feature_repo
  git push -q -u origin feature
  stub_create
  stub_pulls github.com/mislav/dotfiles mislav:feature 'https://github.com/mislav/dotfiles/pull/1'
  HUB_TEST_BROWSER_STATUS=19 run hub pull-request -o -m 'Fix the bug'
  assert_status 19
  assert_output_contains 'https://github.com/mislav/dotfiles/pull/1'
  rm "$HUB_TEST_TMP/browser.log"
  HUB_TEST_CLIPBOARD_STATUS=17 run hub pull-request -o -c -m 'Fix the bug'
  assert_status 17
  assert_equals "$(opened)" 'https://github.com/mislav/dotfiles/pull/1'
}

@test "hub pull-request stops with gh's status when gh pr create fails, and opens nothing" {
  feature_repo
  git push -q -u origin feature
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/1' 4
  run hub pull-request -o -m 'Fix the bug'
  assert_status 4
  assert_equals "$(gh_calls | grep -c 'api')" 0
  assert_equals "$(opened)" ''
}

@test "hub pull-request claims nothing when no open pull request is found after gh pr create" {
  feature_repo
  git push -q -u origin feature
  stub_create
  stub_pulls github.com/mislav/dotfiles mislav:feature 'null'
  run hub pull-request -o -m 'Fix the bug'
  assert_status 1
  local expected='hub pull-request: no open pull request from feature was found after gh pr'
  expected+=" create (gh api --hostname github.com 'repos/mislav/dotfiles/pulls?head=mislav:feature"
  expected+="&state=open')"
  assert_output_contains "$expected"
  assert_equals "$(opened)" ''
}

@test "hub pull-request relays git's refusal to push to a mirror remote" {
  feature_repo
  git config remote.origin.mirror true
  stub_create
  run hub pull-request -p -m 'Fix the bug'
  assert_failure
  assert_output_contains '--mirror'
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request without gh refuses before pushing" {
  feature_repo
  PATH=$(no_gh_path) run hub pull-request -p -m 'Fix the bug'
  assert_status 1
  assert_output_equals \
    'hub pull-request: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_equals "$(server_branches mislav/dotfiles)" main
}

@test "hub pull-request --noop prints the push and gh pr create, and pushes nothing" {
  feature_repo
  run hub --noop pull-request -p -m 'Fix the bug'
  assert_success
  assert_line_equals 0 'git push --set-upstream -- origin HEAD:refs/heads/feature'
  assert_line_equals 1 \
    "gh $DOTFILES --head feature --title Fix\\ the\\ bug --body ''"
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request refuses unknown options, operands and missing values" {
  feature_repo
  run hub pull-request -p --fill
  assert_status 1
  assert_line_equals 0 'hub pull-request: unknown option: --fill'
  assert_line_equals 1 "$USAGE"
  run hub pull-request -pw
  assert_status 1
  assert_line_equals 0 'hub pull-request: unknown option: -w'
  run hub pull-request -p https://github.com/mislav/dotfiles/issues/1
  assert_status 1
  assert_line_equals 0 \
    'hub pull-request: unexpected argument: https://github.com/mislav/dotfiles/issues/1'
  run hub pull-request -p -- extra
  assert_status 1
  assert_line_equals 0 'hub pull-request: unexpected argument: extra'
  run hub pull-request -p -m
  assert_status 1
  assert_line_equals 0 'hub pull-request: -m needs a value'
  run hub pull-request -p --head
  assert_status 1
  assert_line_equals 0 'hub pull-request: --head needs a value'
  run hub pull-request -p -h
  assert_status 1
  assert_line_equals 0 'hub pull-request: -h needs a value'
  assert_line_equals 1 "$USAGE"
  run hub pull-request -p -i 12
  assert_status 1
  local expected='hub pull-request: -i is not supported (use gh api to attach a pull request'
  assert_line_equals 0 "$expected to an issue, or link it in the body)"
  assert_equals "$(server_branches mislav/dotfiles)" main
  assert_gh_not_called
}

@test "hub pull-request --help prints the manual" {
  run hub pull-request --help
  assert_success
  assert_line_equals 0 'Summary: Open a pull request for the current branch.'
  assert_gh_not_called
}
