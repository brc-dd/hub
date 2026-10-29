#!/usr/bin/env bats
load test_helper

@test "commands hub does not know pass straight through to git" {
  run hub --noop status -sb
  assert_success
  assert_output_equals "git status -sb"
  assert_gh_not_called
}

@test "with no arguments, git's own usage is shown" {
  run hub
  assert_failure
  assert_output_contains "usage: git"
}

@test "git global options before the command are forwarded" {
  run hub --noop --no-pager --git-dir=.git log -1
  assert_success
  assert_output_equals "git --no-pager --git-dir=.git log -1"
}

@test "-C changes directory before the command runs" {
  make_repo r1 origin=https://github.com/mislav/r1.git
  cd ..
  run hub -C r1 --noop push origin,staging
  assert_success
  assert_output_equals $'git push origin main\ngit push staging main'
}

@test "-c key=value reaches git through the environment" {
  make_repo r1
  run hub -c hub.protocol=ssh --noop status
  assert_success
  assert_output_equals "git status"
}

@test "an unknown leading option is left for git to reject" {
  run hub --definitely-not-an-option status
  assert_failure
  assert_output_contains "unknown option"
}

@test "version prints git's version and hub's" {
  run hub version
  assert_success
  [[ ${lines[0]} == "git version "* ]]
  [[ ${lines[1]} == "hub version "* ]]
  run hub --version
  assert_success
  [[ ${lines[1]} == "hub version "* ]]
}

@test "help lists the commands hub adds" {
  run hub help
  assert_success
  assert_output_contains "Extended git commands:"
  assert_output_contains "push"
  assert_output_contains "New commands:"
  assert_output_contains "version"
}

@test "help COMMAND prints that module's manual" {
  run hub help push
  assert_success
  assert_output_contains "Usage: hub push REMOTE1,REMOTE2"
}

@test "command words with path characters are never treated as modules" {
  run hub --noop ../core status
  assert_success
  assert_output_equals "git ../core status"
}

@test "refuses to run under bash older than 5" {
  [[ -x /bin/bash ]] || skip "no /bin/bash"
  (( $(/bin/bash -c 'echo ${BASH_VERSINFO[0]}') < 5 )) || skip "/bin/bash is already bash 5+"
  run /bin/bash "$HUB_BIN" status
  assert_failure
  assert_output_contains "bash 5 or newer is required"
}

@test "-C with an empty path is a no-op, as in git" {
  run hub -C '' --noop status
  assert_success
  assert_output_equals "git status"
}

@test "the fast path quotes --noop output like the modules do" {
  run hub --noop status 'two words' '*'
  assert_success
  assert_output_equals "git status two\\ words \\*"
}

@test "-c and --config-env keep git's left-to-right precedence" {
  make_repo r1
  run env HUB_X=other "$HUB_BIN" --config-env=foo.bar=HUB_X -c foo.bar=command config foo.bar
  assert_success
  assert_output_equals "command"
  run env HUB_X=other "$HUB_BIN" -c foo.bar=command --config-env foo.bar=HUB_X config foo.bar
  assert_success
  assert_output_equals "other"
  run env HUB_X=other "$HUB_BIN" --config-env=foo.bar=HUB_X config foo.bar
  assert_output_equals "other"
}

@test "--config-env with a missing variable fails like git" {
  make_repo r1
  run env -u HUB_MISSING "$HUB_BIN" --config-env=foo.bar=HUB_MISSING config foo.bar
  assert_failure
  assert_output_contains "missing environment variable HUB_MISSING"
  run hub --config-env=nonsense config foo.bar
  assert_failure
  assert_output_contains "invalid config format"
}
