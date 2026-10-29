#!/usr/bin/env bats
load ../test_helper

@test "compare opens the current branch's compare page" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD # pushed to origin, no upstream set
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
  assert_gh_not_called
}

@test "compare finds a branch pushed to its upstream or its push remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  git branch -q --set-upstream-to=origin/feature # git push -u origin feature
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
  # started from origin/main (its upstream), then pushed without -u
  git checkout -q -b topic --track origin/main
  git update-ref refs/remotes/origin/topic HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/topic"
  assert_gh_not_called
}

@test "compare refuses a branch that is not pushed to a GitHub remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git backup=../backup.git
  set_remote_head origin main
  git checkout -q -b feature
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  run hub --noop compare -b develop
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  # an upstream the branch was started from is not where it was pushed
  git checkout -q -b topic --track origin/main
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'topic' is not pushed to any GitHub remote; push it first or name a range"
  # pushed, but to a remote that is not on GitHub
  git config branch.topic.pushRemote backup
  git update-ref refs/remotes/backup/topic HEAD
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'topic' is not pushed to any GitHub remote; push it first or name a range"
  run hub --noop compare main...topic
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/main...topic"
  assert_gh_not_called
}

@test "compare on the default branch explains what to do" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: main is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
}

@test "compare on a detached HEAD explains what to do" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git checkout -q --detach
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: not currently on any branch; name a branch or a BASE...HEAD range to compare."
}

@test "compare turns a two-dot range into GitHub's three-dot form" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare v1.0..v1.1
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/v1.0...v1.1"
  run hub --noop compare v1.0...v1.1
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/v1.0...v1.1"
  run hub --noop compare refactor
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/refactor"
  assert_gh_not_called
}

@test "compare -b BASE compares the current branch or HEAD against BASE" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare -b develop
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/develop...feature"
  run hub --noop compare --base develop topic
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/develop...topic"
  git checkout -q main
  run hub --noop compare --base=release
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/release...main"
}

@test "compare -b refuses a range" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare -b develop a..b
  assert_failure
  assert_output_contains "use either -b BASE or a range"
}

@test "compare -b refuses a BASE that is the head" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare -b feature
  assert_failure
  assert_output_equals "Aborted: 'feature' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare --base topic topic
  assert_failure
  assert_output_equals "Aborted: 'topic' is both the base and the head; name a different BASE or HEAD"
  git checkout -q main
  run hub --noop compare --base=main
  assert_failure
  assert_output_equals "Aborted: 'main' is both the base and the head; name a different BASE or HEAD"
}

@test "compare refuses a range from a ref to itself" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare feature...feature
  assert_failure
  assert_output_equals "Aborted: 'feature' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare v1..v1
  assert_failure
  assert_output_equals "Aborted: 'v1' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare jingweno main...main
  assert_failure
  assert_output_equals "Aborted: 'main' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare main...feature
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/main...feature"
}

@test "compare OWNER RANGE uses OWNER's copy of the repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare jingweno v1..v2
  assert_success
  assert_output_equals "open https://github.com/jingweno/dotfiles/compare/v1...v2"
}

@test "compare writes FORKOWNER:BRANCH when the branch pushes to a fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote mislav
  git config branch.feature.merge refs/heads/feature
  git update-ref refs/remotes/mislav/feature HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/mislav:feature"
  run hub --noop compare -b develop
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/develop...mislav:feature"
  run hub --noop compare -b feature # the same name in another repository is a different branch
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/feature...mislav:feature"
  run hub --noop compare -b mislav:feature
  assert_failure
  assert_output_equals "Aborted: 'mislav:feature' is both the base and the head; name a different BASE or HEAD"
}

@test "compare follows remote.pushDefault to the fork a branch was pushed to" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git config remote.pushDefault mislav
  git checkout -q -b feature --track origin/main
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  git update-ref refs/remotes/mislav/feature HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/mislav:feature"
  assert_gh_not_called
}

@test "compare keeps the plain branch name when it pushes to the same repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote origin
  git config branch.feature.merge refs/heads/feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
}

@test "compare names the head after the main remote when only the main remote has the branch" {
  make_repo repo origin=https://github.com/alice/repo.git upstream=https://github.com/org/repo.git
  set_remote_head upstream main
  git checkout -q -b feature
  git config branch.feature.pushRemote origin # pushed to alice's fork, but there is no origin/feature
  git update-ref refs/remotes/upstream/feature HEAD
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/feature"
  assert_gh_not_called
}

@test "compare writes FORKOWNER:BRANCH when the fork it pushes to has the branch" {
  make_repo repo origin=https://github.com/alice/repo.git upstream=https://github.com/org/repo.git
  set_remote_head upstream main
  git checkout -q -b feature
  git config branch.feature.pushRemote origin
  git update-ref refs/remotes/origin/feature HEAD
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:feature"
  git update-ref refs/remotes/upstream/feature HEAD # the push target's ref comes first
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:feature"
  assert_gh_not_called
}

@test "compare refuses a branch that neither its fork nor the main remote has" {
  make_repo repo origin=https://github.com/alice/repo.git upstream=https://github.com/org/repo.git
  set_remote_head upstream main
  git checkout -q -b feature
  git config branch.feature.pushRemote origin
  git update-ref refs/remotes/origin/other HEAD
  git update-ref refs/remotes/upstream/other HEAD
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
}

@test "compare with GH_REPO names the head after the main remote's copy that has the branch" {
  make_repo repo origin=https://github.com/alice/repo.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  GH_REPO=org/repo run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:feature"
  GH_REPO=github.com/Alice/repo run hub compare -u
  assert_success
  assert_output_equals "https://github.com/Alice/repo/compare/feature"
  # hosts are compared without their ports
  git config --global hub.host ghe.example.com
  git remote set-url origin https://ghe.example.com/alice/repo.git
  GH_REPO=ghe.example.com:8443/org/repo run hub compare -u
  assert_success
  assert_output_equals "https://ghe.example.com:8443/org/repo/compare/alice:feature"
}

@test "compare escapes characters that are special in URLs" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub compare -u 'my#b+x'
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/compare/my%23b%2Bx"
}

@test "compare -u prints and -c copies the URL" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare -u v1..v2
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/compare/v1...v2"
  run hub --noop compare -c v1..v2
  assert_output_equals "copy to clipboard: https://github.com/mislav/dotfiles/compare/v1...v2"
}

@test "compare uses the remote's enterprise host" {
  make_repo app origin=https://ghe.example.com/corp/app.git
  export GH_HOST=ghe.example.com
  run hub --noop compare main...topic
  assert_success
  assert_output_equals "open https://ghe.example.com/corp/app/compare/main...topic"
}

@test "compare in a REPO.wiki repository opens the wiki's compare page" {
  make_repo dotfiles.wiki origin=git@github.com:mislav/dotfiles.wiki.git
  set_remote_head origin main
  run hub --noop compare 1a2b3c..4d5e6f
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki/_compare/1a2b3c...4d5e6f"
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare -b main
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki/_compare/main...feature"
  GH_REPO=cli/cli.wiki run hub compare -u v1...v2
  assert_output_equals "https://github.com/cli/cli/wiki/_compare/v1...v2"
  assert_gh_not_called
}

@test "compare without a GitHub remote fails" {
  make_repo local-only
  run hub --noop compare a..b
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
}

@test "compare rejects unknown options and extra arguments" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub compare --bogus
  assert_failure
  assert_output_contains "unknown option: --bogus"
  run hub compare a b c
  assert_failure
  assert_output_contains "Usage: hub compare"
  run hub compare -b
  assert_failure
  assert_output_contains "needs a BASE"
}

@test "compare --help prints the manual" {
  run hub compare --help
  assert_success
  assert_output_contains "Usage: hub compare [-u] [-c] [-b BASE]"
}
