#!/usr/bin/env bats
load ../test_helper

@test "compare opens the current branch's compare page" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
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
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/mislav:feature"
  run hub --noop compare -b develop
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/develop...mislav:feature"
}

@test "compare keeps the plain branch name when it pushes to the same repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote origin
  git config branch.feature.merge refs/heads/feature
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
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
