#!/usr/bin/env bats
load test_helper

# A gh that runs real git, to see the environment gh's own git subprocesses get.
make_fakegh() { # SCRIPT-BODY
  mkdir -p "$HUB_TEST_TMP/fakegh"
  printf '#!/usr/bin/env bash\n%s\n' "$1" >"$HUB_TEST_TMP/fakegh/gh"
  chmod +x "$HUB_TEST_TMP/fakegh/gh"
  FAKEGH_PATH=$HUB_TEST_TMP/fakegh:$PATH
}

@test "commands hub does not know pass straight through to git, as given" {
  make_repo r1
  run hub status -sb
  assert_success
  assert_output_equals "$(git status -sb)"
  run hub --noop status -sb
  assert_output_equals "git status -sb"
  assert_gh_not_called
}

@test "with no arguments, git's own usage is shown" {
  run hub
  assert_failure
  assert_output_contains "usage: git"
}

@test "git's global options reach git unchanged, in their order" {
  make_repo r1
  run hub --no-pager --git-dir=.git log -1 --format=%s
  assert_success
  assert_output_equals "initial commit"
  run hub --noop --no-pager --git-dir=.git log -1
  assert_output_equals "git --no-pager --git-dir=.git log -1"
}

@test "-C is git's own: CDPATH, symlinks and OLDPWD never select another repository" {
  make_repo r1
  cd ..
  mkdir other
  cp -R r1 other/r1
  mkdir other/r1/sub
  ln -s other/r1/sub link
  run env CDPATH="$HUB_TEST_TMP/other" "$HUB_BIN" -C r1 tag from-git
  assert_success
  run env CDPATH="$HUB_TEST_TMP/other" OLDPWD="$HUB_TEST_TMP/other/r1" "$HUB_BIN" -C r1 remote add alice
  assert_success
  assert_equals "$(git -C r1 tag)" from-git
  assert_equals "$(git -C r1 remote get-url alice)" https://github.com/alice/r1.git
  [[ -z $(git -C other/r1 tag) && -z $(git -C other/r1 remote) ]]
  # link/.. is resolved by the kernel, as for plain git: the parent of the link's target
  run hub -C link/.. tag via-link
  assert_success
  assert_equals "$(git -C other/r1 tag)" via-link
  [[ $(git -C r1 tag) == from-git ]]
  assert_equals "$(gh_calls)" 'gh config get git_protocol -h github.com' # only the protocol: no repository lookups
}

@test "--bare takes the git directory where git sees it, before a later -C" {
  git init -q --bare outer.git
  git init -q --bare outer.git/inner.git
  cd outer.git
  run hub --bare -C inner.git remote add alice alice/x
  assert_success
  assert_equals "$(git --git-dir=. config remote.alice.url)" https://github.com/alice/x.git
  [[ -z $(git --git-dir=inner.git config remote.alice.url) ]]
  run hub -C inner.git --bare remote add bob bob/x
  assert_success
  assert_equals "$(git --git-dir=inner.git config remote.bob.url)" https://github.com/bob/x.git
  [[ -z $(git --git-dir=. config remote.bob.url) ]]
}

@test "-c and --config-env reach the git hub runs and the git gh runs, with git's semantics" {
  make_repo r1
  run hub -c hub.protocol=ssh remote add alice
  assert_success
  assert_equals "$(remote_url alice)" git@github.com:alice/r1.git
  run hub --noop -c hub.protocol=ssh remote add bob
  assert_output_equals "git -c hub.protocol=ssh remote add bob git@github.com:bob/r1.git"
  # order (environment, then command line), a valueless key and trailing newlines are git's business
  make_fakegh 'printf "%s" "$(git config --get-all review.value | tr "\n" ,)"; printf " bool=%s lines=%s dir=%s tree=%s\n" "$(git config --type=bool --get foo.bar)" "$(git config --get long.text | wc -l | tr -d " ")" "${GIT_DIR-}" "${GIT_WORK_TREE-}"'
  PATH=$FAKEGH_PATH run env GIT_CONFIG_PARAMETERS="'review.value'='env'" LONG=$'hello\n\n' "$HUB_BIN" -c review.value=cli -c foo.bar --config-env=long.text=LONG pr list
  assert_success
  assert_output_equals "env,cli, bool=true lines=3 dir= tree="
  # an inherited GIT_CONFIG_COUNT in git's syntax stays valid
  local -a count=(GIT_CONFIG_COUNT=08)
  local i
  for i in 0 1 2 3 4 5 6 7; do count+=("GIT_CONFIG_KEY_$i=review.value" "GIT_CONFIG_VALUE_$i=v$i"); done
  PATH=$FAKEGH_PATH run env "${count[@]}" "$HUB_BIN" -c review.value=last pr list
  assert_success
  assert_output_equals "v0,v1,v2,v3,v4,v5,v6,v7,last, bool= lines=0 dir= tree="
  # a multi-valued key is not applied twice to git itself
  run hub -c example.option=one config --get-all example.option
  assert_output_equals "one"
}

@test "git's safeguards reach the git that gh runs" {
  make_repo r1
  git commit -q --allow-empty -m original
  local orig
  orig=$(git rev-parse HEAD)
  git commit -q --allow-empty -m replacement
  git replace "$orig" HEAD
  git reset -q --hard "$orig"
  make_fakegh 'printf "%s lazy=%s locks=%s\n" "$(git log -1 --format=%s)" "${GIT_NO_LAZY_FETCH-}" "${GIT_OPTIONAL_LOCKS-}"'
  PATH=$FAKEGH_PATH run "$HUB_BIN" pr list
  assert_output_equals "replacement lazy= locks="
  PATH=$FAKEGH_PATH run "$HUB_BIN" --no-replace-objects --no-lazy-fetch --no-optional-locks pr list
  assert_output_equals "original lazy=1 locks=0"
}

@test "options git answers by itself end the command line: nothing after them runs" {
  run hub --list-cmds=main delete -y mislav/r1
  assert_success
  [[ ${lines[0]} == add ]]
  assert_gh_not_called
  run hub --noop --list-cmds=main delete -y o/r
  assert_output_equals "git --list-cmds=main delete -y o/r"
  run hub --html-path browse
  assert_success
  assert_gh_not_called
}

@test "an empty command word is git's to reject, and nothing after it runs" {
  make_repo r1
  run hub '' tag oops
  assert_failure
  [[ -z $(git tag) ]]
  run hub --noop '' tag oops
  assert_output_equals "git '' tag oops"
}

@test "an unknown leading option or a missing value is left for git to reject, before anything runs" {
  make_repo r1
  run hub --definitely-not-an-option status
  assert_failure
  assert_output_contains "unknown option"
  run hub --definitely-not-an-option fork
  assert_failure
  assert_output_contains "unknown option"
  run hub -C
  assert_failure
  assert_output_contains "no directory given"
  run env -u MISSING_ENV_TEST "$HUB_BIN" --config-env=example.option=MISSING_ENV_TEST fork
  assert_failure
  assert_output_contains "missing environment variable 'MISSING_ENV_TEST'"
  assert_gh_not_called
}

@test "--run is internal and means nothing from the command line" {
  run hub --run version
  assert_failure
  assert_output_contains "unknown option: --run"
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
  run hub -v
  [[ ${lines[2]} == "hub version "* ]]
}

@test "help lists the commands hub adds" {
  run hub help
  assert_success
  assert_output_contains "Extended git commands:"
  assert_output_contains "push"
  assert_output_contains "New commands:"
  assert_output_contains "version"
  run hub -h
  assert_success
  assert_output_contains "New commands:"
}

@test "help COMMAND prints that module's manual" {
  run hub help push
  assert_success
  assert_output_contains "Usage: hub push "
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

@test "refuses to run when git in PATH is hub itself" {
  mkdir asgit
  ln -s "$HUB_BIN" asgit/git
  PATH=$PWD/asgit:$PATH run "$HUB_BIN" status
  assert_failure
  assert_output_contains "git in PATH is hub itself"
}

@test "-C with an empty path is a no-op, as in git" {
  make_repo r1
  run hub -C '' status -sb
  assert_success
  assert_output_equals "## main"
  run hub -C '' --noop status
  assert_output_equals "git -C '' status"
}

@test "--noop output is shell-quoted so that it can be pasted back as it is" {
  run hub --noop status 'two words' '*' '~' 'x=~' ''
  assert_success
  assert_output_equals "git status two\\ words \\* \\~ x=\\~ ''"
}

@test "--noop shows the global options the user gave" {
  make_repo r1
  cd ..
  run hub --noop -C r1 -c 'x.y=a b' remote add alice
  assert_success
  assert_output_equals "git -C r1 -c x.y=a\\ b remote add alice https://github.com/alice/r1.git"
  [[ -z $(git -C r1 remote) ]]
}

@test "-c and --config-env keep git's left-to-right precedence" {
  make_repo r1
  run env HUB_X=other "$HUB_BIN" --config-env=foo.bar=HUB_X -c foo.bar=command config foo.bar
  assert_success
  assert_output_equals "command"
  run env HUB_X=other "$HUB_BIN" -c foo.bar=command --config-env foo.bar=HUB_X config foo.bar
  assert_success
  assert_output_equals "other"
  run env 'CONFIG.VAR=other' "$HUB_BIN" --config-env=foo.bar=CONFIG.VAR config foo.bar
  assert_output_equals "other"
}

@test "hub's commands run where the user was: subdirectories, linked work trees, relative context" {
  make_repo r1 origin=https://github.com/mislav/r1.git
  mkdir -p sub/deep
  echo one >sub/deep/f
  git add . && git commit -qm f
  cd sub/deep
  echo two >f
  run hub checkout -- f # not a pull request: git's checkout, from here
  assert_success
  assert_equals "$(cat f)" one
  run hub --noop remote add alice
  assert_output_equals "git remote add alice https://github.com/alice/r1.git"
  # a linked work tree: git exports its GIT_DIR, which must not make this subdirectory the work tree
  cd "$HUB_TEST_TMP/r1"
  git worktree add -q ../linked -b topic
  mkdir ../linked/s
  echo three >../linked/sub/deep/f
  cd ../linked/s
  run hub checkout -- ../sub/deep/f
  assert_success
  assert_equals "$(cat ../sub/deep/f)" one
  run hub remote add bob
  assert_success
  assert_equals "$(git remote get-url bob)" https://github.com/bob/r1.git
  run hub --noop push origin,bob
  assert_output_equals $'git push origin topic\ngit push bob topic'
  # relative --git-dir and --work-tree keep their meaning, as for plain git
  cd "$HUB_TEST_TMP/r1/sub/deep"
  run hub --git-dir=../../.git --work-tree=../.. remote add carol
  assert_success
  assert_equals "$(git remote get-url carol)" https://github.com/carol/r1.git
  # a GIT_DIR from the environment stays what the user set
  cd "$HUB_TEST_TMP"
  run env GIT_DIR=r1/.git "$HUB_BIN" remote add dave
  assert_success
  assert_equals "$(git -C r1 remote get-url dave)" https://github.com/dave/r1.git
}

@test "--noop gh lines say where -C runs them, since gh has no -C" {
  make_repo outer origin=https://github.com/o/outer.git
  make_repo inner origin=https://github.com/o/inner.git # nested in outer
  cd ..
  run hub --noop -C inner pr list
  assert_success
  assert_output_equals "(cd $(cd inner && pwd -P) && gh pr list)"
  run hub --noop -C inner -C .. pr list
  assert_output_equals "gh pr list"
  run hub --noop pr list
  assert_output_equals "gh pr list"
  run hub --noop -C inner status
  assert_output_equals "git -C inner status"
  assert_gh_not_called
}
