#!/usr/bin/env bats
# script/update-formula: points Formula/hub.rb at a release, on a copy in a scratch tree.

load test_helper

sha_a=$(printf 'a%.0s' {1..64})
sha_b=$(printf 'b%.0s' {1..64})

setup() {
  hub_test_setup
  mkdir -p tree/script tree/Formula
  cp "$HUB_TEST_ROOT/script/update-formula" tree/script/
  cat >tree/Formula/hub.rb <<RUBY
class Hub < Formula
  REPO = "brc-dd/hub".freeze

  homepage "https://github.com/#{REPO}"
  url "https://github.com/#{REPO}/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "$sha_a"
  head "https://github.com/#{REPO}.git", branch: "main"

  resource "extra" do
    url "https://example.com/extra-1.0.tar.gz"
    sha256 "$sha_a"
  end
end
RUBY
  cp tree/Formula/hub.rb before.rb
  cd tree || return 1
}

update_formula() { script/update-formula "$@"; }

@test "update-formula moves forward: only the first url and sha256 lines change" {
  run update_formula --sha256="$sha_b" v0.2.0
  assert_success
  assert_output_equals "Pointed Formula/hub.rb at v0.2.0 (sha256 $sha_b)"
  run diff ../before.rb Formula/hub.rb
  assert_output_equals "5,6c5,6
<   url \"https://github.com/#{REPO}/archive/refs/tags/v0.1.0.tar.gz\"
<   sha256 \"$sha_a\"
---
>   url \"https://github.com/#{REPO}/archive/refs/tags/v0.2.0.tar.gz\"
>   sha256 \"$sha_b\""
}

@test "update-formula moves to a pre-release of a higher version" {
  run update_formula --sha256="$sha_b" v0.2.0-rc.1
  assert_success
  run grep -c 'refs/tags/v0.2.0-rc.1.tar.gz' Formula/hub.rb
  assert_output_equals 1
}

@test "update-formula stays in its own tree under an exported CDPATH" {
  mkdir -p ../decoy/script ../decoy/Formula
  sed 's/v0.1.0/v9.9.9/' ../before.rb >../decoy/Formula/hub.rb
  export CDPATH=$HUB_TEST_TMP/decoy
  run update_formula --sha256="$sha_b" v0.2.0
  assert_success
  assert_output_equals "Pointed Formula/hub.rb at v0.2.0 (sha256 $sha_b)"
  run grep -c 'refs/tags/v0.2.0.tar.gz' Formula/hub.rb
  assert_output_equals 1
  run grep -c 'refs/tags/v9.9.9.tar.gz' ../decoy/Formula/hub.rb
  assert_output_equals 1
}

@test "update-formula refuses to go back without --force and leaves the file alone" {
  run update_formula --sha256="$sha_b" v0.0.9
  assert_failure
  assert_output_equals "script/update-formula: Formula/hub.rb points at v0.1.0, \
which is newer than v0.0.9 (-f to go back)"
  run cmp ../before.rb Formula/hub.rb
  assert_success
}

@test "update-formula refuses a pre-release of the version the formula names" {
  run update_formula --sha256="$sha_b" v0.1.0-rc.1
  assert_failure
  assert_output_contains 'points at v0.1.0, which is newer than v0.1.0-rc.1'
}

@test "update-formula --force goes back" {
  run update_formula --force --sha256="$sha_b" v0.0.9
  assert_success
  run grep -c 'refs/tags/v0.0.9.tar.gz' Formula/hub.rb
  assert_output_equals 1
  run update_formula -f --sha256="$sha_b" v0.0.8
  assert_success
}

@test "update-formula with the same version and checksum leaves the file byte for byte" {
  run update_formula --sha256="$sha_a" v0.1.0
  assert_success
  run cmp ../before.rb Formula/hub.rb
  assert_success
}

@test "update-formula --dry-run prints the diff and changes nothing" {
  run update_formula -n --sha256="$sha_b" v0.2.0
  assert_success
  assert_output_contains '+  url "https://github.com/#{REPO}/archive/refs/tags/v0.2.0.tar.gz"'
  assert_output_contains "+  sha256 \"$sha_b\""
  run cmp ../before.rb Formula/hub.rb
  assert_success
}

@test "update-formula --dry-run still refuses to go back" {
  run update_formula --dry-run --sha256="$sha_b" v0.0.9
  assert_failure
  assert_output_contains 'newer than v0.0.9'
}

@test "update-formula refuses a checksum that is not 64 lowercase hex digits" {
  local bad
  for bad in "${sha_b^^}" "${sha_b:1}" "${sha_b}0" "${sha_b:1}g" ''; do
    run update_formula --sha256="$bad" v0.2.0
    assert_failure
    assert_output_equals \
      "script/update-formula: not a SHA-256 checksum (64 lowercase hex digits): $bad"
  done
  run update_formula -n --sha256= v0.2.0
  assert_failure
  assert_output_lacks Downloading
  run cmp ../before.rb Formula/hub.rb
  assert_success
}

@test "update-formula refuses a tag that is not vX.Y.Z[-PRE]" {
  local bad
  for bad in 0.2.0 v1.02.0 v1.0 v1.0.0+build v1.0.0-01 nightly; do
    run update_formula --sha256="$sha_b" "$bad"
    assert_failure
    assert_output_equals "script/update-formula: not a vX.Y.Z[-PRE] tag: $bad"
  done
}

@test "update-formula refuses unknown options, two tags and no tag" {
  run update_formula --bogus v0.2.0
  assert_failure
  assert_line_equals 0 'script/update-formula: unknown option: --bogus'
  assert_line_equals 1 'Usage: script/update-formula [--sha256=HEX] [-n] [-f] vX.Y.Z'
  run update_formula v0.2.0 v0.3.0
  assert_failure
  assert_line_equals 0 'script/update-formula: unexpected argument: v0.3.0'
  run update_formula
  assert_failure
  assert_line_equals 0 'script/update-formula: no version given'
}

@test "update-formula fails on a formula without a url or sha256 line" {
  grep -v '^  sha256' ../before.rb >Formula/hub.rb
  run update_formula --sha256="$sha_b" v0.2.0
  assert_failure
  assert_output_equals 'script/update-formula: Formula/hub.rb has no url or no sha256 line'
}

@test "update-formula without --sha256 hashes the downloaded tarball" {
  mkdir bin
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nprintf tarball\n' \
    "$HUB_TEST_TMP/curl.log" >bin/curl
  chmod +x bin/curl
  PATH=$PWD/bin:$PATH run update_formula v0.2.0
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/curl.log")" \
    '-fsSL --retry 3 https://github.com/brc-dd/hub/archive/refs/tags/v0.2.0.tar.gz'
  run grep -c "sha256 \"$(printf tarball | shasum -a 256 | cut -d ' ' -f 1)\"" Formula/hub.rb
  assert_output_equals 1
}

@test "update-formula fails when the download fails and leaves the file alone" {
  mkdir bin
  printf '#!/usr/bin/env bash\nexit 22\n' >bin/curl
  chmod +x bin/curl
  PATH=$PWD/bin:$PATH run update_formula v0.2.0
  assert_failure
  assert_output_contains 'script/update-formula: could not download https://github.com/brc-dd/hub/'
  run cmp ../before.rb Formula/hub.rb
  assert_success
}

@test "update-formula --self-test passes" {
  run update_formula --self-test
  assert_success
  assert_output_equals 'The version order is right.'
}

@test "update-formula --self-test fails when the comparison is wrong" {
  # Numeric identifiers compared as plain strings: 10 < 9.
  sed -i.orig 's/((${#x} < ${#y})) || //' script/update-formula
  run update_formula --self-test
  assert_failure
  assert_output_contains 'script/update-formula: self-test: '
}

@test "update-formula --self-test takes no other arguments" {
  run update_formula --self-test v0.2.0
  assert_failure
  assert_line_equals 0 'script/update-formula: --self-test takes no other arguments'
}

@test "update-formula --help prints the header" {
  run update_formula --help
  assert_success
  assert_line_equals 1 'Usage: script/update-formula [--sha256=HEX] [-n] [-f] vX.Y.Z'
  assert_output_lacks 'set -euo'
}
