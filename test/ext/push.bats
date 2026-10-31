#!/usr/bin/env bats
load ../test_helper

# serve_github OWNER/REPO makes https://github.com/OWNER/REPO.git a local bare repository, so the
# pushes run for real and the served repositories' refs show what was sent.
@test "push to multiple remotes pushes the current branch to each" {
  serve_github me/r me/r2
  clone_served me/r
  git remote add two https://github.com/me/r2.git
  git checkout -q -b cool-feature && git commit -q --allow-empty -m work
  run hub push origin,two
  assert_success
  assert_equals "$(server_ref me/r cool-feature)" "$(git rev-parse HEAD)"
  assert_equals "$(server_ref me/r2 cool-feature)" "$(git rev-parse HEAD)"
  run hub --noop push origin,staging,qa
  assert_success
  assert_output_equals $'git push origin refs/heads/cool-feature\ngit push staging refs/heads/cool-feature\ngit push qa refs/heads/cool-feature'
  assert_gh_not_called
}

@test "push to multiple remotes pushes the current branch when a tag has its name" {
  serve_github me/r me/r2
  clone_served me/r
  git remote add two https://github.com/me/r2.git
  git checkout -q -b topic && git commit -q --allow-empty -m work
  git tag topic HEAD~1 # the short name topic is ambiguous for git
  run hub push origin,two
  assert_success
  assert_equals "$(server_ref me/r refs/heads/topic)" "$(git rev-parse HEAD)"
  assert_equals "$(server_ref me/r2 refs/heads/topic)" "$(git rev-parse HEAD)"
  [[ -z $(server_ref me/r refs/tags/topic) && -z $(server_ref me/r2 refs/tags/topic) ]]
  run hub --noop push origin,two
  assert_success
  assert_output_equals $'git push origin refs/heads/topic\ngit push two refs/heads/topic'
}

@test "push to multiple remotes with a refspec, and with options before and after the list" {
  serve_github me/r me/r2
  clone_served me/r
  git remote add two https://github.com/me/r2.git
  git commit -q --allow-empty -m work
  run hub push -q origin,two main:renamed
  assert_success
  assert_equals "$(server_ref me/r renamed)" "$(git rev-parse HEAD)"
  assert_equals "$(server_ref me/r2 renamed)" "$(git rev-parse HEAD)"
  git tag v1
  run hub push --tags origin,two --quiet
  assert_success
  assert_equals "$(server_ref me/r v1)" "$(git rev-parse HEAD)"
  assert_equals "$(server_ref me/r2 v1)" "$(git rev-parse HEAD)"
  run hub --noop push origin,staging,qa cool-feature
  assert_success
  assert_output_equals $'git push origin cool-feature\ngit push staging cool-feature\ngit push qa cool-feature'
}

@test "push options are passed on as given, without adding the current branch" {
  make_repo dotfiles
  run hub --noop push origin,staging --force-with-lease
  assert_success
  assert_output_equals $'git push origin --force-with-lease\ngit push staging --force-with-lease'
  run hub --noop push origin,staging --delete
  assert_success
  assert_output_equals $'git push origin --delete\ngit push staging --delete'
  local opt
  for opt in --tags --all --mirror; do
    run hub --noop push origin,staging "$opt"
    assert_success
    assert_output_equals "git push origin $opt"$'\n'"git push staging $opt"
  done
}

@test "push keeps every argument and its order, option values included" {
  make_repo dotfiles
  run hub --noop push origin,staging --push-option ci.skip --dry-run HEAD
  assert_success
  assert_output_equals $'git push origin --push-option ci.skip --dry-run HEAD\ngit push staging --push-option ci.skip --dry-run HEAD'
  run hub --noop push origin,staging -o 'a b,c' -- main:main
  assert_success
  assert_output_equals $'git push origin -o a\\ b\\,c -- main:main\ngit push staging -o a\\ b\\,c -- main:main'
  # the values of options before the list are never taken for the list
  run hub --noop push --repo elsewhere -o x --recurse-submodules check origin,staging main
  assert_success
  assert_output_equals $'git push --repo elsewhere -o x --recurse-submodules check origin main\ngit push --repo elsewhere -o x --recurse-submodules check staging main'
  run hub --noop push -qo x origin,staging # not the list alone: no branch is added
  assert_success
  assert_output_equals $'git push -qo x origin\ngit push -qo x staging'
}

@test "push with a single remote or no arguments is plain git push" {
  run hub --noop push origin cool-feature
  assert_success
  assert_output_equals "git push origin cool-feature"
  run hub --noop push
  assert_success
  assert_output_equals "git push"
  run hub --noop push --tags
  assert_output_equals "git push --tags"
}

@test "an option with a comma in it is not a list of remotes" {
  make_repo dotfiles
  run hub --noop push --push-option=a,b origin main
  assert_success
  assert_output_equals "git push --push-option=a,b origin main"
  run hub --noop push -o a,b origin main
  assert_output_equals "git push -o a,b origin main"
  run hub --noop push --repo a,b main
  assert_output_equals "git push --repo a,b main"
  # -- only ends the options: the repository operand after it is still the list
  run hub --noop push -- a,b main
  assert_output_equals $'git push -- a main\ngit push -- b main'
}

@test "a list member that is empty or starts with - is refused before anything is pushed" {
  make_repo work
  # a remote named like the current branch, so that a `git push --mirror main` would have a destination
  git init -q --bare "$HUB_TEST_TMP/one.git" && git init -q --bare "$HUB_TEST_TMP/secondary.git"
  git remote add one "$HUB_TEST_TMP/one.git"
  git remote add main "$HUB_TEST_TMP/secondary.git"
  git push -q main HEAD:keep-me
  git branch local-only
  local list
  for list in one,--mirror one,--delete one,-f ',one' 'one,' 'one,,main'; do
    run hub push "$list"
    assert_failure
    assert_output_contains "hub push: "
    assert_output_contains "'$list'"
    run hub push "$list" main
    assert_failure
  done
  assert_equals "$(git -C "$HUB_TEST_TMP/secondary.git" for-each-ref --format='%(refname:short)' refs/heads)" keep-me
  [[ -z $(git -C "$HUB_TEST_TMP/one.git" for-each-ref) ]]
  assert_gh_not_called
}

@test "an existing remote, path or URL with a comma in it is one destination, never a list" {
  make_repo work
  local r
  for r in one two both; do git init -q --bare "$HUB_TEST_TMP/$r.git"; done
  git remote add one "$HUB_TEST_TMP/one.git"
  git remote add two "$HUB_TEST_TMP/two.git"
  git remote add one,two "$HUB_TEST_TMP/both.git"
  run hub push one,two main
  assert_success
  assert_equals "$(git -C "$HUB_TEST_TMP/both.git" rev-parse refs/heads/main)" "$(git rev-parse HEAD)"
  [[ -z $(git -C "$HUB_TEST_TMP/one.git" for-each-ref) && -z $(git -C "$HUB_TEST_TMP/two.git" for-each-ref) ]]
  git init -q --bare "$HUB_TEST_TMP/dest,backup"
  run hub push "$HUB_TEST_TMP/dest,backup" main
  assert_success
  assert_equals "$(git -C "$HUB_TEST_TMP/dest,backup" rev-parse refs/heads/main)" "$(git rev-parse HEAD)"
  run hub push "../dest,backup" main:relative
  assert_success
  assert_equals "$(git -C "$HUB_TEST_TMP/dest,backup" rev-parse refs/heads/relative)" "$(git rev-parse HEAD)"
  run hub push "file://$HUB_TEST_TMP/dest,backup" main:via-url
  assert_success
  assert_equals "$(git -C "$HUB_TEST_TMP/dest,backup" rev-parse refs/heads/via-url)" "$(git rev-parse HEAD)"
  run hub --noop push git@github.com:me/a,b.git main
  assert_output_equals "git push git@github.com:me/a,b.git main"
  [[ -z $(git -C "$HUB_TEST_TMP/one.git" for-each-ref) && -z $(git -C "$HUB_TEST_TMP/two.git" for-each-ref) ]]
}

@test "push to multiple remotes from a detached HEAD aborts" {
  make_repo dotfiles
  git checkout -q --detach
  run hub --noop push origin,staging
  assert_failure
  assert_output_contains "Aborted: not currently on any branch."
}

@test "push stops at the first remote that fails" {
  make_repo dotfiles
  git init -q --bare "$HUB_TEST_TMP/good.git"
  git remote add good "$HUB_TEST_TMP/good.git"
  git remote add bad "$HUB_TEST_TMP/does-not-exist.git"
  git init -q --bare "$HUB_TEST_TMP/never.git"
  git remote add never "$HUB_TEST_TMP/never.git"
  run hub push good,bad,never main
  assert_failure
  git -C "$HUB_TEST_TMP/good.git" rev-parse --verify -q refs/heads/main
  run git -C "$HUB_TEST_TMP/never.git" rev-parse --verify -q refs/heads/main
  assert_failure
}

@test "push --delete without a ref is left for git to refuse, and deletes nothing" {
  make_repo dotfiles
  local r
  for r in one two; do
    git init -q --bare "$HUB_TEST_TMP/$r.git"
    git remote add "$r" "$HUB_TEST_TMP/$r.git"
    git push -q "$r" main
  done
  run hub push one,two --delete
  assert_failure
  assert_output_contains "--delete doesn't make sense without any refs"
  git -C "$HUB_TEST_TMP/one.git" rev-parse --verify -q refs/heads/main
  git -C "$HUB_TEST_TMP/two.git" rev-parse --verify -q refs/heads/main
}

@test "push --help prints the manual; -h is git's" {
  run hub push --help
  assert_success
  assert_line_equals 0 "Summary: Push to several remotes at once."
  assert_output_contains "Usage: hub push REMOTE1,REMOTE2[,...]"
  run hub --noop push -h
  assert_output_equals "git push -h"
}
