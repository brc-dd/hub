#!/usr/bin/env bats
# The fixtures and stubs every other test file relies on.

load test_helper

@test "a hostile caller environment never reaches a victim repository" {
  git init -q victim
  git -C victim commit -q --allow-empty -m victim
  echo staged >victim/file
  git -C victim add file
  mkdir -p hooks decoy/r
  printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$PWD" >hooks/post-commit
  chmod +x hooks/post-commit
  local victim_state='git -C victim rev-parse HEAD; git -C victim diff --cached --name-only
    git -C victim remote; git -C victim config --local --list; git -C victim tag'
  local before
  before=$(eval "$victim_state")
  printf 'export GIT_DIR=%q GIT_WORK_TREE=%q\n' "$PWD/victim/.git" "$PWD/victim" >evil.sh
  cat >inner.bash <<'INNER'
source "$HUB_TEST_ROOT/test/test_helper.bash"
hub_test_setup || exit 1
echo "${GIT_DIR-unset} ${GIT_INDEX_FILE-unset} ${GH_REPO-unset} ${GH_HOST-unset}" \
  "${HUB_NOOP-unset} ${CDPATH-unset}"
serve_github o/r || exit 1
clone_served o/r r || exit 1
echo "${PWD#"$HUB_TEST_TMP"/}"
git remote add alice git@github.com:alice/r.git || exit 1
git commit -q --allow-empty -m fixture || exit 1
git config core.hooksPath || echo no-hooks
git remote
git push -q origin main || exit 1
[[ $(server_ref o/r main) == $(git rev-parse HEAD) ]] && echo pushed
stub_gh 'repo view' ok
gh repo view
gh_calls
"$HUB_BIN" tag plain || exit 1
stub_gh --version 'gh version 2.103.3'
"$HUB_BIN" version >/dev/null || exit 1
git tag
INNER
  mkdir inner
  run env GIT_DIR="$PWD/victim/.git" GIT_WORK_TREE="$PWD/victim" \
    GIT_INDEX_FILE="$PWD/victim/.git/index" \
    GIT_CONFIG_PARAMETERS="'core.hooksPath'='$PWD/hooks'" \
    GH_REPO=victim/repo GH_HOST=ghe.example.com HUB_NOOP=1 CDPATH="$PWD/decoy" \
    BASH_ENV="$PWD/evil.sh" ENV="$PWD/evil.sh" \
    BATS_TEST_TMPDIR="$PWD/inner" BATS_FILE_TMPDIR="$BATS_FILE_TMPDIR" bash inner.bash
  assert_success
  assert_output_equals "unset unset unset unset unset unset
r
no-hooks
alice
origin
pushed
ok
gh repo view
plain"
  assert_equals "$(eval "$victim_state")" "$before"
  assert_equals "$(ls decoy/r)" ""
  run ls hook-ran
  assert_failure
}

@test "every test runs in the C locale, whatever the caller's" {
  mkdir inner
  run env LC_ALL=de_DE.UTF-8 LANG=de_DE.UTF-8 BATS_TEST_TMPDIR="$PWD/inner" \
    BATS_FILE_TMPDIR="$BATS_FILE_TMPDIR" bash -c \
    'source "$HUB_TEST_ROOT/test/test_helper.bash" && hub_test_setup && echo "$LC_ALL"'
  assert_success
  assert_output_equals C
}

@test "the gh stub logs no call before a test makes one" {
  assert_gh_not_called
}

@test "the gh stub replays the latest matching registration with its exit status" {
  stub_gh 'api *' first
  stub_gh 'api user' second 3
  run gh api user
  assert_status 3
  assert_output_equals second
  run gh api other
  assert_success
  assert_output_equals first
}

@test "the gh stub replays escapes and files verbatim" {
  stub_gh 'one' 'a\tb\nc'
  printf '%s\n' 'line \n one' 'line two \\' '' '' >body
  stub_gh_file 'two' body
  run gh one
  assert_output_equals $'a\tb\nc'
  gh two >out
  run cmp body out
  assert_success
}

@test "the gh stub exits 97 on an unregistered call and still logs it" {
  run gh nothing registered
  assert_status 97
  assert_output_contains 'unexpected call: gh nothing registered'
  assert_gh_called 'nothing *'
}

@test "the gh stub logs GH_REPO in front of the call when it is set" {
  stub_gh 'repo view*' ok
  GH_REPO=github.com/o/r gh repo view --json name
  gh repo view
  assert_equals "$(gh_calls)" $'GH_REPO=github.com/o/r gh repo view --json name\ngh repo view'
  assert_gh_called 'GH_REPO=github.com/o/r gh repo view *'
  run assert_gh_called 'repo view --json name'
  assert_failure
}

@test "a served repository clones and pushes over https with its GitHub URL kept" {
  serve_github o/r
  clone_served o/r
  assert_equals "$(git remote get-url origin)" https://github.com/o/r.git
  assert_equals "$(git rev-parse HEAD)" "$(server_ref o/r main)"
  git commit -q --allow-empty -m over-https
  git push -q origin main
  assert_equals "$(server_ref o/r main)" "$(git rev-parse HEAD)"
}

@test "a served repository is reached over http and without the .git suffix" {
  serve_github o/r
  git clone -q http://github.com/o/r r
  assert_equals "$(git -C r rev-parse HEAD)" "$(server_ref o/r main)"
}

@test "a served repository is pushed to over scp-like and ssh URLs" {
  serve_github o/r
  make_repo local origin=git@github.com:o/r.git
  git push -q origin main:refs/heads/scp
  git remote set-url origin ssh://git@github.com/o/r.git
  git push -q origin main:refs/heads/ssh
  git remote set-url origin ssh://git@ssh.github.com:443/o/r.git
  git push -q origin main:refs/heads/port
  assert_equals "$(git remote get-url origin)" ssh://git@ssh.github.com:443/o/r.git
  assert_equals "$(server_branches o/r)" $'main\nport\nscp\nssh'
  assert_equals "$(server_ref o/r ssh)" "$(git rev-parse HEAD)"
}

@test "another host is a separate server" {
  serve_github o/r ghe.example/o/r
  make_repo local origin=https://ghe.example/o/r.git
  git push -q origin main:refs/heads/topic
  assert_equals "$(server_branches ghe.example/o/r)" $'main\ntopic'
  assert_equals "$(server_branches o/r)" main
}

@test "an unserved repository fails over https and ssh" {
  serve_github o/r
  run git clone -q https://github.com/o/unserved.git
  assert_failure
  assert_output_contains 'nothing is served'
  run git ls-remote git@github.com:o/unserved.git
  assert_failure
  assert_output_contains 'nothing is served'
  assert_equals "$(ls "$HUB_TEST_SRV/github.com/o")" r.git
}

@test "the browser stub and its open and xdg-open links record the URL" {
  assert_equals "$GH_BROWSER" "$HUB_TEST_ROOT/test/stubs/browser"
  "$GH_BROWSER" https://github.com/o/r
  open https://github.com/o/r/issues
  xdg-open --new https://github.com/o/r/pulls
  assert_equals "$(<browser.log)" 'https://github.com/o/r
https://github.com/o/r/issues
https://github.com/o/r/pulls'
}

@test "the browser stub exits with HUB_TEST_BROWSER_STATUS" {
  HUB_TEST_BROWSER_STATUS=19 run open https://github.com/o/r
  assert_status 19
  assert_equals "$(<browser.log)" https://github.com/o/r
}

@test "the clipboard stub and its xclip and wl-copy links record stdin" {
  printf 'one\n' | pbcopy
  assert_equals "$(<clipboard)" one
  printf 'two\n' | xclip -selection clipboard
  assert_equals "$(<clipboard)" two
  printf 'three' | wl-copy
  assert_equals "$(<clipboard)" three
}

@test "the clipboard stub exits with HUB_TEST_CLIPBOARD_STATUS" {
  HUB_TEST_CLIPBOARD_STATUS=17 run pbcopy <<<copied
  assert_status 17
  assert_equals "$(<clipboard)" copied
}

@test "ssh -G reads the test HOME's ssh config" {
  mkdir -p "$HOME/.ssh"
  printf 'Host hub-test-alias\n  HostName github.com\n  User git\n' >"$HOME/.ssh/config"
  run --separate-stderr ssh -G hub-test-alias
  assert_success
  assert_line_equals 0 'host hub-test-alias'
  assert_output_contains $'\nhostname github.com\n'
}

@test "ssh -G without a test config reads none, not the developer's" {
  local real
  real=$(PATH=$(getconf PATH) command -v ssh)
  run --separate-stderr "$real" -F /dev/null -G hub-test-alias
  local expected=$output
  run --separate-stderr ssh -G hub-test-alias
  assert_success
  assert_output_equals "$expected"
  assert_equals "$(<ssh.log)" '-G hub-test-alias'
}

@test "no_gh_path holds git, bash and the commands named, and never gh" {
  local dir
  dir=$(no_gh_path mktemp ssh)
  assert_equals "${dir%/path.*}" "$HUB_TEST_TMP"
  assert_equals "$(ls "$dir")" $'bash\ngit\nmktemp\nssh'
  assert_equals "$(ls "$(no_gh_path)")" $'bash\ngit'
  assert_equals "$(readlink "$dir/ssh")" "$HUB_TEST_ROOT/test/stubs/ssh"
  PATH=$dir run -127 gh --version
  assert_status 127
  PATH=$dir run git --version
  assert_success
  assert_gh_not_called
}

@test "recording_gh answers as the stub and records the latest call's words, variables and parent" {
  stub_gh 'issue view *' answer 3
  local dir
  dir=$(recording_gh)
  assert_equals "$dir" "$HUB_TEST_TMP/bin"
  PATH=$dir:$PATH run gh issue view 'two words' ''
  assert_status 3
  assert_output_equals answer
  assert_equals "$(<args)" "$(printf '%s\n' issue view 'two words' '')"
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=unset GH_REPO=unset'
  assert_equals "$(basename "$(<parent)")" bash
  assert_gh_called 'issue view two words '
  run ls stdin
  assert_failure
  GH_HOST=ghe.example GH_REPO=o/r PATH=$dir:$PATH run gh issue view 1
  assert_equals "$(<args)" $'issue\nview\n1'
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=ghe.example GH_REPO=o/r'
  assert_gh_called 'GH_REPO=o/r gh issue view 1'
}

@test "failing_gh answers as the stub and writes its message on stderr when the stub fails" {
  stub_gh 'api user' partial 4
  stub_gh 'api zen' fine
  local dir
  dir=$(failing_gh "gh: it's Not Found (HTTP 404)")
  PATH=$dir:$PATH run --separate-stderr gh api user
  assert_status 4
  assert_output_equals partial
  assert_equals "$stderr" "gh: it's Not Found (HTTP 404)"
  PATH=$dir:$PATH run --separate-stderr gh api zen
  assert_success
  assert_output_equals fine
  assert_equals "$stderr" ''
  assert_equals "$(gh_calls)" $'gh api user\ngh api zen'
}

@test "recording_gh stdin also records the standard input" {
  stub_gh 'api *' ok
  PATH=$(recording_gh stdin):$PATH run gh api graphql --input - <<<'{"query":"{viewer{login}}"}'
  assert_success
  assert_output_equals ok
  assert_equals "$(<stdin)" '{"query":"{viewer{login}}"}'
}
