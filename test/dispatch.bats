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

@test "-c and --config-env are forwarded to git in order and shown by --noop" {
  make_repo r1
  run hub -c hub.protocol=ssh --noop status
  assert_success
  assert_output_equals "git -c hub.protocol=ssh status"
  run env HUB_X=1 "$HUB_BIN" --noop --config-env=foo.bar=HUB_X -c foo.bar=x status
  assert_output_equals "git --config-env=foo.bar=HUB_X -c foo.bar=x status"
}

@test "-c also applies to the git commands hub runs itself" {
  make_repo r1
  run hub -c hub.protocol=ssh --noop remote add alice
  assert_success
  assert_output_equals "git -c hub.protocol=ssh remote add alice git@github.com:alice/r1.git"
}

@test "a valueless -c keeps git's meaning" {
  make_repo r1
  run hub -c foo.bar config --get foo.bar
  assert_success
  assert_output_equals ""
  run hub -c foo.bar config --type=bool --get foo.bar
  assert_output_equals "true"
}

@test "an unknown leading option is left for git to reject" {
  run hub --definitely-not-an-option status
  assert_failure
  assert_output_contains "unknown option"
}

@test "version names git, gh and this hub by its repository" {
  stub_gh '--version' 'gh version 2.103.2 (2026-10-23)\nhttps://github.com/cli/cli/releases/tag/v2.103.2'
  run hub version
  assert_success
  [[ ${lines[0]} == "git version "* ]]
  assert_line_equals 1 "gh version 2.103.2 (2026-10-23)"
  [[ ${lines[2]} == "hub version "*" (https://github.com/brc-dd/hub)" ]]
  run hub --version
  assert_success
  [[ ${lines[2]} == "hub version "* ]]
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
  (($(/bin/bash -c 'echo ${BASH_VERSINFO[0]}') < 5)) || skip "/bin/bash is already bash 5+"
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
  assert_output_contains "missing environment variable"
  run env 'CONFIG.VAR=other' "$HUB_BIN" --config-env=foo.bar=CONFIG.VAR config foo.bar
  assert_success
  assert_output_equals "other"
}

@test "-c and --config-env reach gh's own git subprocesses, but are not applied twice to git" {
  make_repo r1 origin=https://github.com/mislav/r1.git
  mkdir -p "$HUB_TEST_TMP/fakegh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GIT_CONFIG_COUNT:-0} ${GIT_CONFIG_KEY_0:-}=${GIT_CONFIG_VALUE_0:-} ${GIT_CONFIG_KEY_1:-}=${GIT_CONFIG_VALUE_1:-} dir=${GIT_DIR:-} tree=${GIT_WORK_TREE:-}"\n' >"$HUB_TEST_TMP/fakegh/gh"
  chmod +x "$HUB_TEST_TMP/fakegh/gh"
  PATH=$HUB_TEST_TMP/fakegh:$PATH run env HUB_X=other "$HUB_BIN" -c foo.bar --config-env=baz.qux=HUB_X pr list
  assert_success
  assert_output_equals "2 foo.bar=true baz.qux=other dir= tree="
  # git itself only gets the flags: a multi-valued key is not duplicated
  run hub -c example.option=one config --get-all example.option
  assert_success
  assert_output_equals "one"
  # the git context given to hub reaches gh as well
  PATH=$HUB_TEST_TMP/fakegh:$PATH run "$HUB_BIN" --git-dir=.git --work-tree . pr list
  assert_output_equals "0 = = dir=.git tree=."
  # environment names bash cannot read still work, and a missing variable is fatal like in git
  PATH=$HUB_TEST_TMP/fakegh:$PATH run env 'CONFIG.VAR=develop' "$HUB_BIN" --config-env=branch.main.gh-merge-base=CONFIG.VAR pr list
  assert_output_equals "1 branch.main.gh-merge-base=develop = dir= tree="
  PATH=$HUB_TEST_TMP/fakegh:$PATH run env -u MISSING_ENV_TEST "$HUB_BIN" --config-env=example.option=MISSING_ENV_TEST pr list
  assert_failure
  assert_output_contains "missing environment variable 'MISSING_ENV_TEST'"
}
