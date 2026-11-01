#!/usr/bin/env bats
# script/bump: the version commit and tag, in a scratch checkout with a copy of the script.

load test_helper

setup() {
  hub_test_setup
  make_repo work
  mkdir script
  cp "$HUB_TEST_ROOT/script/bump" script/
  echo 0.1.0 >VERSION
  write_changelog '### Fixed

- A fix.'
  git add -A
  git commit -q -m 'add the tooling'
  today=$(date +%Y-%m-%d)
}

# write_changelog NOTES : CHANGELOG.md with NOTES under Unreleased and a 0.1.0 section.
write_changelog() {
  cat >CHANGELOG.md <<EOF
# Changelog

## [Unreleased]

$1

## [0.1.0] - 2026-10-29

- The first release.

[Unreleased]: https://github.com/brc-dd/hub/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/brc-dd/hub/releases/tag/v0.1.0
EOF
}

# assert_unchanged : no commit, no tag, VERSION and CHANGELOG.md as committed.
assert_unchanged() {
  assert_equals "$(git log --format=%s -1)" 'add the tooling'
  assert_equals "$(git tag -l)" ''
  assert_equals "$(git status --porcelain)" ''
}

@test "bump moves the notes, writes VERSION, commits and makes an annotated tag" {
  run script/bump 0.2.0
  assert_success
  assert_equals "$(<VERSION)" 0.2.0
  assert_equals "$(<CHANGELOG.md)" "# Changelog

## [Unreleased]

## [0.2.0] - $today

### Fixed

- A fix.

## [0.1.0] - 2026-10-29

- The first release.

[Unreleased]: https://github.com/brc-dd/hub/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/brc-dd/hub/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/brc-dd/hub/releases/tag/v0.1.0"
  assert_equals "$(git log --format=%s -1)" 'hub v0.2.0'
  assert_equals "$(git show --name-only --format= HEAD)" $'CHANGELOG.md\nVERSION'
  assert_equals "$(git cat-file -t refs/tags/v0.2.0)" tag
  assert_equals "$(git rev-parse 'v0.2.0^{commit}')" "$(git rev-parse HEAD)"
  assert_equals "$(git tag -l --format='%(contents:subject)' v0.2.0)" 'hub v0.2.0'
  assert_equals "$(git status --porcelain)" ''
}

@test "bump accepts a leading v and a pre-release" {
  run script/bump v1.0.0-rc.1
  assert_success
  assert_equals "$(<VERSION)" 1.0.0-rc.1
  assert_equals "$(git cat-file -t refs/tags/v1.0.0-rc.1)" tag
  run grep -c "^## \[1.0.0-rc.1\] - $today\$" CHANGELOG.md
  assert_output_equals 1
}

@test "bump keeps notes that come right after the heading" {
  write_changelog '- A fix.'
  sed -i.orig '/^## \[Unreleased\]$/{n;d;}' CHANGELOG.md
  rm CHANGELOG.md.orig
  git commit -q -am 'no blank line'
  run script/bump 0.2.0
  assert_success
  run sed -n '3,7p' CHANGELOG.md
  assert_output_equals "## [Unreleased]

## [0.2.0] - $today

- A fix."
}

@test "bump --dry-run prints the changes and the commands, and changes nothing" {
  run script/bump --dry-run 0.2.0
  assert_success
  assert_line_equals 0 '[dry-run] VERSION: 0.1.0 -> 0.2.0'
  assert_output_contains "+## [0.2.0] - $today"
  assert_output_contains '+[0.2.0]: https://github.com/brc-dd/hub/compare/v0.1.0...v0.2.0'
  assert_output_contains $'\n[dry-run] git add VERSION CHANGELOG.md
[dry-run] git commit -q -m hub\\ v0.2.0
[dry-run] git tag -a v0.2.0 -m hub\\ v0.2.0'
  assert_equals "$(<VERSION)" 0.1.0
  assert_unchanged
}

@test "bump -s makes a signed tag" {
  run script/bump -n -s 0.2.0
  assert_success
  assert_output_contains '[dry-run] git tag -s v0.2.0 -m hub\ v0.2.0'
}

@test "bump refuses an empty Unreleased section" {
  write_changelog ''
  git commit -q -am 'add the tooling'
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: CHANGELOG.md has no notes under "## [Unreleased]"'
  assert_equals "$(git tag -l)" ''
  assert_equals "$(<VERSION)" 0.1.0
}

@test "bump refuses an Unreleased section holding only empty subheadings" {
  write_changelog '### Changed

### Fixed'
  git commit -q -am 'add the tooling'
  run script/bump --dry-run 0.2.0
  assert_failure
  assert_output_equals 'script/bump: CHANGELOG.md has no notes under "## [Unreleased]"'
}

@test "bump refuses an Unreleased section that is last and empty" {
  printf '# Changelog\n\n## [Unreleased]\n\n' >CHANGELOG.md
  git commit -q -am 'add the tooling'
  run script/bump --dry-run 0.2.0
  assert_failure
  assert_output_equals 'script/bump: CHANGELOG.md has no notes under "## [Unreleased]"'
}

@test "bump refuses a changelog without the Unreleased heading or link" {
  sed -i.orig 's/^## \[Unreleased\]$/## Unreleased/' CHANGELOG.md
  rm CHANGELOG.md.orig
  git commit -q -am 'add the tooling'
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: CHANGELOG.md has no "## [Unreleased]" heading'
  write_changelog '- A fix.'
  sed -i.orig '/^\[Unreleased\]: /d' CHANGELOG.md
  rm CHANGELOG.md.orig
  git commit -q -am 'add the tooling'
  run script/bump 0.2.0
  assert_failure
  assert_output_contains 'CHANGELOG.md has no "[Unreleased]: URL/compare/vX.Y.Z...HEAD" link'
  assert_unchanged
}

@test "bump refuses an existing tag" {
  git tag v0.2.0
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: tag v0.2.0 exists already'
  assert_equals "$(<VERSION)" 0.1.0
}

@test "bump refuses a branch other than main" {
  git switch -q -c topic
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: not on main (git switch main)'
  git switch -q --detach main
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: not on main (git switch main)'
}

@test "bump works on main while a tag is named main" {
  git tag main
  run script/bump 0.2.0
  assert_success
  assert_equals "$(<VERSION)" 0.2.0
  assert_equals "$(git cat-file -t refs/tags/v0.2.0)" tag
}

@test "bump stays in its own checkout under an exported CDPATH" {
  mkdir -p "$HUB_TEST_TMP/decoy/script"
  echo 9.9.9 >"$HUB_TEST_TMP/decoy/VERSION"
  export CDPATH=$HUB_TEST_TMP/decoy
  run script/bump 0.2.0
  assert_success
  assert_output_equals ''
  assert_equals "$(<VERSION)" 0.2.0
  assert_equals "$(<"$HUB_TEST_TMP/decoy/VERSION")" 9.9.9
}

@test "bump refuses a working tree with changes or untracked files" {
  echo change >>VERSION
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: the working tree is not clean (git status)'
  git checkout -q VERSION
  touch untracked
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: the working tree is not clean (git status)'
  git config status.showUntrackedFiles no
  run script/bump 0.2.0
  assert_failure
  assert_output_equals 'script/bump: the working tree is not clean (git status)'
  rm untracked
  assert_unchanged
}

@test "bump says how to undo when a hook or signing fails after the writes" {
  local start
  start=$(git rev-parse HEAD)
  printf '#!/bin/sh\nexit 1\n' >.git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  run script/bump 0.2.0
  assert_failure
  assert_output_equals "script/bump: stopped; git reset --hard $start undoes it"
  assert_equals "$(git diff --cached --name-only)" $'CHANGELOG.md\nVERSION'
  rm .git/hooks/pre-commit
  git reset -q --hard "$start"
  git config gpg.program false
  run script/bump -s 0.2.0
  assert_failure
  assert_line_equals -1 "script/bump: stopped; git reset --hard $start undoes it"
  assert_equals "$(git log --format=%s -1)" 'hub v0.2.0'
  git reset -q --hard "$start"
  assert_unchanged
}

@test "bump refuses versions that are not SemVer" {
  local bad
  for bad in 1.02.0 1.0 1.0.0+build 1.0.0-01 1.0.0- x.y.z; do
    run script/bump "$bad"
    assert_failure
    assert_output_equals "script/bump: not a X.Y.Z or X.Y.Z-PRE version: $bad"
  done
  assert_unchanged
}

@test "bump refuses unknown options, two versions and none" {
  run script/bump --bogus 0.2.0
  assert_failure
  assert_line_equals 0 'script/bump: unknown option: --bogus'
  assert_line_equals 1 'Usage: script/bump [-n] [-s] VERSION'
  run script/bump 0.2.0 0.3.0
  assert_failure
  assert_line_equals 0 'script/bump: unexpected argument: 0.3.0'
  run script/bump
  assert_failure
  assert_line_equals 0 'script/bump: no version given'
  assert_unchanged
}

@test "bump --help prints the header" {
  run script/bump --help
  assert_success
  assert_line_equals 0 'Summary: Commit and tag a new version of hub.'
  assert_line_equals 1 'Usage: script/bump [-n] [-s] VERSION'
}
