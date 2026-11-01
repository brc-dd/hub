#!/usr/bin/env bats
# hub help: git's help with hub's commands, hub's manuals, and git help for the rest.

load test_helper

@test "hub help lists every command with its summary after git's help" {
  local file name
  run hub help
  assert_success
  assert_output_contains 'usage: git'
  local heading='GitHub commands provided or extended by hub (hub help COMMAND for details):'
  assert_output_contains $'\n'"$heading"$'\n'
  for file in "$HUB_TEST_ROOT"/lib/hub/cmd/*.sh; do
    name=${file##*/} && name=${name%.sh}
    assert_output_contains "$(printf '   %-14s %s' "$name" "$(sed -n 's/^# Summary: //p' "$file")")"
  done
}

@test "hub help COMMAND prints that command's manual" {
  run hub help version
  assert_success
  assert_line_equals 0 'Summary: Show the versions of hub, git and gh.'
  assert_line_equals 1 'Usage: hub version [--build-options]'
  assert_output_lacks '#'
  assert_output_lacks 'shellcheck'
}

@test "hub help --help and -h print help's own manual" {
  run hub help --help
  assert_success
  assert_line_equals 0 "Summary: Show git's help and hub's commands."
  run hub help -h
  assert_success
  assert_line_equals 0 "Summary: Show git's help and hub's commands."
}

@test "hub help with any other command line runs git help" {
  run hub --noop help log
  assert_output_equals 'git help log'
  run hub --noop help version extra
  assert_output_equals 'git help version extra'
  run hub --noop help -a
  assert_output_equals 'git help -a'
  run hub -c man.viewer=hubtest -c man.hubtest.cmd=echo help log
  assert_success
  assert_output_equals 'git-log'
}
