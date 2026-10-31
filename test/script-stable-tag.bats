#!/usr/bin/env bats
load test_helper

# What script/stable-tag asks gh, with the jq filter's glob characters escaped.
LIST='release list --exclude-drafts --exclude-pre-releases --limit 1000 --json tagName -q .\[\].tagName'

# tags N : the tags v0.0.1 to v0.0.N as a stub response, one per line
tags() {
  local i out=''
  for ((i = 1; i <= $1; i++)); do out+="v0.0.$i\\n"; done
  printf '%s' "$out"
}

@test "stable-tag picks the highest stable version, not the newest release" {
  stub_gh "$LIST" 'v0.2.0\nv1.0.0-rc.1\nv0.10.0\nnightly\nv0.9.9'
  run "$HUB_TEST_ROOT/script/stable-tag"
  assert_success
  assert_output_equals v0.10.0
  assert_gh_called "$LIST"
}

@test "stable-tag fails when gh's list may be incomplete, and when no stable tag is listed" {
  stub_gh "$LIST" "$(tags 1000)"
  run "$HUB_TEST_ROOT/script/stable-tag"
  assert_failure
  assert_output_equals "script/stable-tag: 1000 releases listed, as many as gh was asked for, so the highest version may be missing; raise the limit in script/stable-tag"
  stub_gh "$LIST" "$(tags 999)"
  run "$HUB_TEST_ROOT/script/stable-tag"
  assert_success
  assert_output_equals v0.0.999
  stub_gh "$LIST" 'nightly\nv1\n0.1.0'
  run "$HUB_TEST_ROOT/script/stable-tag"
  assert_failure
  assert_output_equals "script/stable-tag: no published stable release with a vX.Y.Z tag"
  stub_gh "$LIST" ''
  run "$HUB_TEST_ROOT/script/stable-tag"
  assert_failure
  run "$HUB_TEST_ROOT/script/stable-tag" v1.0.0
  assert_failure
  assert_output_equals "script/stable-tag: takes no arguments"
}
