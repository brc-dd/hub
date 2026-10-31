#!/usr/bin/env bats
load ../test_helper

# child_of REV MESSAGE : a new commit on top of REV that no ref points at; prints its hash.
child_of() { git commit-tree -p "$1" -m "$2" "$1^{tree}"; }

# make_sync_fixture : github.com/mislav/dotfiles; "work", the clone under test, left as the current directory
# with main checked out and a local branch in every state sync handles; and "seed", everyone else's clone,
# through which github.com then moves on: main, behind, diverged and same-name get a commit, merged is
# merged into main and deleted, unmerged is deleted.
make_sync_fixture() {
  local b
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles work
  for b in ahead behind diverged merged same-name unmerged uptodate; do git branch -q "$b"; done
  commit_on merged "merged work"
  commit_on unmerged "unmerged work"
  git push -q origin --all
  for b in ahead behind diverged merged unmerged uptodate; do git branch -q --set-upstream-to="origin/$b" "$b"; done
  git branch -q local-only
  commit_on ahead "local work"
  commit_on diverged "local work"
  cd .. && clone_served mislav/dotfiles seed
  for b in behind diverged same-name; do git branch -q --track "$b" "origin/$b"; done
  for b in main behind diverged same-name; do commit_on "$b" "upstream work"; done
  git merge -q --no-ff -m "Merge branch 'merged'" origin/merged
  git push -q origin main behind diverged same-name
  git push -q origin --delete merged unmerged
  cd "$HUB_TEST_TMP/work" || return 1
}

# make_file_fixture : github.com/mislav/dotfiles whose main has file.txt, and "work", a clone of it on main,
# left as the current directory.
make_file_fixture() {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles work
  echo committed >file.txt && git add file.txt && git commit -q -m "add file.txt" && git push -q origin main
}

# advance_server_main : through "seed", another clone, change file.txt on github.com's main.
advance_server_main() {
  (cd "$HUB_TEST_TMP" && clone_served mislav/dotfiles seed && echo remote-new >file.txt && git commit -q -am "remote work" && git push -q origin main)
}

@test "sync fast-forwards branches that are behind, deletes merged ones and warns about the rest" {
  make_sync_fixture
  local main behind merged same_name ahead diverged unmerged local_only
  main=$(git rev-parse --short main) behind=$(git rev-parse --short behind)
  merged=$(git rev-parse --short merged) same_name=$(git rev-parse --short same-name)
  ahead=$(tip ahead) diverged=$(tip diverged) unmerged=$(tip unmerged) local_only=$(tip local-only)
  run hub sync
  assert_success
  assert_output_equals "warning: 'ahead' seems to contain unpushed commits
Updated branch behind (was $behind).
warning: 'diverged' seems to contain unpushed commits
Updated branch main (was $main).
Deleted branch merged (was $merged).
Updated branch same-name (was $same_name).
warning: 'unmerged' was deleted on origin, but appears not merged into 'main'"
  local b
  for b in main behind same-name uptodate; do
    assert_equals "$(tip "$b")" "$(server_ref mislav/dotfiles "$b")"
  done
  [[ -z $(tip merged) ]]
  [[ $(tip ahead) == "$ahead" && $(tip diverged) == "$diverged" && $(tip unmerged) == "$unmerged" ]]
  [[ $(tip local-only) == "$local_only" ]]
  [[ $(git symbolic-ref --short HEAD) == main && -z $(git status --porcelain) ]]
  # The remote-tracking branches of what github.com deleted are pruned; nothing else is.
  [[ -z $(git rev-parse --verify -q refs/remotes/origin/merged) && -z $(git rev-parse --verify -q refs/remotes/origin/unmerged) ]]
  [[ -n $(git rev-parse --verify -q refs/remotes/origin/ahead) ]]
  # Tracking configuration is left as it was, and the deleted branch's goes with it.
  [[ $(git rev-parse --abbrev-ref 'behind@{upstream}') == origin/behind ]]
  [[ -z $(git config branch.same-name.merge) ]]
  [[ $(git config branch.unmerged.merge) == refs/heads/unmerged ]]
  [[ -z $(git config --get-regexp '^branch\.merged\.') ]]
  [[ $(git reflog -1 --format=%gs refs/heads/behind) == "hub sync: fast-forward to origin/behind" ]]
  assert_gh_not_called
}

@test "sync switches to the default branch before deleting the current one" {
  make_sync_fixture
  git switch -q merged
  run hub sync
  assert_success
  assert_output_contains "Updated branch main (was "
  assert_output_contains "Deleted branch merged (was "
  [[ $(git symbolic-ref --short HEAD) == main && -z $(git status --porcelain) ]]
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
  [[ $(git rev-parse HEAD) == $(tip main) && -z $(tip merged) ]]
}

@test "sync creates a missing default branch from the remote, never by restoring a file of that name" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles work
  echo committed >main && git add main && git commit -q -m "a file named main" && git push -q origin main
  git switch -q -c topic && git push -q -u origin topic && git push -q origin --delete topic
  git branch -q -D main
  git config checkout.guess false
  echo 'irreplaceable edits' >main
  run hub sync
  assert_success
  assert_output_contains "Deleted branch topic (was "
  [[ $(git symbolic-ref --short HEAD) == main ]]
  assert_equals "$(cat main)" 'irreplaceable edits'
  [[ $(git status --porcelain) == ' M main' ]]
  [[ -z $(tip topic) ]]
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
  [[ $(git config branch.main.remote) == origin && $(git config branch.main.merge) == refs/heads/main ]]
}

@test "sync creates a missing default branch from the remote it syncs, not from checkout.defaultRemote or a tag" {
  make_sync_fixture
  git switch -q merged
  git branch -q -D main
  git remote add backup https://github.com/backup/dotfiles.git
  git update-ref refs/remotes/backup/main "$(child_of refs/remotes/origin/main 'backup work')"
  git config checkout.defaultRemote backup
  git tag main "$(child_of refs/remotes/origin/main 'tagged work')"
  run hub sync
  assert_success
  assert_output_contains "Deleted branch merged (was "
  [[ $(git symbolic-ref HEAD) == refs/heads/main ]]
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
  [[ $(git config branch.main.remote) == origin && $(git config branch.main.merge) == refs/heads/main ]]
  [[ -z $(tip merged) && -n $(git rev-parse --verify -q refs/tags/main) ]]
}

@test "sync keeps the current branch, and fails, when it cannot switch to the default branch" {
  make_sync_fixture
  git switch -q merged
  git worktree add -q "$HUB_TEST_TMP/wt-main" main
  local merged main
  merged=$(tip merged) main=$(tip main)
  run hub sync
  assert_failure
  assert_output_contains "error: could not switch to 'main' to delete 'merged'"
  assert_output_contains "warning: 'main' is checked out in "
  assert_output_contains "Updated branch behind (was "
  [[ $(git symbolic-ref --short HEAD) == merged && $(tip merged) == "$merged" && $(tip main) == "$main" ]]
  [[ $(git config branch.merged.remote) == origin ]]
  assert_equals "$(tip behind)" "$(server_ref mislav/dotfiles behind)"
}

@test "sync's fetch never writes or prunes local branches or tags, whatever the fetch configuration says" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles work
  git branch -q x-topic && commit_on x-topic "unmerged x work"
  git branch -q x-pushed && git push -q origin x-pushed
  git tag local-only-tag
  local xtopic xpushed
  xtopic=$(tip x-topic) xpushed=$(tip x-pushed)
  # fetch refspecs that map straight into local branches, with pruning of branches and tags turned on
  git config --replace-all remote.origin.fetch 'refs/heads/x*:refs/heads/x*'
  git config --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git config fetch.prune true
  git config fetch.pruneTags true
  cp -R "$HUB_TEST_TMP/work" "$HUB_TEST_TMP/control"
  # github.com: x-pushed is rewritten, main moves on
  cd .. && clone_served mislav/dotfiles seed
  git switch -q -c x-pushed origin/x-pushed && git commit -q --allow-empty -m "rewritten" --amend && git push -q -f origin x-pushed
  git switch -q main && git commit -q --allow-empty -m "upstream work" && git push -q origin main
  cd "$HUB_TEST_TMP/work"
  run hub sync
  assert_success
  assert_output_equals "Updated branch main (was $(git rev-parse --short "$(server_ref mislav/dotfiles main)~1")).
warning: 'x-pushed' seems to contain unpushed commits"
  [[ $(tip x-topic) == "$xtopic" && $(tip x-pushed) == "$xpushed" ]]
  git reflog exists refs/heads/x-topic
  [[ -n $(git rev-parse --verify -q refs/tags/local-only-tag) ]]
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
  assert_equals "$(git rev-parse refs/remotes/origin/x-pushed)" "$(server_ref mislav/dotfiles x-pushed)"
  # With the same configuration, git's own pruning fetch deletes the branch and the tag (and then fails
  # over the rewritten x-pushed).
  run git -C "$HUB_TEST_TMP/control" fetch -q --prune origin
  [[ -z $(git -C "$HUB_TEST_TMP/control" rev-parse --verify -q refs/heads/x-topic) ]]
  [[ -z $(git -C "$HUB_TEST_TMP/control" rev-parse --verify -q refs/tags/local-only-tag) ]]
}

@test "sync leaves alone a branch that moved after it looked, and fails" {
  make_sync_fixture
  local c
  c=$(child_of refs/heads/behind "concurrent work")
  shim_git 'update-ref --no-deref -m * refs/heads/behind *' "git update-ref refs/heads/behind $c"
  PATH=$SHIM_PATH run hub sync
  assert_failure
  assert_output_contains "error: 'behind' changed while syncing; leaving it alone"
  assert_output_lacks "Updated branch behind"
  assert_output_contains "Updated branch main (was "
  [[ $(tip behind) == "$c" ]]
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
}

@test "sync leaves alone the current branch when it moved after sync looked, and fails" {
  make_sync_fixture
  local c
  c=$(child_of refs/heads/main "concurrent work")
  shim_git 'rev-parse --verify --quiet refs/heads/main^{commit}' "git update-ref refs/heads/main $c"
  PATH=$SHIM_PATH run hub sync
  assert_failure
  assert_output_contains "error: 'main' changed while syncing; leaving it alone"
  assert_output_lacks "Updated branch main"
  assert_output_contains "Updated branch behind (was "
  [[ $(tip main) == "$c" && $(git rev-parse HEAD) == "$c" ]]
}

@test "sync does not delete a branch that moved after it looked, and fails" {
  make_sync_fixture
  local c
  c=$(child_of refs/heads/merged "concurrent work")
  shim_git 'update-ref --no-deref -d refs/heads/merged *' "git update-ref refs/heads/merged $c"
  PATH=$SHIM_PATH run hub sync
  assert_failure
  assert_output_contains "error: 'merged' changed while syncing; leaving it alone"
  assert_output_lacks "Deleted branch merged"
  [[ $(tip merged) == "$c" && $(git config branch.merged.remote) == origin ]]
}

@test "sync fast-forwards to the commit it checked, not to where another fetch moved the remote-tracking branch" {
  make_sync_fixture
  local d
  d=$(child_of refs/heads/behind "elsewhere")
  shim_git 'update-ref --no-deref -m * refs/heads/behind *' "git update-ref refs/remotes/origin/behind $d"
  PATH=$SHIM_PATH run hub sync
  assert_success
  assert_output_contains "Updated branch behind (was "
  assert_equals "$(tip behind)" "$(server_ref mislav/dotfiles behind)"
  [[ $(git rev-parse refs/remotes/origin/behind) == "$d" ]]
}

@test "sync writes the ref it examined, never another branch through a symbolic ref made meanwhile" {
  make_sync_fixture
  local old
  old=$(tip behind)
  # between sync's look and its update, behind becomes a symbolic ref to a branch at the same commit
  shim_git 'update-ref --no-deref -m * refs/heads/behind *' 'git branch target refs/heads/behind && git symbolic-ref refs/heads/behind refs/heads/target'
  PATH=$SHIM_PATH run hub sync
  assert_success
  assert_output_contains "Updated branch behind (was "
  [[ -e $HUB_TEST_TMP/shim/done ]]
  [[ -z $(git symbolic-ref -q refs/heads/behind) ]] # a plain branch again, at the new commit
  assert_equals "$(tip behind)" "$(server_ref mislav/dotfiles behind)"
  [[ $(tip target) == "$old" ]] # the branch the symbolic ref pointed at is untouched
}

@test "sync deletes the ref it examined, never the branch a symbolic ref made meanwhile points at" {
  make_sync_fixture
  local old
  old=$(tip merged)
  shim_git 'update-ref --no-deref -d refs/heads/merged *' 'git branch keep refs/heads/merged && git symbolic-ref refs/heads/merged refs/heads/keep'
  PATH=$SHIM_PATH run hub sync
  assert_success
  assert_output_contains "Deleted branch merged (was "
  [[ -e $HUB_TEST_TMP/shim/done ]]
  [[ -z $(git symbolic-ref -q refs/heads/merged) && -z $(tip merged) ]]
  [[ $(tip keep) == "$old" ]]
}

@test "sync skips symbolic refs among the branches and fast-forwards their target through the work tree" {
  make_file_fixture
  git symbolic-ref refs/heads/alias refs/heads/main
  # github.com has alias ahead of main
  local a
  a=$(tip main)
  (cd "$HUB_TEST_TMP" && clone_served mislav/dotfiles seed && echo remote-new >file.txt && git commit -q -am "alias work" && git push -q origin main:alias)
  run hub sync
  assert_success
  assert_output_equals "warning: 'alias' is a symbolic ref to 'main'; skipping it"
  [[ $(tip main) == "$a" && $(git symbolic-ref refs/heads/alias) == refs/heads/main ]]
  [[ $(cat file.txt) == committed && -z $(git status --porcelain) ]]
  # main itself moves only through the work tree
  git -C "$HUB_TEST_TMP/seed" push -q origin main
  run hub sync
  assert_success
  assert_output_contains "Updated branch main (was ${a:0:7})."
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
  [[ $(git rev-parse HEAD) == $(tip main) && $(cat file.txt) == remote-new && -z $(git status --porcelain) ]]
  [[ $(git symbolic-ref refs/heads/alias) == refs/heads/main ]]
  # a symbolic ref whose branch is gone from github.com is not deleted either, and neither is its target
  git config branch.alias.remote origin
  git config branch.alias.merge refs/heads/alias
  git -C "$HUB_TEST_TMP/seed" push -q origin --delete alias
  run hub sync
  assert_success
  assert_output_equals "warning: 'alias' is a symbolic ref to 'main'; skipping it"
  [[ $(git symbolic-ref refs/heads/alias) == refs/heads/main && -n $(tip main) ]]
}

@test "sync never updates a branch checked out in another work tree" {
  make_file_fixture
  local a
  a=$(tip main)
  git switch -q -c topic
  git worktree add -q "$HUB_TEST_TMP/wt" main
  advance_server_main
  run hub sync
  assert_success
  assert_output_contains "warning: 'main' is checked out in "
  assert_output_contains "; not updating it"
  [[ $(tip main) == "$a" ]]
  [[ $(git -C "$HUB_TEST_TMP/wt" rev-parse HEAD) == "$a" && -z $(git -C "$HUB_TEST_TMP/wt" status --porcelain) ]]
  [[ $(cat "$HUB_TEST_TMP/wt/file.txt") == committed ]]
}

@test "sync fast-forwards the current branch although merging is configured to squash" {
  make_file_fixture
  advance_server_main
  git config branch.main.mergeOptions --squash
  local before
  before=$(git rev-parse --short main)
  run hub sync
  assert_success
  assert_output_equals "Updated branch main (was $before)."
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
  [[ $(git rev-parse HEAD) == $(tip main) && -z $(git status --porcelain) && $(cat file.txt) == remote-new ]]
  [[ ! -e .git/SQUASH_MSG ]]
}

@test "sync fails when the current branch cannot be fast-forwarded: local changes, or a merge setting that refuses" {
  make_file_fixture
  advance_server_main
  local a
  a=$(tip main)
  echo mine >file.txt
  run hub sync
  assert_failure
  assert_output_lacks "Updated branch main"
  [[ $(tip main) == "$a" && $(cat file.txt) == mine ]]
  git checkout -q -- file.txt
  git config branch.main.mergeOptions --verify-signatures
  run hub sync
  assert_failure
  assert_output_lacks "Updated branch main"
  [[ $(tip main) == "$a" && $(cat file.txt) == committed ]]
}

@test "sync with a detached HEAD updates the branches and leaves HEAD where it is" {
  make_sync_fixture
  git switch -q --detach
  local head
  head=$(git rev-parse HEAD)
  run hub sync
  assert_success
  assert_output_contains "Updated branch main (was "
  assert_output_contains "Deleted branch merged (was "
  [[ $(git rev-parse HEAD) == "$head" && -z $(git symbolic-ref -q HEAD) ]]
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
}

@test "sync --noop prints the commands that would change branches and changes nothing" {
  make_sync_fixture
  git fetch -q --prune origin
  local before
  before=$(git for-each-ref)
  run hub --noop sync
  assert_success
  assert_output_equals "git fetch --prune --quiet --refmap= origin +refs/heads/\\*:refs/remotes/origin/\\*
warning: 'ahead' seems to contain unpushed commits
git update-ref --no-deref -m hub\\ sync:\\ fast-forward\\ to\\ origin/behind refs/heads/behind $(server_ref mislav/dotfiles behind) $(tip behind)
warning: 'diverged' seems to contain unpushed commits
git merge --ff-only --no-squash --quiet $(server_ref mislav/dotfiles main)
git update-ref --no-deref -d refs/heads/merged $(tip merged)
git config --remove-section branch.merged
git update-ref --no-deref -m hub\\ sync:\\ fast-forward\\ to\\ origin/same-name refs/heads/same-name $(server_ref mislav/dotfiles same-name) $(tip same-name)
warning: 'unmerged' was deleted on origin, but appears not merged into 'main'"
  [[ $(git for-each-ref) == "$before" && -z $(git status --porcelain) ]]
  git switch -q merged
  run hub --noop sync
  assert_success
  assert_output_contains "git switch --quiet --no-guess main
git update-ref --no-deref -d refs/heads/merged $(tip merged)"
  [[ $(git for-each-ref) == "$before" && $(git symbolic-ref --short HEAD) == merged ]]
}

@test "sync follows a renamed default branch, asking gh when REMOTE/HEAD points at a pruned branch" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles work
  local srv
  srv=$(server_dir mislav/dotfiles)
  git -C "$srv" update-ref refs/heads/trunk refs/heads/main
  git -C "$srv" symbolic-ref HEAD refs/heads/trunk
  git -C "$srv" update-ref -d refs/heads/main
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef *' 'trunk'
  run hub sync
  assert_success
  assert_output_equals "Deleted branch main (was $(git rev-parse --short "$(server_ref mislav/dotfiles trunk)"))."
  [[ $(git symbolic-ref --short HEAD) == trunk && -z $(tip main) ]]
  assert_equals "$(tip trunk)" "$(server_ref mislav/dotfiles trunk)"
  [[ $(git config branch.trunk.remote) == origin && $(git config branch.trunk.merge) == refs/heads/trunk ]]
  assert_gh_called 'repo view github.com/mislav/dotfiles --json defaultBranchRef -q .defaultBranchRef.name'
}

@test "sync leaves gone branches alone when the remote has no default branch to check them against" {
  make_sync_fixture
  local srv
  srv=$(server_dir mislav/dotfiles)
  git -C "$srv" update-ref refs/heads/trunk refs/heads/main
  git -C "$srv" update-ref -d refs/heads/main
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef *' 'main'
  local main merged
  main=$(tip main) merged=$(tip merged)
  run hub sync
  assert_success
  assert_output_contains "warning: 'main' tracks a branch that is gone from origin, but it is the default branch; leaving it alone"
  assert_output_contains "warning: 'merged' was deleted on origin, but origin has no 'main' branch to check it against; leaving it alone"
  assert_output_contains "warning: 'unmerged' was deleted on origin, but origin has no 'main' branch to check it against; leaving it alone"
  [[ $(tip main) == "$main" && $(tip merged) == "$merged" && $(git symbolic-ref --short HEAD) == main ]]
}

@test "sync deletes a branch tracking a pull request ref once it is merged, and otherwise leaves it alone quietly" {
  make_file_fixture
  cd .. && clone_served mislav/dotfiles seed
  git switch -q -c feature && echo feature >feature.txt && git add feature.txt && git commit -q -m "feature work"
  git push -q origin HEAD:refs/pull/5/head
  cd ../work
  # as gh pr checkout sets up a branch for a pull request from a fork
  git fetch -q origin refs/pull/5/head:feature
  git config branch.feature.remote origin
  git config branch.feature.merge refs/pull/5/head
  local feature
  feature=$(tip feature)
  run hub sync
  assert_success
  assert_output_equals ""
  [[ $(tip feature) == "$feature" ]]
  git -C "$HUB_TEST_TMP/seed" switch -q main
  git -C "$HUB_TEST_TMP/seed" merge -q --no-ff -m "Merge pull request #5 from fork/feature" feature
  git -C "$HUB_TEST_TMP/seed" push -q origin main
  run hub sync
  assert_success
  assert_output_equals "Deleted branch feature (was ${feature:0:7}).
Updated branch main (was $(git rev-parse --short "$(server_ref mislav/dotfiles main)~1"))."
  [[ -z $(tip feature) && -z $(git config --get-regexp '^branch\.feature\.') ]]
}

@test "sync syncs the remote named, else the main GitHub remote" {
  serve_github me/dotfiles mislav/dotfiles
  clone_served me/dotfiles work
  git remote add upstream https://github.com/mislav/dotfiles.git
  (cd "$HUB_TEST_TMP" && clone_served mislav/dotfiles seed && git commit -q --allow-empty -m "upstream work" && git push -q origin main)
  local a
  a=$(tip main)
  run hub sync origin
  assert_success
  assert_output_equals ""
  [[ $(tip main) == "$a" ]]
  run hub sync upstream
  assert_success
  assert_output_equals "Updated branch main (was ${a:0:7})."
  assert_equals "$(tip main)" "$(server_ref mislav/dotfiles main)"
  # with no remote named, upstream comes first
  git reset -q --hard "$a"
  run hub sync
  assert_success
  assert_output_equals "Updated branch main (was ${a:0:7})."
  assert_gh_not_called
}

@test "sync --color colors what changed; --color=never and a non-terminal do not" {
  make_sync_fixture
  local behind merged
  behind=$(git rev-parse --short behind) merged=$(git rev-parse --short merged)
  run hub sync --color
  assert_success
  assert_output_contains $'\e[32mUpdated branch \e[32;1mbehind\e[0m (was '"$behind)."
  assert_output_contains $'\e[31mDeleted branch \e[31;1mmerged\e[0m (was '"$merged)."
  assert_output_contains "warning: 'ahead' seems to contain unpushed commits"
  serve_github me/dotfiles
  cd "$HUB_TEST_TMP" && clone_served me/dotfiles mine
  (cd "$HUB_TEST_TMP" && clone_served me/dotfiles mine-seed && git commit -q --allow-empty -m "upstream work" && git push -q origin main)
  local a
  a=$(git rev-parse --short main)
  run hub sync --color=never
  assert_success
  assert_output_lacks $'\e['
  assert_output_equals "Updated branch main (was $a)."
}

@test "sync without a GitHub remote, or with an unknown remote, aborts before fetching" {
  make_repo dotfiles
  run hub sync
  assert_failure
  assert_output_equals "Aborted: no GitHub remote found (looked for upstream, github, origin); name the one to sync: hub sync REMOTE"
  run hub sync nope
  assert_failure
  assert_output_equals "Aborted: no remote named 'nope'"
  assert_gh_not_called
}

@test "sync takes --color and at most one remote, and nothing else" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  local arg
  for arg in '--color=sometimes' '-q' '--quiet' '--color -x'; do
    # shellcheck disable=SC2086
    run hub --noop sync $arg
    assert_failure
    assert_output_equals "Usage: hub sync [--color[=WHEN]] [REMOTE]"
  done
  run hub --noop sync origin upstream
  assert_failure
  assert_output_equals "Usage: hub sync [--color[=WHEN]] [REMOTE]"
  assert_gh_not_called
}

@test "sync outside a repository aborts" {
  run hub sync
  assert_failure
  assert_output_contains "not a git repository"
}

@test "sync --help prints the manual" {
  run hub sync --help
  assert_success
  assert_output_contains "Usage: hub sync [--color[=WHEN]] [REMOTE]"
  run hub sync -h
  assert_success
  assert_output_contains "Usage: hub sync [--color[=WHEN]] [REMOTE]"
}

@test "sync leaves a branch deleted upstream alone when the remote's default branch is unknown" {
  make_sync_fixture
  git remote set-head origin -d
  git config remote.origin.followRemoteHEAD never # git 2.48+ would set refs/remotes/origin/HEAD again when fetching
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' '' 1
  local merged unmerged
  merged=$(tip merged) unmerged=$(tip unmerged)
  run hub sync
  assert_success
  assert_output_contains "warning: 'merged' was deleted on origin, but the default branch of origin is not known (git remote set-head origin -a); leaving it alone"
  assert_output_contains "warning: 'unmerged' was deleted on origin, but the default branch of origin is not known"
  assert_output_lacks "Deleted branch"
  [[ $(tip merged) == "$merged" && $(tip unmerged) == "$unmerged" ]]
  # everything else is synced as always
  assert_output_contains "Updated branch behind"
  assert_equals "$(tip behind)" "$(server_ref mislav/dotfiles behind)"
}
