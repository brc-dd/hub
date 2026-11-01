#!/usr/bin/env bats
# hub push: one git push per remote of a comma-separated list.

load test_helper

# A clone of mislav/one on branch feature, one commit ahead of main, with remote two.
setup_push() {
  serve_github mislav/one mislav/two "$@"
  clone_served mislav/one work
  git remote add two https://github.com/mislav/two.git
  git switch -q -c feature
  git commit -q --allow-empty -m 'feature work'
}

@test "hub push with a list alone pushes the current branch to every remote" {
  setup_push
  run hub push origin,two
  assert_success
  assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
  assert_gh_not_called
}

@test "hub push pushes the branch, not a tag of the same name" {
  setup_push
  git tag feature HEAD~1
  run hub push origin,two
  assert_success
  assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref mislav/one refs/tags/feature)" ''
  assert_equals "$(server_ref mislav/two refs/tags/feature)" ''
}

@test "hub push pushes to the remotes in the list's order" {
  setup_push
  printf '#!/bin/sh\nexit 1\n' >"$(server_dir mislav/two)/hooks/pre-receive"
  chmod +x "$(server_dir mislav/two)/hooks/pre-receive"
  run hub push two,origin
  assert_status 1
  assert_equals "$(server_ref mislav/two refs/heads/feature)" ''
  assert_equals "$(server_ref mislav/one refs/heads/feature)" ''
}

@test "hub push keeps refspecs and options before and after the list for every remote" {
  setup_push
  run hub push -q origin,two main:refs/heads/renamed feature
  assert_success
  assert_output_equals ''
  assert_equals "$(server_ref mislav/one refs/heads/renamed)" "$(tip main)"
  assert_equals "$(server_ref mislav/two refs/heads/renamed)" "$(tip main)"
  assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
}

@test "hub push gives options after a list alone to every push, with HEAD" {
  setup_push
  run hub push origin,two --set-upstream
  assert_success
  assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
  assert_equals "$(git config branch.feature.remote)" two
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
}

@test "hub push takes a list after -- and after the value of a valued option" {
  setup_push
  git -C "$(server_dir mislav/one)" config receive.advertisePushOptions true
  git -C "$(server_dir mislav/two)" config receive.advertisePushOptions true
  run hub push -o ci.skip,fast -- origin,two main:refs/heads/copy
  assert_success
  assert_equals "$(server_ref mislav/one refs/heads/copy)" "$(tip main)"
  assert_equals "$(server_ref mislav/two refs/heads/copy)" "$(tip main)"
}

@test "hub push adds no HEAD when an option chooses the refs" {
  setup_push
  git tag v1
  run hub push --tags origin,two
  assert_success
  assert_equals "$(server_ref mislav/one refs/tags/v1)" "$(tip feature)"
  assert_equals "$(server_ref mislav/two refs/tags/v1)" "$(tip feature)"
  assert_equals "$(server_ref mislav/one refs/heads/feature)" ''
  assert_equals "$(server_ref mislav/two refs/heads/feature)" ''
}

@test "hub push takes every separate value of the push table before the list" {
  setup_push
  git -C "$(server_dir mislav/one)" config receive.advertisePushOptions true
  git -C "$(server_dir mislav/two)" config receive.advertisePushOptions true
  run hub push --push-option ci.skip --recurse-submodules no --exec git-receive-pack origin,two
  assert_success
  assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
}

@test "hub push adds HEAD when an option's value looks like a ref-choosing option" {
  setup_push
  git config push.default matching
  git push -q origin main
  git push -q two main
  commit_on main 'unpushed on main'
  git -C "$(server_dir mislav/one)" config receive.advertisePushOptions true
  git -C "$(server_dir mislav/two)" config receive.advertisePushOptions true
  local option
  for option in --tags --delete -d; do
    run hub push -o "$option" origin,two
    assert_success
    assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
    assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
    assert_equals "$(server_ref mislav/one refs/heads/main)" "$(tip main~1)"
    assert_equals "$(server_ref mislav/two refs/heads/main)" "$(tip main~1)"
  done
  run hub push -od origin,two
  assert_success
  assert_equals "$(server_ref mislav/two refs/heads/main)" "$(tip main~1)"
}

@test "hub push adds no HEAD with --all, --branches or --mirror" {
  setup_push
  local option branch
  for option in --all --branches --mirr; do
    branch=side${option#--}
    git branch "$branch" main
    run hub push "$option" origin,two
    assert_success
    assert_equals "$(server_ref mislav/one "refs/heads/$branch")" "$(tip main)"
    assert_equals "$(server_ref mislav/two "refs/heads/$branch")" "$(tip main)"
    assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
  done
}

@test "hub push adds no HEAD for a remote with its own push refspec or mirroring" {
  setup_push mislav/three
  git remote add three https://github.com/mislav/three.git
  git config remote.two.push refs/heads/main:refs/heads/from-main
  git config remote.three.mirror true
  git branch side main
  run hub push origin,two,three
  assert_success
  assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches mislav/two)" "$(printf '%s\n' from-main main)"
  assert_equals "$(server_ref mislav/three refs/heads/side)" "$(tip side)"
  assert_equals "$(server_ref mislav/three refs/heads/feature)" "$(tip feature)"
}

@test "hub push --delete with a list alone deletes nothing" {
  setup_push
  git push -q origin feature
  git push -q two feature
  local option
  for option in --delete --del -d -qd; do
    run hub push "$option" origin,two
    assert_status 128
    assert_output_contains "fatal: --delete doesn't make sense without any refs"
    assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
    assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
  done
}

@test "hub push --delete with a list and a branch deletes it on every remote" {
  setup_push
  git push -q origin feature
  git push -q two feature
  run hub push origin,two --delete feature
  assert_success
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push stops at the first push that fails, with its status" {
  setup_push mislav/three
  git remote add gone https://github.com/mislav/missing.git
  git remote add three https://github.com/mislav/three.git
  run hub push origin,gone,three
  assert_status 128
  assert_output_contains 'nothing is served at https://github.com/mislav/missing.git'
  assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref mislav/three refs/heads/feature)" ''
}

@test "hub push on a detached HEAD gets git's refusal from the first remote" {
  setup_push
  git checkout -q --detach
  run hub push origin,two
  assert_status 1
  assert_output_contains 'You must fully qualify the ref'
  assert_output_lacks 'mislav/two'
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push refuses a list with an empty name before pushing" {
  setup_push
  local list
  for list in origin,,two 'origin,' ,two; do
    run hub push "$list"
    assert_status 1
    assert_output_equals "hub push: empty name in the list: $list"
  done
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push refuses an option inside the list before pushing" {
  setup_push
  run hub push origin,--mirror main
  assert_status 1
  assert_output_equals 'hub push: not a remote name: --mirror (write options outside the list)'
  run hub push origin,-f,two main
  assert_status 1
  assert_output_equals 'hub push: not a remote name: -f (write options outside the list)'
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push refuses a name that is not a remote before pushing" {
  setup_push
  run hub push origin,staging,two
  assert_status 1
  assert_output_equals 'hub push: not a remote: staging'
  run hub push 'origin,x y'
  assert_status 1
  assert_output_equals 'hub push: not a remote: x\ y'
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push takes a remote whose name contains a comma as one destination" {
  setup_push mislav/three
  git remote add one,two https://github.com/mislav/three.git
  run hub push one,two feature
  assert_success
  assert_equals "$(server_ref mislav/three refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push takes a path with a comma as one destination" {
  setup_push
  git init -q --bare ../dest,backup
  run hub push ../dest,backup feature
  assert_success
  assert_equals "$(git -C ../dest,backup rev-parse refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches mislav/one)" main
}

@test "hub push takes a repository named STR.git as the destination STR" {
  setup_push
  git init -q --bare ../dest,backup.git
  run hub push ../dest,backup feature
  assert_success
  assert_equals "$(git -C ../dest,backup.git rev-parse refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches mislav/one)" main
}

@test "hub push from a subdirectory takes a path at the top as one destination" {
  setup_push
  git init -q --bare origin,two
  mkdir sub
  cd sub
  run hub push origin,two feature
  assert_success
  assert_equals "$(git -C ../origin,two rev-parse refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push takes a URL with a comma as one destination" {
  setup_push 'mislav/a,b'
  run hub push https://github.com/mislav/a,b.git feature
  assert_success
  assert_equals "$(server_ref 'mislav/a,b' refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches mislav/one)" main
}

@test "hub push without a list is plain git push" {
  setup_push
  run hub push two feature
  assert_success
  assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_branches mislav/one)" main
  git push -q -u origin feature
  git commit -q --allow-empty -m 'more work'
  run hub push
  assert_success
  assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
}

@test "hub push hands a comma value of an option to git" {
  setup_push
  run hub push --repo origin,two
  assert_failure
  assert_output_contains "'origin,two' does not appear to be a git repository"
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push hands an unclear command line to git untouched" {
  setup_push
  run hub push origin,two --receive-pack
  assert_status 129
  assert_output_contains 'requires a value'
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub push hands an abbreviated valued option or a cluster ending in -o to git" {
  setup_push
  run hub --noop push --recu no origin,two
  assert_success
  assert_output_equals 'git push --recu no origin\,two'
  run hub --noop push -qo ci.skip origin,two
  assert_success
  assert_output_equals 'git push -qo ci.skip origin\,two'
}

@test "hub push takes a list after --end-of-options" {
  setup_push
  run hub push --end-of-options origin,two
  assert_success
  assert_equals "$(server_ref mislav/one refs/heads/feature)" "$(tip feature)"
  assert_equals "$(server_ref mislav/two refs/heads/feature)" "$(tip feature)"
}

@test "hub push -h is git's usage even for a list naming a missing remote" {
  setup_push
  run hub push origin,nope -h
  assert_status 129
  assert_line_equals 0 'usage: git push [<options>] [<repository> [<refspec>...]]'
  run hub push -qh origin,nope
  assert_status 129
  assert_line_equals 0 'usage: git push [<options>] [<repository> [<refspec>...]]'
}

@test "hub push --help and -h are git's" {
  setup_push
  run hub -c man.viewer=record -c 'man.record.cmd=echo manual' push --help
  assert_success
  assert_output_equals 'manual git-push'
  run hub push origin,two -h
  assert_status 129
  assert_line_equals 0 'usage: git push [<options>] [<repository> [<refspec>...]]'
  assert_equals "$(server_branches mislav/one)" main
}

@test "hub push with a list outside a repository gets git's message" {
  run hub push origin,two
  assert_status 128
  assert_output_contains 'fatal: not a git repository'
}

@test "hub --noop push prints one git push per remote and pushes nothing" {
  setup_push
  run hub --noop push -f origin,two
  assert_success
  assert_line_equals 0 'git push -f origin HEAD'
  assert_line_equals 1 'git push -f two HEAD'
  assert_equals "${#lines[@]}" 2
  assert_equals "$(server_branches mislav/one)" main
  assert_equals "$(server_branches mislav/two)" main
}

@test "hub help push prints the manual, which points at git's" {
  run hub help push
  assert_success
  assert_line_equals 0 'Summary: Push to several remotes at once.'
  assert_line_equals 1 'Usage: hub push REMOTE1,REMOTE2[,...] [GIT-PUSH-ARGS...]'
  assert_equals "${lines[${#lines[@]} - 1]}" "git's own manual: git push --help"
}
