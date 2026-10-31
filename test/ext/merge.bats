#!/usr/bin/env bats
load ../test_helper

PR=https://github.com/mislav/dotfiles/pull/12
MSG=$'Merge pull request #12 from jingweno/fix-build\n\nFix the build'
JQ='"Merge pull request #\(.number) from \(.headRepositoryOwner.login)/\(.headRefName)\n\n\(.title)"'

# stub_pr_message [URL] : gh pr view answers with the merge message for the pull request.
stub_pr_message() {
  stub_gh "pr view ${1:-$PR} --json number,title,headRepositoryOwner,headRefName --jq *" "${MSG//$'\n'/\\n}"
}

# make_pr_fixture : github.com/mislav/dotfiles with main and pull request #12 (refs/pull/12/head: one commit
# on top of main adding build.txt), and "work", a clone of it on main, left as the current directory.
# Sets PR_HEAD to the pull request's commit.
make_pr_fixture() {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles seed
  git switch -q -c fix-build
  echo fixed >build.txt && git add build.txt && git commit -q -m "Fix the build"
  git push -q origin HEAD:refs/pull/12/head
  PR_HEAD=$(git rev-parse HEAD)
  cd .. && clone_served mislav/dotfiles work
}

# make_topic : a local branch topic with one commit (adding topic.txt), and a commit on main that is not on
# topic, so that merging topic takes a merge commit; main stays checked out.
make_topic() {
  git switch -q -c topic
  echo topic >topic.txt && git add topic.txt && git commit -q -m "topic work"
  git switch -q main
  echo main >main.txt && git add main.txt && git commit -q -m "main work"
}

# parents REV : the parent hashes of a commit, space-separated.
parents() { git rev-list --parents -n 1 "$1" | cut -d' ' -f2-; }

# assert_no_leftovers : no private ref of hub's and no merge in progress.
assert_no_leftovers() {
  [[ -z $(git for-each-ref refs/hub) ]] || {
    printf 'refs left behind:\n%s\n' "$(git for-each-ref refs/hub)"
    return 1
  }
  [[ ! -e $(git rev-parse --git-dir)/MERGE_HEAD ]]
}

@test "merge of a pull request URL fetches its head from the base remote and merges it with the merge button's message" {
  make_pr_fixture
  stub_pr_message
  local main
  main=$(git rev-parse HEAD)
  run hub merge "$PR"
  assert_success
  assert_equals "$(parents HEAD)" "$main $PR_HEAD"
  assert_equals "$(git log -1 --format=%B)" "$MSG"
  [[ $(git symbolic-ref --short HEAD) == main && $(cat build.txt) == fixed && -z $(git status --porcelain) ]]
  assert_no_leftovers
  [[ $(gh_calls) == "gh pr view $PR --json number,title,headRepositoryOwner,headRefName --jq $JQ" ]]
  # nothing was pushed: merging on GitHub is gh pr merge's job
  [[ -z $(server_ref mislav/dotfiles HEAD^2) ]]
  assert_equals "$(server_ref mislav/dotfiles main)" "$main"
}

@test "merge --noop shows the fetch into a private ref, the merge of it and the cleanup, and changes nothing" {
  make_pr_fixture
  stub_pr_message
  run hub --noop merge "$PR"
  assert_success
  [[ ${#lines[@]} -eq 3 ]]
  [[ ${lines[0]} =~ ^git\ fetch\ --no-tags\ --refmap=\ origin\ \+refs/pull/12/head:(refs/hub/merge/12-[0-9]+)$ ]]
  local ref=${BASH_REMATCH[1]}
  assert_line_equals 1 "git merge --no-ff -m $(printf '%q' "$MSG") $ref"
  assert_line_equals 2 "git update-ref -d $ref"
  assert_equals "$(git rev-parse HEAD)" "$(server_ref mislav/dotfiles main)"
  assert_no_leftovers
}

@test "merge fetches from whichever remote points at the pull request's repository, over any protocol" {
  make_pr_fixture
  git remote rename origin fork
  git remote set-url fork https://github.com/me/dotfiles.git
  git remote add upstream git@github.com:mislav/dotfiles.git
  stub_pr_message
  run hub merge "$PR"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$PR_HEAD"
  assert_no_leftovers
  # the match ignores case, as GitHub does
  git remote set-url upstream git@github.com:Mislav/DotFiles.git
  run hub --noop merge "$PR"
  assert_success
  [[ ${lines[0]} == "git fetch --no-tags --refmap= upstream +refs/pull/12/head:refs/hub/merge/12-"* ]]
}

@test "merge fetches from the repository's URL when no remote points at it" {
  make_pr_fixture
  git remote set-url origin https://github.com/me/dotfiles.git
  stub_pr_message
  run hub merge "$PR"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$PR_HEAD"
  assert_no_leftovers
  git config --global hub.protocol ssh
  run hub --noop merge "$PR"
  assert_success
  [[ ${lines[0]} == "git fetch --no-tags --refmap= git@github.com:mislav/dotfiles.git +refs/pull/12/head:refs/hub/merge/12-"* ]]
}

@test "merge matches remotes by host too" {
  git config --global hub.host ghe.example.com
  make_repo app origin=https://github.com/team/app.git work=git@ghe.example.com:team/app.git
  stub_pr_message https://ghe.example.com/team/app/pull/7
  run hub --noop merge https://ghe.example.com/team/app/pull/7
  assert_success
  [[ ${lines[0]} == "git fetch --no-tags --refmap= work +refs/pull/7/head:refs/hub/merge/7-"* ]]
  git remote remove work
  run hub --noop merge https://ghe.example.com/team/app/pull/7
  assert_success
  [[ ${lines[0]} == "git fetch --no-tags --refmap= https://ghe.example.com/team/app.git +refs/pull/7/head:refs/hub/merge/7-"* ]]
}

@test "merge merges the commit it fetched, not what another fetch left in FETCH_HEAD meanwhile" {
  make_pr_fixture
  # an unrelated branch on github.com, which another process fetches between hub's fetch and its merge
  (cd "$HUB_TEST_TMP/seed" && git switch -q -c unrelated main && echo u >unrelated.txt && git add unrelated.txt \
    && git commit -q -m "unrelated work" && git push -q origin unrelated)
  local unrelated
  unrelated=$(server_ref mislav/dotfiles unrelated)
  stub_pr_message
  shim_git 'merge --no-ff *' 'git fetch -q origin refs/heads/unrelated'
  PATH=$SHIM_PATH run hub merge "$PR"
  assert_success
  [[ $(cut -c1-40 .git/FETCH_HEAD) == "$unrelated" ]] # the other fetch did happen
  assert_equals "$(git rev-parse HEAD^2)" "$PR_HEAD"
  assert_equals "$(git log -1 --format=%B)" "$MSG"
  [[ -f build.txt && ! -e unrelated.txt ]]
  assert_no_leftovers
}

@test "merge cleans up its private ref when the merge fails, leaving the merge in progress to resolve" {
  make_pr_fixture
  echo conflicting >build.txt && git add build.txt && git commit -q -m "another build.txt"
  stub_pr_message
  run hub merge "$PR"
  assert_failure
  assert_output_contains "CONFLICT"
  [[ -z $(git for-each-ref refs/hub) ]]
  assert_equals "$(git rev-parse MERGE_HEAD)" "$PR_HEAD"
  git merge --abort
  assert_no_leftovers
}

@test "merge aborts before fetching when the pull request can't be looked up" {
  make_pr_fixture
  stub_gh "pr view $PR *" '' 1
  run hub merge "$PR"
  assert_failure
  assert_output_equals "Aborted: could not look up pull request $PR"
  [[ ! -e .git/FETCH_HEAD ]]
  assert_no_leftovers
}

@test "merge --ff, --ff-only and --no-ff set the fast-forward behavior instead of hub's --no-ff" {
  make_pr_fixture
  stub_pr_message
  local main
  main=$(git rev-parse HEAD)
  run hub merge --ff-only "$PR"
  assert_success
  assert_equals "$(git rev-parse HEAD)" "$PR_HEAD"
  git reset -q --hard "$main"
  run hub merge "$PR" --ff
  assert_success
  assert_equals "$(git rev-parse HEAD)" "$PR_HEAD"
  git reset -q --hard "$main"
  run hub merge --no-ff "$PR"
  assert_success
  assert_equals "$(parents HEAD)" "$main $PR_HEAD"
  assert_equals "$(git log -1 --format=%B)" "$MSG"
  # hub's --no-ff is not added to the user's
  run hub --noop merge --no-ff "$PR"
  [[ ${lines[1]} == "git merge -m "*" --no-ff refs/hub/merge/12-"* ]]
  assert_no_leftovers
}

@test "merge --squash squashes as git does, without a merge commit or hub's message" {
  make_pr_fixture
  local main
  main=$(git rev-parse HEAD)
  run hub merge --squash "$PR"
  assert_success
  assert_equals "$(git rev-parse HEAD)" "$main"
  assert_equals "$(git diff --cached --name-only)" build.txt
  [[ -e .git/SQUASH_MSG ]]
  assert_gh_not_called
  assert_no_leftovers
}

@test "merge takes the last of --squash and --no-squash, as git does" {
  make_pr_fixture
  stub_pr_message
  local main
  main=$(git rev-parse HEAD)
  run hub merge "$PR" --squash --no-squash
  assert_success
  assert_equals "$(parents HEAD)" "$main $PR_HEAD"
  assert_equals "$(git log -1 --format=%s)" "Merge pull request #12 from jingweno/fix-build"
  git reset -q --hard "$main"
  run hub merge --no-squash "$PR" --squash
  assert_success
  assert_equals "$(git rev-parse HEAD)" "$main"
  assert_equals "$(git diff --cached --name-only)" build.txt
  assert_no_leftovers
}

@test "merge with -m or -F keeps that message and doesn't ask gh" {
  make_pr_fixture
  local main
  main=$(git rev-parse HEAD)
  run hub merge -m "Bring in the fix" "$PR"
  assert_success
  assert_equals "$(parents HEAD)" "$main $PR_HEAD"
  assert_equals "$(git log -1 --format=%B)" "Bring in the fix"
  git reset -q --hard "$main"
  echo "From a file" >msg.txt
  run hub merge "$PR" --file=msg.txt
  assert_success
  assert_equals "$(git log -1 --format=%B)" "From a file"
  git reset -q --hard "$main"
  run hub merge -qm "Clustered message" "$PR"
  assert_success
  assert_equals "$(git log -1 --format=%B)" "Clustered message"
  assert_gh_not_called
  assert_no_leftovers
}

@test "merge passes other git-merge options on, in place" {
  make_pr_fixture
  stub_pr_message
  local main
  main=$(git rev-parse HEAD)
  run hub merge --no-edit -s ort -X theirs "$PR" --no-stat
  assert_success
  assert_equals "$(parents HEAD)" "$main $PR_HEAD"
  git reset -q --hard "$main"
  run hub merge -Xtheirs -sort "$PR"
  assert_success
  assert_equals "$(parents HEAD)" "$main $PR_HEAD"
  run hub --noop merge --no-edit -s ort -X theirs --cleanup verbatim "$PR" -S --into-name=main
  assert_success
  [[ ${lines[1]} == "git merge --no-ff -m "*" --no-edit -s ort -X theirs --cleanup verbatim refs/hub/merge/12-"*" -S --into-name=main" ]]
  assert_no_leftovers
}

@test "merge doesn't mistake the value of a message option for the pull request, in a cluster either" {
  make_pr_fixture
  make_topic
  local main topic
  main=$(git rev-parse HEAD) topic=$(git rev-parse topic)
  run hub merge -qm "$PR" topic
  assert_success
  assert_equals "$(parents HEAD)" "$main $topic"
  assert_equals "$(git log -1 --format=%B)" "$PR"
  [[ -f topic.txt && ! -e build.txt ]]
  git reset -q --hard "$main"
  run hub merge "-qm$PR" topic
  assert_success
  assert_equals "$(parents HEAD)" "$main $topic"
  assert_equals "$(git log -1 --format=%B)" "$PR"
  git reset -q --hard "$main"
  run hub merge --message="$PR" topic
  assert_success
  assert_equals "$(git log -1 --format=%B)" "$PR"
  git reset -q --hard "$main"
  mkdir -p https:/github.com/mislav/dotfiles/pull
  echo "From a file named like the URL" >"$PR"
  run hub merge -qF "$PR" topic
  assert_success
  assert_equals "$(parents HEAD)" "$main $topic"
  assert_equals "$(git log -1 --format=%B)" "From a file named like the URL"
  [[ ! -e .git/FETCH_HEAD ]]
  assert_gh_not_called
  assert_no_leftovers
}

@test "merge takes the pull request as the only revision" {
  make_pr_fixture
  make_topic
  run hub merge "$PR" topic
  assert_failure
  assert_output_equals "Aborted: a pull request is merged on its own; unexpected argument: topic"
  run hub merge topic "$PR" -- other
  assert_failure
  assert_output_equals "Aborted: a pull request is merged on its own; unexpected argument: topic"
  # an empty operand is one too, refused before anything is fetched
  run hub merge --squash "$PR" ''
  assert_failure
  assert_output_equals "Aborted: a pull request is merged on its own; unexpected argument: ''"
  run hub merge '' "$PR"
  assert_failure
  assert_output_equals "Aborted: a pull request is merged on its own; unexpected argument: ''"
  [[ ! -e .git/FETCH_HEAD ]]
  assert_gh_not_called
  assert_no_leftovers
}

@test "merge without a pull request URL, or with one after --, is plain git merge" {
  make_pr_fixture
  make_topic
  local main topic
  main=$(git rev-parse HEAD) topic=$(git rev-parse topic)
  run hub merge -q --no-edit topic
  assert_success
  assert_equals "$(parents HEAD)" "$main $topic"
  run hub --noop merge -- "$PR"
  assert_output_equals "git merge -- $PR"
  run hub --noop merge --abort
  assert_output_equals "git merge --abort"
  run hub --noop merge --continue "$PR"
  assert_output_equals "git merge --continue $PR"
  run hub --noop merge -h
  assert_output_equals "git merge -h"
  run hub --noop merge https://github.com/mislav/dotfiles/commit/abc1234
  assert_output_equals "git merge https://github.com/mislav/dotfiles/commit/abc1234"
  run hub --noop merge https://github.com/mislav/dotfiles/pull/12.patch
  assert_output_equals "git merge https://github.com/mislav/dotfiles/pull/12.patch"
  assert_gh_not_called
  assert_no_leftovers
}

@test "merge --help prints the manual" {
  run hub merge --help
  assert_success
  assert_output_contains "Usage: hub merge [<git-merge options>] PULLREQ-URL"
}

@test "merge never writes what the remote's fetch refspecs map the pull request to" {
  make_pr_fixture
  # pull requests mapped onto local branches, as some configurations have it, with local work on one
  git config --add remote.origin.fetch '+refs/pull/*/head:refs/heads/pull-*'
  git branch pull-12 main
  commit_on pull-12 "local work"
  local before
  before=$(tip pull-12)
  stub_pr_message
  run hub merge "$PR"
  assert_success
  [[ $(tip pull-12) == "$before" ]]
  [[ -f build.txt ]]
  [[ -z $(git for-each-ref refs/hub) ]]
  # the mapping is git's, for git's own fetches
  git fetch -q origin
  [[ $(tip pull-12) == "$PR_HEAD" ]]
}

@test "merge follows no tags into the repository" {
  make_pr_fixture
  git -C "$(server_dir mislav/dotfiles)" tag imported "$PR_HEAD" # a tag on the pull request's commit, in the base repository
  [[ -z $(git tag -l) ]]
  stub_pr_message
  run hub merge "$PR"
  assert_success
  [[ $(parents HEAD) == *" $PR_HEAD" ]]
  [[ -z $(git for-each-ref refs/tags) ]]
  assert_no_leftovers
  # git's own fetch follows it, as configured
  git fetch -q origin
  [[ $(git tag -l) == imported ]]
}
