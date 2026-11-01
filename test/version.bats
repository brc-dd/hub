#!/usr/bin/env bats
# hub version: hub's, git's and gh's versions.

load test_helper

@test "hub version prints hub's, git's and gh's versions" {
  stub_gh '--version' 'gh version 2.103.3 (2026-10-26)\nhttps://github.com/cli/cli/releases'
  run hub version
  assert_success
  assert_line_equals 0 "hub $(<"$HUB_TEST_ROOT/VERSION") (brc-dd/hub)"
  assert_line_equals 1 "$(git --version)"
  assert_line_equals 2 'gh version 2.103.3 (2026-10-26)'
  assert_equals "${#lines[@]}" 3
}

@test "hub version without gh prints hub's and git's versions" {
  PATH=$(no_gh_path) run hub version
  assert_success
  assert_equals "${#lines[@]}" 2
  assert_line_equals 1 "$(git --version)"
}

@test "hub --version --build-options prints git's build options after hub's version" {
  stub_gh '--version' 'gh version 2.103.3 (2026-10-26)'
  run git --version --build-options
  local expected=$output
  run hub --version --build-options
  assert_success
  assert_line_equals 0 "hub $(<"$HUB_TEST_ROOT/VERSION") (brc-dd/hub)"
  assert_output_contains $'\n'"$expected"$'\ngh version 2.103.3'
}

@test "hub version refuses other options and arguments" {
  run hub version extra
  assert_status 1
  assert_line_equals 0 'hub version: unexpected argument: extra'
  assert_line_equals 1 'Usage: hub version [--build-options]'
  run hub version --build-options extra
  assert_status 1
  assert_line_equals 0 'hub version: unexpected argument: extra'
  run hub version -x
  assert_status 1
  assert_line_equals 0 'hub version: unknown option: -x'
  assert_gh_not_called
}

@test "hub version --help prints its manual" {
  run hub version --help
  assert_success
  assert_line_equals 0 'Summary: Show the versions of hub, git and gh.'
  run hub version -h
  assert_line_equals 0 'Summary: Show the versions of hub, git and gh.'
  assert_gh_not_called
}
