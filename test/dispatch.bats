#!/usr/bin/env bats
# The dispatcher: plain git command lines, global options, re-entry through git, the command word.

load test_helper

# probe_install : a copy of hub, in a directory whose name needs quoting, with version and a
# probe command that prints what the re-entered hub sees.
probe_install() {
  local inst="$HUB_TEST_TMP/it's here"
  mkdir -p "$inst/bin" "$inst/lib/hub/cmd"
  cp "$HUB_BIN" "$inst/bin/hub"
  cp "$HUB_TEST_ROOT/lib/hub/core.sh" "$inst/lib/hub/"
  cp "$HUB_TEST_ROOT/lib/hub/cmd/version.sh" "$inst/lib/hub/cmd/"
  cp "$HUB_TEST_ROOT/VERSION" "$inst/"
  cat >"$inst/lib/hub/cmd/probe.sh" <<'EOF'
# shellcheck shell=bash
# Summary: Print what the re-entered hub sees.
hub_cmd_probe() {
  local arg
  printf 'pwd=%s\n' "$PWD"
  printf 'GIT_DIR=%s\n' "${GIT_DIR-unset}"
  printf 'top=%s\n' "$(git rev-parse --show-toplevel 2>/dev/null)"
  printf 'git-dir=%s\n' "$(git rev-parse --absolute-git-dir 2>/dev/null)"
  printf 'hub.test=%s\n' "$(git config --get hub.test)"
  printf 'command=%s noop=%s\n' "$HUB_COMMAND" "$HUB_NOOP"
  printf 'root=%s\n' "$(cd "$HUB_ROOT" && pwd -P)"
  for arg; do
    if [[ -e $arg ]]; then printf 'found %s\n' "$arg"; else printf 'missing %s\n' "$arg"; fi
  done
}
EOF
}

probe() { "$HUB_TEST_TMP/it's here/bin/hub" "$@"; }

# bounded SECONDS CMD... : CMD's status, or 137 when it is killed after SECONDS.
bounded() {
  local pid watcher rc=0
  "${@:2}" &
  pid=$!
  # An exec loop keeps its pid. The watcher lets go of bats' descriptor 3.
  { sleep "$1" && kill -9 "$pid"; } >/dev/null 2>&1 3>&- &
  watcher=$!
  wait "$pid" || rc=$?
  kill "$watcher" 2>/dev/null
  return "$rc"
}

@test "a plain git command runs git with the same output and no gh call" {
  make_repo r
  echo change >file
  run git status -sb
  local expected=$output
  run hub status -sb
  assert_success
  assert_output_equals "$expected"
  assert_gh_not_called
}

@test "hub without arguments is git without arguments" {
  run hub
  assert_status 1
  assert_output_contains 'usage: git'
}

@test "--noop prints a plain git command quoted instead of running it" {
  make_repo r
  run hub --noop tag 'two words' '*' '' -m "it's"
  assert_success
  assert_output_equals "git tag two\\ words \\* '' -m it\\'s"
  run hub -C . --noop tag v1
  assert_output_equals 'git -C . tag v1'
  assert_equals "$(git tag)" ''
}

@test "a command word that is not a module name goes to git as written" {
  run hub --noop ../core status
  assert_success
  assert_output_equals 'git ../core status'
  run hub ../core status
  assert_status 1
  assert_output_contains "git: '../core' is not a git command"
}

@test "global options reach a plain git command in order" {
  make_repo r
  cd ..
  run hub --no-pager -C r --git-dir=.git -c log.showSignature=false log -1 --format=%s
  assert_success
  assert_output_equals 'initial commit'
  run hub -C r -C sub status
  assert_status 128
  assert_output_contains 'cannot change to'
}

@test "every global option that takes a value takes the next word, whatever it is" {
  local opt
  for opt in -C -c --config-env --git-dir --work-tree --namespace --attr-source \
    --super-prefix --shallow-file; do
    run hub --noop "$opt" version status
    assert_success
    assert_output_equals "git $opt version status"
  done
}

@test "--config-env reaches a hub command in git's order" {
  probe_install
  make_repo r
  HUB_A=one HUB_B=two run probe --config-env=hub.test=HUB_A --config-env hub.test=HUB_B probe
  assert_success
  assert_output_contains $'\nhub.test=two\n'
  HUB_A=one HUB_B=two run probe --config-env hub.test=HUB_B --config-env=hub.test=HUB_A probe
  assert_output_contains $'\nhub.test=one\n'
}

@test "hub found through symbolic links runs from the installation they lead to" {
  probe_install
  local inst="$HUB_TEST_TMP/it's here"
  mkdir -p links a/b
  ln -s "$inst/bin/hub" links/absolute
  ln -s "../it's here/bin/hub" links/relative
  ln -s ../../links/relative a/b/hub
  local link
  for link in links/absolute links/relative a/b/hub "$HUB_TEST_TMP/a/b/hub"; do
    run "$link" probe
    assert_success
    assert_line_equals 6 "root=$inst"
    run "$link" version
    assert_line_equals 0 "hub $(<"$HUB_TEST_ROOT/VERSION") (brc-dd/hub)"
  done
}

@test "hub run as ../hub from a directory below its own finds its installation" {
  probe_install
  local inst="$HUB_TEST_TMP/it's here"
  mkdir "$inst/bin/sub"
  cd "$inst/bin/sub"
  run ../hub probe
  assert_success
  assert_line_equals 6 "root=$inst"
  cd ..
  run ./hub probe
  assert_line_equals 6 "root=$inst"
}

@test "a hub command sees the global options git applied" {
  probe_install
  make_repo r
  mkdir sub
  cd "$HUB_TEST_TMP"
  run probe -c hub.test=one -C r -c hub.test=two -C sub probe
  assert_success
  assert_line_equals 0 "pwd=$HUB_TEST_TMP/r/sub"
  assert_output_contains 'hub.test=two'
  assert_output_contains "top=$HUB_TEST_TMP/r"
  assert_output_contains 'command=probe noop=0'
  run probe --noop --no-pager probe
  assert_output_contains 'command=probe noop=1'
}

@test "--bare takes the directory current where it stands among the global options" {
  probe_install
  git init -q --bare outer.git
  git init -q --bare outer.git/inner.git
  cd outer.git
  run probe --bare -C inner.git probe
  assert_success
  assert_output_contains "git-dir=$HUB_TEST_TMP/outer.git"$'\n'
  run probe -C inner.git --bare probe
  assert_success
  assert_output_contains "git-dir=$HUB_TEST_TMP/outer.git/inner.git"$'\n'
}

@test "-C is git's: CDPATH, symbolic links and the logical directory play no part" {
  probe_install
  make_repo real
  mkdir -p sub/deep
  cd "$HUB_TEST_TMP"
  make_repo decoy/real
  cd "$HUB_TEST_TMP"
  ln -s real/sub/deep link
  CDPATH=$HUB_TEST_TMP/decoy run probe -C real probe
  assert_line_equals 0 "pwd=$HUB_TEST_TMP/real"
  run probe -C link/.. probe
  assert_line_equals 0 "pwd=$HUB_TEST_TMP/real/sub"
  cd link
  run probe probe
  assert_line_equals 0 "pwd=$HUB_TEST_TMP/real/sub/deep"
  cd "$HUB_TEST_TMP"
  CDPATH=$HUB_TEST_TMP/decoy run hub -C real tag x
  assert_success
  assert_equals "$(git -C "$HUB_TEST_TMP/real" tag)" x
  assert_equals "$(git -C "$HUB_TEST_TMP/decoy/real" tag)" ''
}

@test "a hub command run from a subdirectory keeps relative paths and no pinned GIT_DIR" {
  probe_install
  make_repo r
  mkdir -p sub/deep
  touch sub/deep/file
  cd sub/deep
  run probe probe file ../deep/file
  assert_success
  assert_output_equals "pwd=$HUB_TEST_TMP/r/sub/deep
GIT_DIR=unset
top=$HUB_TEST_TMP/r
git-dir=$HUB_TEST_TMP/r/.git
hub.test=
command=probe noop=0
root=$HUB_TEST_TMP/it's here
found file
found ../deep/file"
}

@test "a hub command run from a linked work tree's subdirectory sees that work tree" {
  probe_install
  make_repo r
  git worktree add -q ../wt
  mkdir -p ../wt/sub
  touch ../wt/sub/file
  cd ../wt/sub
  run probe probe file
  assert_success
  assert_line_equals 0 "pwd=$HUB_TEST_TMP/wt/sub"
  assert_line_equals 1 'GIT_DIR=unset'
  assert_line_equals 2 "top=$HUB_TEST_TMP/wt"
  assert_line_equals 3 "git-dir=$HUB_TEST_TMP/r/.git/worktrees/wt"
  assert_output_contains 'found file'
}

@test "a git directory the user set stays set for a hub command" {
  probe_install
  make_repo r
  cd "$HUB_TEST_TMP"
  GIT_DIR=r/.git run probe probe
  assert_success
  assert_line_equals 1 'GIT_DIR=r/.git'
  assert_line_equals 3 "git-dir=$HUB_TEST_TMP/r/.git"
  run probe --git-dir=r/.git probe
  assert_line_equals 3 "git-dir=$HUB_TEST_TMP/r/.git"
  assert_output_lacks 'GIT_DIR=unset'
  run probe --git-dir r/.git probe
  assert_line_equals 3 "git-dir=$HUB_TEST_TMP/r/.git"
}

@test "-c values reach the programs a hub command runs" {
  mkdir bin
  printf '#!/usr/bin/env bash\necho "gh sees $(git config --get hub.test)"\n' >bin/gh
  chmod +x bin/gh
  PATH=$HUB_TEST_TMP/bin:$PATH run hub -c hub.test=1 version
  assert_success
  assert_line_equals 2 'gh sees 1'
}

@test "--version and -v run version, --help and -h run help" {
  stub_gh '--version' 'gh version 2.103.3 (2026-10-26)\nhttps://github.com/cli/cli/releases'
  run hub version
  local expected=$output
  run hub --version
  assert_output_equals "$expected"
  run hub -v
  assert_output_equals "$expected"
  run hub --help
  assert_success
  assert_output_contains 'GitHub commands provided or extended by hub'
  run hub -h
  assert_output_contains 'GitHub commands provided or extended by hub'
}

@test "an unknown global option or an empty command word gets git's message" {
  make_repo r
  run hub --definitely-not-an-option status
  assert_status 129
  assert_output_contains 'unknown option: --definitely-not-an-option'
  run hub --definitely-not-an-option version
  assert_status 129
  assert_output_contains 'unknown option: --definitely-not-an-option'
  run hub '' tag oops
  assert_status 1
  assert_output_contains "git: '' is not a git command"
  run hub -C
  assert_status 129
  assert_output_contains 'no directory given'
  assert_equals "$(git tag)" ''
  assert_gh_not_called
}

@test "hub --run is an unknown option without the re-entry marker" {
  run hub --run version
  assert_status 129
  assert_output_contains 'unknown option: --run'
}

@test "the re-entry refuses a word that is not a hub command" {
  HUB_REEXEC=1 run hub --run nosuch
  assert_status 1
  assert_output_equals 'hub: not a hub command: nosuch'
  HUB_REEXEC=1 run hub --run ../core
  assert_output_equals 'hub: not a hub command: ../core'
}

@test "hub refuses to run when git on PATH is hub itself" {
  mkdir bin
  ln -s "$HUB_BIN" bin/git
  # Without the refusal hub would exec itself forever.
  PATH=$HUB_TEST_TMP/bin:$PATH run bounded 20 hub status
  assert_status 1
  local fix='install hub under its own name and alias git to it'
  assert_output_equals "hub: git on PATH is hub itself: $HUB_TEST_TMP/bin/git ($fix)"
  PATH=$HUB_TEST_TMP/bin:$PATH run bounded 20 hub version
  assert_status 1
  assert_output_contains 'git on PATH is hub itself'
}

@test "hub refuses to run when git on PATH is hub itself through a trailing empty entry" {
  mkdir tools
  ln -s "$(command -v bash)" tools/bash
  ln -s "$(command -v readlink)" tools/readlink
  ln -s "$HUB_BIN" git
  # The empty entry after the last colon is the current directory, where exec git looks too.
  run bounded 20 /usr/bin/env PATH="$HUB_TEST_TMP/tools:" "$HUB_BIN" status
  assert_status 1
  local fix='install hub under its own name and alias git to it'
  assert_output_equals "hub: git on PATH is hub itself: ./git ($fix)"
  local real
  real=$(command -v git)
  run bounded 20 /usr/bin/env PATH="${real%/*}:$HUB_TEST_TMP/tools:" "$HUB_BIN" --version
  assert_success
  assert_output_contains 'git version'
}

@test "a hub command run from inside a .git directory gives git's commands a work tree" {
  serve_github mislav/top mislav/sub
  git clone -q https://github.com/mislav/top.git top
  cd top
  git submodule add -q https://github.com/mislav/sub.git s
  git commit -q -m 'add s'
  git push -q origin HEAD:main
  cd "$HUB_TEST_TMP"
  make_repo r
  cd .git
  # git exports GIT_IMPLICIT_WORK_TREE=0 here, which would leave the submodule step without one.
  run hub clone --recurse-submodules mislav/top "$HUB_TEST_TMP/dst"
  assert_success
  assert_equals "$(git -C "$HUB_TEST_TMP/dst/s" log -1 --format=%s)" 'initial commit'
  assert_equals "$(git -C "$HUB_TEST_TMP/dst" config remote.origin.url)" \
    https://github.com/mislav/top.git
}

# The bash 3.2 path can only be tested where /bin/bash is that old (macOS).
@test "an old bash runs plain git commands and refuses hub's own" {
  local major
  major=$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')
  ((major < 5)) || skip "/bin/bash is bash $major"
  make_repo r
  run /bin/bash "$HUB_BIN" log -1 --format=%s
  assert_success
  assert_output_equals 'initial commit'
  run /bin/bash "$HUB_BIN" --noop -C . tag 'two words'
  assert_output_equals 'git -C . tag two\ words'
  run /bin/bash "$HUB_BIN" version
  assert_status 1
  assert_output_contains 'hub: bash 5 or newer is required for hub'"'"'s commands (this is bash 3.'
  assert_output_contains '; on macOS: brew install bash)'
}
