#!/usr/bin/env bats
# script/stable-tag: the highest published stable vX.Y.Z tag, with gh stubbed.

load test_helper

list='release list --exclude-drafts --exclude-pre-releases --limit 1000 --json tagName --jq *'

stable_tag() { "$HUB_TEST_ROOT/script/stable-tag" "$@"; }

@test "stable-tag picks the highest version by number, not by text or date" {
  stub_gh "$list" 'v0.2.0\nv1.0.0-rc.1\nv0.10.0\nnightly\nv0.9.9\nv0.10.0-beta'
  run stable_tag
  assert_success
  assert_output_equals v0.10.0
  assert_equals "$(gh_calls)" "gh ${list%\*}.[].tagName"
}

@test "stable-tag compares every field numerically" {
  stub_gh "$list" 'v2.0.0\nv10.0.0\nv9.99.99\nv10.0.10\nv10.0.9'
  run stable_tag
  assert_success
  assert_output_equals v10.0.10
}

@test "stable-tag refuses a list as long as the limit" {
  local tags
  tags=$(printf 'v0.0.%s\\n' {1..1000})
  stub_gh "$list" "${tags%\\n}"
  run stable_tag
  assert_failure
  assert_output_equals "script/stable-tag: gh listed 1000 releases, as many as it was asked for, \
so the highest version may be missing (raise the limit in script/stable-tag)"
}

@test "stable-tag accepts a list one shorter than the limit" {
  local tags
  tags=$(printf 'v0.0.%s\\n' {1..999})
  stub_gh "$list" "${tags%\\n}"
  run stable_tag
  assert_success
  assert_output_equals v0.0.999
}

@test "stable-tag fails without a stable vX.Y.Z tag" {
  stub_gh "$list" 'nightly\nv1\n0.1.0\nv1.0.0-rc.1\nv01.0.0'
  run stable_tag
  assert_failure
  assert_output_equals 'script/stable-tag: no published stable release has a vX.Y.Z tag'
}

@test "stable-tag fails without any release" {
  stub_gh "$list" ''
  run stable_tag
  assert_failure
  assert_output_equals 'script/stable-tag: no published stable release has a vX.Y.Z tag'
}

@test "stable-tag fails when gh fails" {
  stub_gh "$list" 'HTTP 401: Bad credentials' 1
  run stable_tag
  assert_status 1
  assert_output_equals ''
}

@test "stable-tag takes no arguments" {
  run stable_tag v1.0.0
  assert_failure
  assert_output_equals 'script/stable-tag: takes no arguments (Usage: script/stable-tag)'
  assert_gh_not_called
}
