#!/usr/bin/env bats
# script/release: the checks and the commands, in a clone of a served brc-dd/hub with a copy of
# the release scripts and a make stub.

load test_helper

zeros=$(printf '0%.0s' {1..64})
view='repo view github.com/brc-dd/hub --json nameWithOwner --jq .nameWithOwner'
push_line='[dry-run] git push --atomic --no-follow-tags origin refs/heads/main:refs/heads/main'
push_line+=' refs/tags/v0.2.0:refs/tags/v0.2.0'

setup() {
  hub_test_setup
  serve_github brc-dd/hub mislav/hub
  clone_served brc-dd/hub
  mkdir script Formula
  cp "$HUB_TEST_ROOT"/script/{bump,release,update-formula} script/
  cat >Formula/hub.rb <<RUBY
class Hub < Formula
  REPO = "brc-dd/hub".freeze

  url "https://github.com/#{REPO}/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "$zeros"
end
RUBY
  echo 0.1.0 >VERSION
  write_changelog '- A fix.'
  git add -A
  git commit -q -m 'add the tooling'
  git push -q origin main
  git tag v0.1.0
  stub_gh "$view" brc-dd/hub
}

# write_changelog NOTES : CHANGELOG.md with NOTES under Unreleased.
write_changelog() {
  printf '%s\n' '# Changelog' '' '## [Unreleased]' '' "$1" '' '## [0.1.0] - 2026-10-29' '' \
    '- The first release.' '' \
    '[Unreleased]: https://github.com/brc-dd/hub/compare/v0.1.0...HEAD' \
    '[0.1.0]: https://github.com/brc-dd/hub/releases/tag/v0.1.0' >CHANGELOG.md
}

release() { script/release "$@"; }

# stub_make STATUS : a make on PATH that logs its arguments to make.log and exits with STATUS.
stub_make() {
  mkdir -p "$HUB_TEST_TMP/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nexit %s\n' \
    "$HUB_TEST_TMP/make.log" "$1" >"$HUB_TEST_TMP/bin/make"
  chmod +x "$HUB_TEST_TMP/bin/make"
  PATH=$HUB_TEST_TMP/bin:$PATH
}

# assert_unchanged : no new tag here or on the server, and the checkout as it was.
assert_unchanged() {
  assert_equals "$(git tag -l)" v0.1.0
  assert_equals "$(server_ref brc-dd/hub refs/tags/v0.2.0)" ''
  assert_equals "$(git status --porcelain)" ''
  assert_equals "$(<VERSION)" 0.1.0
}

# assert_nothing_released : a refusal before any command: no dry-run line, nothing changed.
assert_nothing_released() {
  assert_output_lacks '[dry-run]'
  assert_unchanged
}

@test "release --dry-run makes the checks and prints the commands" {
  run release --dry-run 0.2.0
  assert_success
  assert_line_equals 0 'Releasing hub 0.2.0 to github.com/brc-dd/hub'
  assert_line_equals 1 '[dry-run] make check'
  assert_line_equals 2 '[dry-run] script/bump 0.2.0'
  assert_line_equals 3 "$push_line"
  assert_line_equals 4 "The Release workflow publishes v0.2.0 and points Formula/hub.rb at it \
(gh run watch -R brc-dd/hub)."
  assert_equals "${#lines[@]}" 5
  assert_equals "$(gh_calls)" "gh $view"
  assert_unchanged
}

@test "release runs make check, bumps and pushes main and the tag" {
  stub_make 0
  run release 0.2.0
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/make.log")" check
  assert_equals "$(<VERSION)" 0.2.0
  assert_equals "$(server_ref brc-dd/hub refs/heads/main)" "$(git rev-parse HEAD)"
  assert_equals "$(git -C "$(server_dir brc-dd/hub)" cat-file -t refs/tags/v0.2.0)" tag
  assert_equals "$(server_ref brc-dd/hub refs/tags/v0.2.0)" "$(git rev-parse HEAD)"
  assert_line_equals -1 "The Release workflow publishes v0.2.0 and points Formula/hub.rb at it \
(gh run watch -R brc-dd/hub)."
}

@test "release stops without a tag or a push when make check fails" {
  local before
  before=$(git rev-parse HEAD)
  stub_make 2
  run release 0.2.0
  assert_failure
  assert_equals "$(<"$HUB_TEST_TMP/make.log")" check
  assert_equals "$(git rev-parse HEAD)" "$before"
  assert_equals "$(server_ref brc-dd/hub refs/heads/main)" "$before"
  assert_unchanged
}

@test "release -n of a pre-release says the workflow leaves the formula alone" {
  run release -n v0.2.0-rc.1
  assert_success
  assert_line_equals 2 '[dry-run] script/bump 0.2.0-rc.1'
  assert_output_contains ' refs/tags/v0.2.0-rc.1:refs/tags/v0.2.0-rc.1'
  assert_output_contains 'publishes v0.2.0-rc.1 as a pre-release'
}

@test "release accepts ssh push URLs to the same repository in any case" {
  git remote set-url --push origin git@github.com:BRC-DD/Hub.git
  git remote set-url --add --push origin ssh://git@github.com/brc-dd/hub
  run release -n 0.2.0
  assert_success
  assert_line_equals 3 "$push_line"
}

@test "release refuses a version older than the formula's" {
  run release -n 0.0.9
  assert_failure
  assert_output_equals "script/update-formula: Formula/hub.rb points at v0.1.0, \
which is newer than v0.0.9 (-f to go back)"
  assert_nothing_released
}

@test "release accepts a pre-release of a line older than the formula's" {
  run release -n 0.0.9-rc.1
  assert_success
  assert_output_contains ' refs/tags/v0.0.9-rc.1:refs/tags/v0.0.9-rc.1'
  assert_unchanged
}

@test "release refuses an existing tag" {
  run release -n 0.1.0
  assert_failure
  assert_output_equals 'script/bump: tag v0.1.0 exists already'
  assert_nothing_released
}

@test "release refuses a tag that only origin has" {
  git push -q origin refs/heads/main:refs/tags/v0.2.0
  run release -n 0.2.0
  assert_failure
  assert_output_equals "script/release: origin has the tag v0.2.0 already \
(git fetch origin tag v0.2.0)"
  assert_output_lacks '[dry-run]'
  assert_gh_not_called
}

@test "release refuses a tag origin has off main or that the fetch leaves out" {
  local srv commit
  srv=$(server_dir brc-dd/hub)
  commit=$(git -C "$srv" commit-tree -m unmerged 'refs/heads/main^{tree}')
  git -C "$srv" tag -a -m x v0.2.0 "$commit"
  run release -n 0.2.0
  assert_failure
  assert_output_equals "script/release: origin has the tag v0.2.0 already \
(git fetch origin tag v0.2.0)"
  git -C "$srv" tag -d v0.2.0 >/dev/null
  git -C "$srv" tag v0.3.0 main
  git config remote.origin.tagOpt --no-tags
  run release -n 0.3.0
  assert_failure
  assert_output_equals "script/release: origin has the tag v0.3.0 already \
(git fetch origin tag v0.3.0)"
  assert_output_lacks '[dry-run]'
  assert_equals "$(git tag -l)" v0.1.0
  assert_equals "$(<VERSION)" 0.1.0
  assert_gh_not_called
}

@test "release refuses origin's tag before it bumps anything" {
  local srv commit
  srv=$(server_dir brc-dd/hub)
  commit=$(git -C "$srv" commit-tree -m unmerged 'refs/heads/main^{tree}')
  git -C "$srv" tag v0.2.0 "$commit"
  stub_make 0
  run release 0.2.0
  assert_failure
  assert_output_equals "script/release: origin has the tag v0.2.0 already \
(git fetch origin tag v0.2.0)"
  assert_equals "$(<VERSION)" 0.1.0
  assert_equals "$(git log --format=%s -1)" 'add the tooling'
  assert_equals "$(git tag -l)" v0.1.0
  assert_equals "$(git status --porcelain)" ''
  [[ ! -e $HUB_TEST_TMP/make.log ]]
}

@test "release refuses when origin cannot be asked about the tag" {
  mv "$(server_dir brc-dd/hub)" "$HUB_TEST_TMP/away"
  run release -n 0.2.0
  assert_failure
  assert_line_equals -1 "script/release: cannot ask origin about the tag v0.2.0 \
(git ls-remote origin)"
  assert_nothing_released
  assert_gh_not_called
}

@test "release pushes only main and the tag when push.followTags is set" {
  git config push.followTags true
  git tag -a v0.9.0 -m x
  stub_make 0
  run release 0.2.0
  assert_success
  assert_equals "$(server_ref brc-dd/hub refs/tags/v0.9.0)" ''
  assert_equals "$(git -C "$(server_dir brc-dd/hub)" cat-file -t refs/tags/v0.2.0)" tag
  assert_equals "$(server_ref brc-dd/hub refs/heads/main)" "$(git rev-parse HEAD)"
}

@test "release says how to retry or undo when the push fails" {
  local start hook
  start=$(git rev-parse HEAD)
  hook=$(server_dir brc-dd/hub)/hooks/pre-receive
  printf '#!/bin/sh\necho protected >&2\nexit 1\n' >"$hook"
  chmod +x "$hook"
  stub_make 0
  run release 0.2.0
  assert_failure
  assert_line_equals -1 "script/release: the push failed (retry with git push --atomic \
--no-follow-tags origin refs/heads/main:refs/heads/main refs/tags/v0.2.0:refs/tags/v0.2.0, \
or undo the bump with git tag -d v0.2.0 && git reset --hard $start)"
  assert_equals "$(server_ref brc-dd/hub refs/heads/main)" "$start"
  git tag -d v0.2.0 >/dev/null && git reset -q --hard "$start"
  assert_unchanged
}

@test "release refuses an empty Unreleased section" {
  write_changelog ''
  git commit -q -am 'no notes'
  git push -q origin main
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/bump: CHANGELOG.md has no notes under "## [Unreleased]"'
  assert_nothing_released
}

@test "release refuses a version that is not SemVer" {
  run release -n 1.02.0
  assert_failure
  assert_output_equals 'script/release: not a X.Y.Z or X.Y.Z-PRE version: 1.02.0'
  run release -n vv0.2.0-rc.1
  assert_failure
  assert_output_equals 'script/release: not a X.Y.Z or X.Y.Z-PRE version: v0.2.0-rc.1'
  assert_nothing_released
  assert_gh_not_called
}

@test "release refuses an origin that is not on github.com" {
  git remote set-url origin https://gitlab.com/brc-dd/hub.git
  run release -n 0.2.0
  assert_failure
  assert_output_equals "script/release: origin's URL https://gitlab.com/brc-dd/hub.git is not \
github.com/brc-dd/hub (releases come from a checkout of brc-dd/hub)"
  assert_nothing_released
  assert_gh_not_called
}

@test "release refuses a local path as origin" {
  git remote set-url origin "$(server_dir brc-dd/hub)"
  run release -n 0.2.0
  assert_failure
  assert_output_contains "script/release: origin's URL $(server_dir brc-dd/hub) is not"
  assert_nothing_released
  assert_gh_not_called
}

@test "release refuses an origin that is another repository on github.com" {
  git remote set-url origin https://github.com/mislav/hub.git
  run release -n 0.2.0
  assert_failure
  assert_output_contains "origin's URL https://github.com/mislav/hub.git is not github.com/brc-dd"
  assert_nothing_released
  assert_gh_not_called
}

@test "release accepts and refuses these push URL spellings" {
  local url
  for url in https://github.com/brc-dd/hub https://github.com/brc-dd/hub.git/ \
    git@github.com:brc-dd/hub ssh://git@github.com/brc-dd/hub.git/; do
    git remote set-url --push origin "$url"
    run release -n 0.2.0
    assert_success
  done
  for url in https://GitHub.com/brc-dd/hub.git ssh://github.com/brc-dd/hub \
    https://github.com/brc-dd/hub/extra git://github.com/brc-dd/hub.git \
    https://github.com.evil.example/brc-dd/hub http://github.com/brc-dd/hub; do
    git remote set-url --push origin "$url"
    run release -n 0.2.0
    assert_failure
    assert_output_equals "script/release: origin's push URL $url is not github.com/brc-dd/hub \
(releases come from a checkout of brc-dd/hub)"
  done
  assert_nothing_released
}

@test "release does not print a token kept in origin's URL" {
  git remote set-url origin https://x-access-token:ghp_SECRET@gitlab.com/brc-dd/hub.git
  run release -n 0.2.0
  assert_failure
  assert_output_equals "script/release: origin's URL https://gitlab.com/brc-dd/hub.git is not \
github.com/brc-dd/hub (releases come from a checkout of brc-dd/hub)"
  assert_gh_not_called
}

@test "release refuses a push URL naming another repository" {
  git remote set-url --push origin https://github.com/mislav/hub.git
  run release -n 0.2.0
  assert_failure
  assert_output_equals "script/release: origin's push URL https://github.com/mislav/hub.git is \
not github.com/brc-dd/hub (releases come from a checkout of brc-dd/hub)"
  assert_nothing_released
  assert_gh_not_called
}

@test "release refuses when one of several push URLs names another repository" {
  git remote set-url --push origin https://github.com/brc-dd/hub.git
  git remote set-url --add --push origin git@github.com:mislav/hub.git
  run release -n 0.2.0
  assert_failure
  assert_output_contains "origin's push URL git@github.com:mislav/hub.git is not"
  assert_nothing_released
  assert_gh_not_called
}

@test "release refuses an insteadOf that sends origin elsewhere" {
  git config url.https://github.com/mislav/.pushInsteadOf https://github.com/brc-dd/
  run release -n 0.2.0
  assert_failure
  assert_output_contains "origin's push URL https://github.com/mislav/hub.git is not"
  assert_nothing_released
}

@test "release refuses a checkout without origin" {
  git remote remove origin
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: no origin remote'
}

@test "release refuses a formula without REPO" {
  sed -i.orig '/REPO = /d' Formula/hub.rb
  rm Formula/hub.rb.orig
  git commit -q -am 'no REPO'
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: Formula/hub.rb does not set REPO'
}

@test "release refuses when gh cannot see the repository" {
  stub_gh "$view" 'HTTP 404: Not Found' 1
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: gh cannot see github.com/brc-dd/hub (gh auth status)'
  assert_nothing_released
}

@test "release refuses a main that is behind origin/main" {
  git clone -q https://github.com/brc-dd/hub.git ../other
  git -C ../other commit -q --allow-empty -m 'elsewhere'
  git -C ../other push -q origin main
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: main is behind origin/main (git pull --rebase origin main)'
  assert_nothing_released
  assert_gh_not_called
}

@test "release refuses a stale origin/main when origin's fetch refspec is narrowed" {
  git clone -q https://github.com/brc-dd/hub.git ../other
  git -C ../other commit -q --allow-empty -m 'elsewhere'
  git -C ../other push -q origin main
  git config remote.origin.fetch +refs/heads/other:refs/remotes/origin/other
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: main is behind origin/main (git pull --rebase origin main)'
  assert_nothing_released
  assert_gh_not_called
}

@test "release refuses an origin without main" {
  git -C "$(server_dir brc-dd/hub)" update-ref -d refs/heads/main
  run release -n 0.2.0
  assert_failure
  assert_line_equals -1 'script/release: cannot fetch main from origin (git fetch origin main)'
  assert_nothing_released
  assert_gh_not_called
}

@test "release works on main while a tag is named main" {
  git tag main
  run release -n 0.2.0
  assert_success
  assert_line_equals 3 "$push_line"
}

@test "release stays in its own checkout under an exported CDPATH" {
  mkdir -p "$HUB_TEST_TMP/decoy/script"
  export CDPATH=$HUB_TEST_TMP/decoy
  run release -n 0.2.0
  assert_success
  assert_line_equals 0 'Releasing hub 0.2.0 to github.com/brc-dd/hub'
}

@test "release refuses a branch other than main and a dirty tree" {
  git switch -q -c topic
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: not on main (git switch main)'
  git switch -q main
  touch untracked
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: the working tree is not clean (git status)'
  git config status.showUntrackedFiles no
  run release -n 0.2.0
  assert_failure
  assert_output_equals 'script/release: the working tree is not clean (git status)'
  assert_gh_not_called
}

@test "release refuses unknown options, two versions and none" {
  run release --bogus 0.2.0
  assert_failure
  assert_line_equals 0 'script/release: unknown option: --bogus'
  assert_line_equals 1 'Usage: script/release [-n] VERSION'
  run release 0.2.0 0.3.0
  assert_failure
  assert_line_equals 0 'script/release: unexpected argument: 0.3.0'
  run release
  assert_failure
  assert_line_equals 0 'script/release: no version given'
  assert_gh_not_called
}

@test "release --help prints the header" {
  run release --help
  assert_success
  assert_line_equals 1 'Usage: script/release [-n] VERSION'
  assert_gh_not_called
}
