#!/usr/bin/env bats
# hub sync: fetch the remotes, then fast-forward or delete local branches to match them.

load test_helper

warning='hub sync: warning:'

# server_commit [HOST/]OWNER/REPO BRANCH MSG [FILE TEXT] : a commit on the served BRANCH (started
# from main when missing), whose tree holds only FILE with TEXT when given; prints its id.
server_commit() {
  local dir parent tree blob commit
  dir=$(server_dir "$1")
  parent=$(git -C "$dir" rev-parse --verify --quiet "refs/heads/$2") \
    || parent=$(git -C "$dir" rev-parse refs/heads/main) || return 1
  tree=$(git -C "$dir" rev-parse "$parent^{tree}") || return 1
  if [[ -n ${4-} ]]; then
    blob=$(printf '%s\n' "$5" | git -C "$dir" hash-object -w --stdin) || return 1
    tree=$(printf '100644 blob %s\t%s\n' "$blob" "$4" | git -C "$dir" mktree) || return 1
  fi
  commit=$(git -C "$dir" commit-tree -p "$parent" -m "$3" "$tree") || return 1
  git -C "$dir" update-ref "refs/heads/$2" "$commit" && printf '%s\n' "$commit"
}

# server_merge_and_delete [HOST/]OWNER/REPO BRANCH : main fast-forwarded to BRANCH, BRANCH deleted.
server_merge_and_delete() {
  local dir
  dir=$(server_dir "$1")
  git -C "$dir" update-ref refs/heads/main "refs/heads/$2" || return 1
  git -C "$dir" update-ref -d "refs/heads/$2"
}

# pushed_branch NAME : a local branch NAME with one commit on main, pushed with -u; HEAD stays.
pushed_branch() {
  git branch -q "$1" refs/heads/main || return 1
  commit_on "$1" "work on $1" || return 1
  git push -q -u origin "refs/heads/$1:refs/heads/$1" 2>/dev/null
}

# short COMMIT : the abbreviation git prints for COMMIT.
short() { git rev-parse --short "$1"; }

@test "hub sync fast-forwards branches behind their upstream, the current branch last" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch feature
  was_main=$(tip main) was_feature=$(tip feature)
  main=$(server_commit mislav/dotfiles main 'new on main' README 'hello')
  feature=$(server_commit mislav/dotfiles feature 'new on feature')
  run hub sync
  assert_success
  assert_line_equals 0 "Updated branch feature (was $(short "$was_feature"))."
  assert_line_equals 1 "Updated branch main (was $(short "$was_main"))."
  assert_equals "${#lines[@]}" 2
  assert_equals "$(tip main)" "$main"
  assert_equals "$(tip feature)" "$feature"
  assert_equals "$(git symbolic-ref HEAD)" refs/heads/main
  assert_equals "$(git status --porcelain)" ''
  assert_equals "$(<README)" hello
  assert_gh_not_called
}

@test "hub sync prunes and updates the remote-tracking branches of the remote" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch old
  git branch -q --unset-upstream old
  was=$(tip old)
  git -C "$(server_dir mislav/dotfiles)" update-ref -d refs/heads/old
  main=$(server_commit mislav/dotfiles main 'new on main')
  run hub sync
  assert_success
  assert_equals "$(git rev-parse --verify --quiet refs/remotes/origin/old)" ''
  assert_equals "$(git rev-parse refs/remotes/origin/main)" "$main"
  assert_equals "$(tip old)" "$was"
}

@test "hub sync warns about branches ahead of or diverged from their upstream and keeps them" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch ahead
  pushed_branch diverged
  commit_on ahead 'local work'
  commit_on diverged 'local work'
  server_commit mislav/dotfiles diverged 'remote work' >/dev/null
  was_ahead=$(tip ahead) was_diverged=$(tip diverged)
  run hub sync
  assert_success
  assert_output_equals "$warning ahead seems to contain unpushed commits
$warning diverged seems to contain unpushed commits"
  assert_equals "$(tip ahead)" "$was_ahead"
  assert_equals "$(tip diverged)" "$was_diverged"
}

@test "hub sync deletes a branch that was merged and deleted on the remote, with its config" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was_main=$(tip main)
  pushed_branch topic
  was=$(tip topic)
  server_merge_and_delete mislav/dotfiles topic
  run hub sync
  assert_success
  assert_line_equals 0 "Deleted branch topic (was $(short "$was"))."
  assert_line_equals 1 "Updated branch main (was $(short "$was_main"))."
  assert_equals "$(tip topic)" ''
  assert_equals "$(git config --get-regexp '^branch\.topic\.')" ''
  assert_equals "$(tip main)" "$was"
}

@test "hub sync keeps a branch deleted on the remote that is not merged, squash merges included" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch topic
  was=$(tip topic)
  git -C "$(server_dir mislav/dotfiles)" update-ref -d refs/heads/topic
  server_commit mislav/dotfiles main 'Squashed topic' >/dev/null
  run hub sync
  assert_success
  assert_line_equals 0 \
    "$warning topic was deleted on origin, but is not merged into origin/main"
  assert_equals "$(tip topic)" "$was"
  assert_equals "$(git config branch.topic.remote)" origin
}

@test "hub sync switches away from the current branch before deleting it" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was_main=$(tip main)
  pushed_branch topic
  git switch -q topic
  was=$(tip topic)
  server_merge_and_delete mislav/dotfiles topic
  run hub sync
  assert_success
  assert_line_equals 0 "Updated branch main (was $(short "$was_main"))."
  assert_line_equals 1 "Deleted branch topic (was $(short "$was"))."
  assert_equals "$(git symbolic-ref HEAD)" refs/heads/main
  assert_equals "$(tip main)" "$was"
  assert_equals "$(tip topic)" ''
}

@test "hub sync keeps the current branch when the default branch is not a local branch" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch topic
  git switch -q topic
  git branch -q -D main
  was=$(tip topic)
  server_merge_and_delete mislav/dotfiles topic
  run hub sync
  assert_success
  assert_output_equals \
    "$warning topic is merged and deleted on origin; switch to another branch to delete it"
  assert_equals "$(git symbolic-ref HEAD)" refs/heads/topic
  assert_equals "$(tip topic)" "$was"
}

@test "hub sync asks gh for the default branch when refs/remotes/REMOTE/HEAD is missing" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git remote set-head origin -d
  git config remote.origin.followRemoteHEAD never
  pushed_branch topic
  server_merge_and_delete mislav/dotfiles topic
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef *' main
  run hub sync
  assert_success
  assert_equals "$(tip topic)" ''
  assert_gh_called \
    'repo view github.com/mislav/dotfiles --json defaultBranchRef --jq .defaultBranchRef.name'
}

@test "hub sync deletes nothing when the default branch is not known, and updates the rest" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git remote set-head origin -d
  git config remote.origin.followRemoteHEAD never
  pushed_branch topic
  pushed_branch feature
  was=$(tip topic) was_feature=$(tip feature)
  feature=$(server_commit mislav/dotfiles feature 'new on feature')
  git -C "$(server_dir mislav/dotfiles)" update-ref -d refs/heads/topic
  stub_gh 'repo view *' '' 1
  run hub sync
  assert_success
  assert_output_contains "Updated branch feature (was $(short "$was_feature"))."
  assert_output_contains "$warning topic was deleted on origin, but the default branch of \
origin is not known; leaving it alone"
  assert_equals "$(tip topic)" "$was"
  assert_equals "$(tip feature)" "$feature"
}

@test "hub sync leaves the default branch alone when it was deleted on the remote" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git config remote.origin.followRemoteHEAD never
  was=$(tip main)
  server_commit mislav/dotfiles trunk 'trunk' >/dev/null
  git -C "$(server_dir mislav/dotfiles)" symbolic-ref HEAD refs/heads/trunk
  git -C "$(server_dir mislav/dotfiles)" update-ref -d refs/heads/main
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef *' main
  run hub sync
  assert_success
  assert_output_equals "$warning main was deleted on origin, but it is the default branch of \
origin; leaving it alone"
  assert_equals "$(tip main)" "$was"
}

@test "hub sync in a fork's clone updates the default branch from upstream and fetches the fork" {
  serve_github octo/dotfiles mislav/dotfiles
  clone_served mislav/dotfiles
  was_main=$(tip main)
  git remote add upstream https://github.com/octo/dotfiles.git
  pushed_branch topic
  was=$(tip topic)
  git -C "$(server_dir mislav/dotfiles)" update-ref -d refs/heads/topic
  git push -q https://github.com/octo/dotfiles.git refs/heads/topic:refs/heads/main 2>/dev/null
  run hub sync
  assert_success
  assert_output_equals "Deleted branch topic (was $(short "$was")).
Updated branch main (was $(short "$was_main"))."
  assert_equals "$(tip main)" "$was"
  assert_equals "$(git config branch.main.remote)" origin
  assert_equals "$(git rev-parse --verify --quiet refs/remotes/origin/topic)" ''
  assert_gh_not_called
}

@test "hub sync REMOTE syncs that remote and the remotes its branches track, nothing else" {
  serve_github octo/dotfiles mislav/dotfiles jane/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/octo/dotfiles.git
  git remote add jane https://github.com/jane/dotfiles.git
  was=$(tip main)
  server_commit octo/dotfiles theirs 'theirs' >/dev/null
  git fetch -q upstream
  git branch -q -t theirs refs/remotes/upstream/theirs
  was_theirs=$(tip theirs)
  theirs=$(server_commit octo/dotfiles theirs 'new on theirs')
  server_commit octo/dotfiles main 'new upstream' >/dev/null
  server_commit jane/dotfiles main 'new on jane' >/dev/null
  main=$(server_commit mislav/dotfiles main 'new on the fork')
  run hub sync origin
  assert_success
  assert_output_equals "Updated branch theirs (was $(short "$was_theirs")).
Updated branch main (was $(short "$was"))."
  assert_equals "$(tip main)" "$main"
  assert_equals "$(tip theirs)" "$theirs"
  assert_equals "$(git for-each-ref --format='%(refname)' refs/remotes/jane)" ''
}

@test "hub sync fetches each remote once" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch feature
  run hub --noop sync
  assert_success
  assert_output_equals 'git fetch --prune --quiet -- origin'
}

@test "hub sync goes on past a branch checked out in another work tree and exits 1" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch busy
  pushed_branch feature
  git worktree add -q ../busy busy
  was=$(tip busy) was_feature=$(tip feature)
  server_commit mislav/dotfiles busy 'new on busy' >/dev/null
  feature=$(server_commit mislav/dotfiles feature 'new on feature')
  run hub sync
  assert_status 1
  assert_output_contains "fatal: refusing to fetch into branch 'refs/heads/busy' checked out at"
  assert_output_contains "Updated branch feature (was $(short "$was_feature"))."
  assert_equals "$(tip busy)" "$was"
  assert_equals "$(tip feature)" "$feature"
  assert_equals "$(git -C ../busy status --porcelain)" ''
}

@test "hub sync exits 1 when a merged branch cannot be deleted" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch topic
  git worktree add -q ../topic topic
  was=$(tip topic)
  server_merge_and_delete mislav/dotfiles topic
  run hub sync
  assert_status 1
  assert_output_contains "cannot delete branch 'topic' used by worktree at"
  assert_equals "$(tip topic)" "$was"
  assert_equals "$(tip main)" "$was"
}

@test "hub sync leaves the current branch when local changes are in the way and exits 1" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was=$(tip main)
  server_commit mislav/dotfiles main 'add README' README theirs >/dev/null
  printf 'mine\n' >README
  run hub sync
  assert_status 1
  assert_line_equals 0 \
    'error: The following untracked working tree files would be overwritten by merge:'
  assert_line_equals 1 $'\tREADME'
  assert_equals "$(tip main)" "$was"
  assert_equals "$(<README)" mine
}

@test "hub sync fast-forwards the current branch even when its merge options say --squash" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git config branch.main.mergeOptions --squash
  main=$(server_commit mislav/dotfiles main 'new on main')
  run hub sync
  assert_success
  assert_equals "$(tip main)" "$main"
  assert_equals "$(git rev-parse HEAD)" "$main"
  assert_equals "$(ls .git/SQUASH_MSG 2>/dev/null)" ''
}

@test "hub sync on a detached HEAD updates the branches and leaves HEAD alone" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was=$(tip main)
  git switch -q --detach
  main=$(server_commit mislav/dotfiles main 'new on main')
  run hub sync
  assert_success
  assert_output_equals "Updated branch main (was $(short "$was"))."
  assert_equals "$(tip main)" "$main"
  assert_equals "$(git rev-parse HEAD)" "$was"
  assert_equals "$(git symbolic-ref --quiet HEAD)" ''
}

@test "hub sync skips symbolic refs and branches without an upstream" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch feature
  git branch -q --unset-upstream feature
  git symbolic-ref refs/heads/alias refs/heads/main
  git config branch.alias.remote origin
  git config branch.alias.merge refs/heads/main
  was_feature=$(tip feature) was_main=$(tip main)
  server_commit mislav/dotfiles feature 'new on feature' >/dev/null
  main=$(server_commit mislav/dotfiles main 'new on main')
  run hub sync
  assert_success
  assert_output_equals "Updated branch main (was $(short "$was_main"))."
  assert_equals "$(tip feature)" "$was_feature"
  assert_equals "$(git symbolic-ref refs/heads/alias)" refs/heads/main
  assert_equals "$(tip main)" "$main"
}

@test "hub sync updates the default branch from the remote even without an upstream" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c work
  git branch -q --unset-upstream main
  main=$(server_commit mislav/dotfiles main 'new on main')
  run hub sync
  assert_success
  assert_equals "$(tip main)" "$main"
}

@test "hub sync fails with git's status when the remote cannot be fetched" {
  make_repo work origin=https://github.com/mislav/missing.git
  was=$(tip main)
  run hub sync
  assert_status 128
  assert_output_contains 'nothing is served at https://github.com/mislav/missing.git'
  assert_equals "$(tip main)" "$was"
}

@test "hub sync goes on when another tracked remote cannot be fetched, and exits 1" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was_main=$(tip main)
  git remote add dead https://github.com/nobody/dotfiles.git
  git branch -q stale refs/heads/main
  git config branch.stale.remote dead
  git config branch.stale.merge refs/heads/stale
  main=$(server_commit mislav/dotfiles main 'new on main')
  run hub sync
  assert_status 1
  assert_output_contains 'nothing is served at https://github.com/nobody/dotfiles.git'
  assert_output_contains "Updated branch main (was $(short "$was_main"))."
  assert_equals "$(tip main)" "$main"
  assert_equals "$(tip stale)" "$was_main"
}

@test "hub sync with a remote that is not on GitHub reads its default branch from its HEAD" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was_main=$(tip main)
  pushed_branch topic
  git remote add mirror "$(server_dir mislav/dotfiles)"
  git fetch -q mirror
  git branch -q -u mirror/main main
  git branch -q -u mirror/topic topic
  was=$(tip topic)
  server_merge_and_delete mislav/dotfiles topic
  run hub sync mirror
  assert_success
  assert_line_equals 0 "Deleted branch topic (was $(short "$was"))."
  assert_line_equals 1 "Updated branch main (was $(short "$was_main"))."
  assert_equals "$(tip topic)" ''
  assert_equals "$(tip main)" "$was"
  assert_gh_not_called
}

@test "hub sync with a remote that is not on GitHub and has no HEAD deletes none" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was_main=$(tip main)
  pushed_branch topic
  git remote add mirror "$(server_dir mislav/dotfiles)"
  git config remote.mirror.followRemoteHEAD never
  git fetch -q mirror
  git branch -q -u mirror/main main
  git branch -q -u mirror/topic topic
  was=$(tip topic)
  server_merge_and_delete mislav/dotfiles topic
  run hub sync mirror
  assert_success
  assert_line_equals 0 "$warning topic was deleted on mirror, but the default branch of mirror is \
not known; leaving it alone"
  assert_line_equals 1 "Updated branch main (was $(short "$was_main"))."
  assert_equals "$(tip topic)" "$was"
  assert_equals "$(tip main)" "$was"
  assert_gh_not_called
}

@test "hub sync without gh treats the default branch as unknown and still updates" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git remote set-head origin -d
  git config remote.origin.followRemoteHEAD never
  pushed_branch topic
  pushed_branch feature
  was=$(tip topic) was_feature=$(tip feature) was_main=$(tip main)
  feature=$(server_commit mislav/dotfiles feature 'new on feature')
  server_merge_and_delete mislav/dotfiles topic
  mkdir "$HUB_TEST_TMP/nogh"
  ln -s "$(command -v git)" "$HUB_TEST_TMP/nogh/git"
  ln -s "$(command -v bash)" "$HUB_TEST_TMP/nogh/bash"
  PATH=$HUB_TEST_TMP/nogh:/usr/bin:/bin run hub sync
  assert_success
  assert_output_equals "Updated branch feature (was $(short "$was_feature")).
$warning topic was deleted on origin, but the default branch of origin is not known; leaving \
it alone
Updated branch main (was $(short "$was_main"))."
  assert_equals "$(tip topic)" "$was"
  assert_equals "$(tip feature)" "$feature"
  assert_equals "$(tip main)" "$was"
}

@test "hub sync switches away only when it can, and keeps the branch and local changes" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  pushed_branch topic
  printf 'main\n' >README
  git add README
  git commit -q -m 'README on main'
  git switch -q topic
  was=$(tip topic) was_main=$(tip main)
  server_merge_and_delete mislav/dotfiles topic
  printf 'mine\n' >README
  run hub sync
  assert_status 1
  assert_output_contains "$warning main seems to contain unpushed commits"
  assert_output_contains 'error: The following untracked working tree files would be overwritten'
  assert_output_lacks 'cannot delete branch'
  assert_equals "$(git symbolic-ref HEAD)" refs/heads/topic
  assert_equals "$(tip topic)" "$was"
  assert_equals "$(tip main)" "$was_main"
  assert_equals "$(<README)" mine
}

@test "hub sync deletes a merged branch whose name looks like an option" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git update-ref refs/heads/-x refs/heads/main
  commit_on -x 'work on -x'
  git push -q origin refs/heads/-x:refs/heads/-x 2>/dev/null
  git fetch -q origin
  git config branch.-x.remote origin
  git config branch.-x.merge refs/heads/-x
  was=$(tip -x)
  server_merge_and_delete mislav/dotfiles -x
  run hub sync
  assert_success
  assert_line_equals 0 "Deleted branch -x (was $(short "$was"))."
  assert_equals "$(tip -x)" ''
  assert_equals "$(tip main)" "$was"
}

@test "hub sync leaves a branch whose upstream is a deleted local branch alone" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git branch -q base refs/heads/main
  git branch -q -t child refs/heads/base
  git branch -q -D base
  was=$(tip child)
  run hub sync
  assert_success
  assert_output_equals ''
  assert_equals "$(tip child)" "$was"
  assert_equals "$(git config branch.child.remote)" .
}

@test "hub sync leaves a branch made by gh pr checkout for a fork alone" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git branch -q review refs/heads/main
  commit_on review 'their work'
  git config branch.review.remote https://github.com/jane/dotfiles.git
  git config branch.review.merge refs/pull/7/head
  was=$(tip review)
  run hub sync
  assert_success
  assert_output_equals ''
  assert_equals "$(tip review)" "$was"
}

@test "hub sync relays an invalid GH_REPO and names a GH_REPO no remote points to" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  was=$(git rev-parse refs/remotes/origin/main)
  server_commit mislav/dotfiles main 'new on main' >/dev/null
  GH_REPO='a b' run hub sync
  assert_status 1
  assert_output_equals \
    'hub sync: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
  GH_REPO=octo/other run hub sync
  assert_status 1
  assert_output_equals \
    'hub sync: no remote points to GH_REPO: octo/other (name the remote to sync)'
  assert_equals "$(git rev-parse refs/remotes/origin/main)" "$was"
  assert_gh_not_called
}

@test "hub sync with GH_REPO syncs the remote that points to it" {
  serve_github octo/dotfiles mislav/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/octo/dotfiles.git
  was=$(tip main)
  server_commit octo/dotfiles main 'new upstream' >/dev/null
  main=$(server_commit mislav/dotfiles main 'new on the fork')
  GH_REPO=mislav/dotfiles run hub sync
  assert_success
  assert_output_equals "Updated branch main (was $(short "$was"))."
  assert_equals "$(tip main)" "$main"
  assert_equals "$(git for-each-ref --format='%(refname)' refs/remotes/upstream)" ''
}

@test "hub sync refuses extra arguments, unknown options and unknown remotes before fetching" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  server_commit mislav/dotfiles main 'new on main' >/dev/null
  was=$(git rev-parse refs/remotes/origin/main)
  run hub sync origin upstream
  assert_status 1
  assert_line_equals 0 'hub sync: unexpected argument: upstream'
  assert_line_equals 1 'Usage: hub sync [REMOTE]'
  run hub sync -q
  assert_status 1
  assert_line_equals 0 'hub sync: unknown option: -q'
  run hub sync origin --prune
  assert_status 1
  assert_line_equals 0 'hub sync: unknown option: --prune'
  run hub sync nope
  assert_status 1
  assert_output_equals 'hub sync: not a remote: nope'
  run hub sync -- -x
  assert_status 1
  assert_output_equals 'hub sync: not a remote: -x'
  assert_equals "$(git rev-parse refs/remotes/origin/main)" "$was"
  assert_gh_not_called
}

@test "hub sync refuses to guess the remote without a GitHub remote" {
  make_repo work origin=https://gitlab.com/mislav/dotfiles.git
  run hub sync
  assert_status 1
  assert_output_equals 'hub sync: no GitHub remote found; name the remote to sync'
  assert_gh_not_called
}

@test "hub sync outside a repository says so" {
  run hub sync
  assert_status 1
  assert_output_contains 'not a git repository'
}

@test "hub sync --help and hub help sync print its manual" {
  run hub sync --help
  assert_success
  assert_line_equals 0 \
    'Summary: Fetch and fast-forward or delete local branches to match the remotes.'
  assert_line_equals 1 'Usage: hub sync [REMOTE]'
  run hub sync -h
  assert_line_equals 1 'Usage: hub sync [REMOTE]'
  run hub help sync
  assert_success
  assert_line_equals 1 'Usage: hub sync [REMOTE]'
}
