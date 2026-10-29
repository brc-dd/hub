#!/usr/bin/env bats
load ../test_helper

# commit_on BRANCH MESSAGE : add an empty commit to BRANCH without checking it out.
commit_on() {
  local tip
  tip=$(git rev-parse "refs/heads/$1")
  git update-ref "refs/heads/$1" "$(git commit-tree -p "$tip" -m "$2" "$tip^{tree}")"
}

# make_sync_fixture : a bare upstream.git; a "seed" clone that stands in for everyone else; and "work", the
# clone under test, left as the current directory with main checked out and a branch in every state sync
# handles. Then upstream moves on: main, behind, diverged and same-name get new commits, merged is merged
# into main and deleted, and unmerged is deleted.
make_sync_fixture() {
  local b
  git init -q --bare "$HUB_TEST_TMP/upstream.git"
  make_repo seed origin="$HUB_TEST_TMP/upstream.git"
  for b in ahead behind diverged merged same-name unmerged uptodate; do git branch "$b"; done
  commit_on merged "merged work"
  commit_on unmerged "unmerged work"
  git push -q origin --all

  git clone -q "$HUB_TEST_TMP/upstream.git" "$HUB_TEST_TMP/work"
  cd "$HUB_TEST_TMP/work" || return 1
  for b in ahead behind diverged merged unmerged uptodate; do git branch -q --track "$b" "origin/$b"; done
  git branch -q --no-track same-name origin/same-name
  git branch -q local-only
  commit_on ahead "local work"
  commit_on diverged "local work"

  cd "$HUB_TEST_TMP/seed" || return 1
  for b in main behind diverged same-name; do commit_on "$b" "upstream work"; done
  git merge -q --no-ff -m "Merge branch 'merged'" merged
  git push -q origin main behind diverged same-name
  git push -q origin --delete merged unmerged
  cd "$HUB_TEST_TMP/work" || return 1
}

# tip BRANCH : the commit BRANCH points at.
tip() { git rev-parse --verify -q "refs/heads/$1"; }

@test "sync fast-forwards branches that are behind, deletes merged ones and warns about the rest" {
  make_sync_fixture
  local main behind merged same_name ahead diverged unmerged local_only
  main=$(git rev-parse --short main) behind=$(git rev-parse --short behind)
  merged=$(git rev-parse --short merged) same_name=$(git rev-parse --short same-name)
  ahead=$(tip ahead) diverged=$(tip diverged) unmerged=$(tip unmerged) local_only=$(tip local-only)
  run hub sync origin
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
    [[ $(tip "$b") == $(git rev-parse "refs/remotes/origin/$b") ]]
  done
  [[ -z $(tip merged) ]]
  [[ $(tip ahead) == "$ahead" && $(tip diverged) == "$diverged" && $(tip unmerged) == "$unmerged" ]]
  [[ $(tip local-only) == "$local_only" ]]
  [[ $(git symbolic-ref --short HEAD) == main && -z $(git status --porcelain) ]]
  # Tracking configuration is left as it was.
  [[ $(git rev-parse --abbrev-ref 'behind@{upstream}') == origin/behind ]]
  [[ -z $(git config branch.same-name.merge) ]]
  assert_gh_not_called
}

@test "sync checks out the default branch before deleting the current branch" {
  make_sync_fixture
  git checkout -q merged
  run hub sync origin
  assert_success
  assert_output_contains "Updated branch main (was "
  assert_output_contains "Deleted branch merged (was "
  [[ $(git symbolic-ref --short HEAD) == main ]]
  [[ $(tip main) == $(git rev-parse refs/remotes/origin/main) ]]
  [[ -z $(tip merged) ]]
}

@test "sync goes on past branches git cannot update or delete, and then fails" {
  make_sync_fixture
  git worktree add -q "$HUB_TEST_TMP/wt-behind" behind
  git worktree add -q "$HUB_TEST_TMP/wt-merged" merged
  local behind merged
  behind=$(tip behind) merged=$(tip merged)
  run hub sync origin
  assert_failure
  assert_output_contains "error: could not fast-forward 'behind' to origin/behind"
  assert_output_contains "error: could not delete 'merged'"
  # The other branches are still dealt with.
  assert_output_contains "warning: 'ahead' seems to contain unpushed commits"
  assert_output_contains "Updated branch main (was "
  assert_output_contains "Updated branch same-name (was "
  assert_output_contains "warning: 'unmerged' was deleted on origin, but appears not merged into 'main'"
  local b
  for b in main same-name; do
    [[ $(tip "$b") == $(git rev-parse "refs/remotes/origin/$b") ]]
  done
  [[ $(tip behind) == "$behind" && $(tip merged) == "$merged" ]]
}

@test "sync fails when it cannot check out the default branch to delete the current one" {
  make_sync_fixture
  git checkout -q merged
  git worktree add -q "$HUB_TEST_TMP/wt-main" main
  run hub sync origin
  assert_failure
  assert_output_contains "error: could not fast-forward 'main' to origin/main"
  assert_output_contains "error: could not check out 'main' to delete 'merged'"
  assert_output_contains "Updated branch behind (was "
  [[ $(tip behind) == $(git rev-parse refs/remotes/origin/behind) ]]
  [[ $(git symbolic-ref --short HEAD) == merged && -n $(tip merged) ]]
}

@test "sync --noop prints the commands that would change branches and changes nothing" {
  make_sync_fixture
  git fetch -q --prune origin
  local before
  before=$(git for-each-ref refs/heads)
  run hub --noop sync origin
  assert_success
  assert_output_equals "git fetch --prune --quiet origin
warning: 'ahead' seems to contain unpushed commits
git branch --force --no-track behind refs/remotes/origin/behind
warning: 'diverged' seems to contain unpushed commits
git merge --ff-only --quiet refs/remotes/origin/main
git branch -D merged
git branch --force --no-track same-name refs/remotes/origin/same-name
warning: 'unmerged' was deleted on origin, but appears not merged into 'main'"
  [[ $(git for-each-ref refs/heads) == "$before" ]]
}

@test "sync finds the default branch when REMOTE/HEAD is missing or points at a deleted branch" {
  make_sync_fixture
  git fetch -q --prune origin
  git remote set-head origin -d
  run hub --noop sync origin
  assert_success
  assert_output_contains $'\ngit branch -D merged\n'
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
  run hub --noop sync origin
  assert_success
  assert_output_contains $'\ngit branch -D merged\n'
  assert_output_contains "appears not merged into 'main'"
}

@test "sync defaults to the main GitHub remote and compares with same-named branches there" {
  make_repo dotfiles origin=https://github.com/me/dotfiles.git upstream=https://github.com/mislav/dotfiles.git
  git update-ref refs/remotes/origin/main HEAD
  git branch -q --set-upstream-to=origin/main main
  git commit -q --allow-empty -m "upstream work"
  git update-ref refs/remotes/upstream/main HEAD
  git reset -q --hard HEAD~1
  run hub --noop sync
  assert_success
  assert_output_equals "git fetch --prune --quiet upstream
git merge --ff-only --quiet refs/remotes/upstream/main"
  assert_gh_not_called
}

@test "sync without a GitHub remote, or with an unknown remote, aborts" {
  make_repo dotfiles
  run hub sync
  assert_failure
  assert_output_contains "Aborted: no GitHub remote found"
  run hub sync nope
  assert_failure
  assert_output_equals "Aborted: no such remote: nope"
  assert_gh_not_called
}

@test "sync takes at most one remote and no options" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop sync origin upstream
  assert_failure
  assert_output_equals "Usage: hub sync [REMOTE]"
  run hub --noop sync --color
  assert_failure
  assert_output_equals "Usage: hub sync [REMOTE]"
}

@test "sync outside a repository aborts" {
  run hub sync
  assert_failure
  assert_output_contains "not a git repository"
}

@test "sync --help prints the manual" {
  run hub sync --help
  assert_success
  assert_output_contains "Usage: hub sync [REMOTE]"
}
