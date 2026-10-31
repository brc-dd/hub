#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test runs in a subshell, so its exports stay local on purpose
load ../test_helper

# fake_browser [STATUS] : a browser that logs the URL to $HUB_TEST_TMP/browsed and exits STATUS.
fake_browser() {
  printf '#!/bin/sh\nprintf "%%s\\n" "$1" >>"%s/browsed"\nexit %s\n' "$HUB_TEST_TMP" "${1:-0}" >"$HUB_TEST_TMP/browser"
  chmod +x "$HUB_TEST_TMP/browser"
  export BROWSER=$HUB_TEST_TMP/browser
}

# fake_clipboard [STATUS] : a pbcopy (the clipboard tool hub tries first) that writes to
# $HUB_TEST_TMP/clipboard and exits STATUS.
fake_clipboard() {
  mkdir -p "$HUB_TEST_TMP/bin"
  printf '#!/bin/sh\ncat >"%s/clipboard"\nexit %s\n' "$HUB_TEST_TMP" "${1:-0}" >"$HUB_TEST_TMP/bin/pbcopy"
  chmod +x "$HUB_TEST_TMP/bin/pbcopy"
  export PATH=$HUB_TEST_TMP/bin:$PATH
}

# fake_gh_create : a gh whose `repo create --source --remote` adds the remote as gh does, with
# gh's git_protocol (https), and records the directory it ran in.
fake_gh_create() {
  mkdir -p "$HUB_TEST_TMP/fake"
  cat >"$HUB_TEST_TMP/fake/gh" <<'SH'
#!/usr/bin/env bash
[[ $1 == repo && $2 == create ]] || exec "$HUB_TEST_ROOT/test/stubs/gh" "$@"
printf 'gh %s\n' "$*" >>"$HUB_TEST_LOG"
pwd -P >"$HUB_TEST_TMP/gh.pwd"
name=$3 remote=origin source=.
for arg; do
  case $arg in
    --remote=*) remote=${arg#*=} ;;
    --source=*) source=${arg#*=} ;;
  esac
done
git -C "$source" remote add "$remote" "https://$name.git" || exit 1
printf 'https://%s\n' "$name"
SH
  chmod +x "$HUB_TEST_TMP/fake/gh"
  export PATH=$HUB_TEST_TMP/fake:$PATH
}

@test "create makes a private repository named after the work tree, from its top, as the remote origin" {
  make_repo dotfiles
  local top
  top=$(git rev-parse --show-toplevel)
  run hub --noop create
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --private"
  mkdir -p lib/deep && cd lib/deep
  run hub --noop create
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --private"
  stub_gh 'repo create *' 'https://github.com/mislav/dotfiles'
  run hub create
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles"
  assert_gh_called "repo create github.com/mislav/dotfiles --source=$top --remote=origin --private"
}

@test "create runs gh where you are and gives it the top of the work tree as a path, so the remote lands here" {
  make_repo dotfiles
  local top
  top=$(git rev-parse --show-toplevel)
  mkdir -p lib/deep && cd lib/deep
  fake_gh_create
  run hub create
  assert_success
  assert_equals "$(cat "$HUB_TEST_TMP/gh.pwd")" "$top/lib/deep"
  assert_equals "$(remote_url origin)" https://github.com/mislav/dotfiles.git
  assert_gh_called "repo create github.com/mislav/dotfiles --source=$top --remote=origin --private"
  # relative --git-dir and --work-tree keep their meaning, as for plain git, but gh refuses them
  run hub --noop --git-dir=../../.git --work-tree=../.. create --remote-name second
  assert_failure
  assert_output_contains "Aborted: gh repo create --source takes a work tree with its .git directory inside it"
}

@test "create --public, --internal, -p and --private set the visibility; the last one wins; values are errors" {
  make_repo dotfiles
  local top
  top=$(git rev-parse --show-toplevel)
  run hub --noop create --public
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --public"
  run hub --noop create -p
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --private"
  run hub --noop create --public --private
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --private"
  run hub --noop create --private --public
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --public"
  run hub --noop create --internal myorg/app
  assert_output_equals "gh repo create github.com/myorg/app --source=$top --remote=origin --internal"
  local opt
  for opt in --private=false --public=true --internal=false; do
    run hub --noop create "$opt"
    assert_failure
    assert_line_equals 0 "hub create: unknown option: $opt"
  done
  [[ $(gh_calls) != *"repo create"* ]]
}

@test "create NAME, OWNER/NAME, HOST/OWNER/NAME and a repository URL name the repository" {
  make_repo dotfiles
  local top
  top=$(git rev-parse --show-toplevel)
  run hub --noop create my-dots
  assert_success
  assert_output_equals "gh repo create github.com/mislav/my-dots --source=$top --remote=origin --private"
  run hub --noop create myorg/dotfiles
  assert_output_equals "gh repo create github.com/myorg/dotfiles --source=$top --remote=origin --private"
  run hub --noop create other.git
  assert_output_equals "gh repo create github.com/mislav/other --source=$top --remote=origin --private"
  : >"$HUB_TEST_LOG"
  run hub --noop create ghe.example.com/myorg/app
  assert_output_equals "gh repo create ghe.example.com/myorg/app --source=$top --remote=origin --private"
  run hub --noop create -o https://github.localhost/review/sample
  assert_output_equals $'gh repo create github.localhost/review/sample --source='"$top"$' --remote=origin --private\nopen https://github.localhost/review/sample'
  run hub --noop create -c git@ghe.example.com:myorg/app.git
  assert_output_equals $'gh repo create ghe.example.com/myorg/app --source='"$top"$' --remote=origin --private\ncopy to clipboard: https://ghe.example.com/myorg/app'
  assert_gh_not_called # an owner given needs no login lookup
}

@test "create refuses names that are not repository names before gh runs" {
  make_repo dotfiles
  run hub --noop create 'my dot+files'
  assert_failure
  assert_output_equals "Aborted: not a repository name: my dot+files (letters, digits, -, _ and . only)"
  run hub --noop create ../other
  assert_failure
  assert_output_equals "Aborted: not a GitHub owner: .. (letters, digits and - only)"
  run hub --noop create a/b/c/d
  assert_failure
  assert_output_equals "Aborted: not a repository name: a/b/c/d (use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)"
  run hub --noop create myorg/
  assert_failure
  assert_output_contains "Aborted: not a repository name: myorg/"
  run hub --noop create ''
  assert_failure
  assert_output_contains "Aborted: not a repository name:"
  run hub create one two
  assert_failure
  assert_line_equals 0 "hub create: too many arguments"
  assert_output_contains "Usage: hub create"
  assert_gh_not_called
  # the directory's name is used as GitHub would name it
  cd "$HUB_TEST_TMP"
  make_repo 'my dot+files'
  run hub --noop create
  assert_success
  assert_line_equals 0 "gh repo create github.com/mislav/my-dot-files --source=$(printf '%q' "$(git rev-parse --show-toplevel)") --remote=origin --private"
}

@test "create -d and -h pass the description and home page; a bare -h prints the manual" {
  make_repo dotfiles
  local top
  top=$(git rev-parse --show-toplevel)
  run hub --noop create -d 'My dotfiles' -h https://example.com/dots
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --private --description My\\ dotfiles --homepage https://example.com/dots"
  run hub --noop create --description=Dots --homepage=https://example.com
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --private --description Dots --homepage https://example.com"
  run hub --noop create -dDots
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=origin --private --description Dots"
  run hub create -d
  assert_failure
  assert_output_equals "Aborted: -d needs a value."
  run hub create -h
  assert_success
  assert_output_contains "Usage: hub create"
  run hub create --help
  assert_success
  assert_output_contains "private unless --public"
}

@test "create --remote-name names the remote gh adds, which must be free and a remote name" {
  make_repo dotfiles origin=https://gitlab.com/mislav/dotfiles.git
  local top
  top=$(git rev-parse --show-toplevel)
  run hub --noop create --remote-name github
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=github --private"
  run hub --noop create
  assert_failure
  assert_output_equals "Aborted: a remote named 'origin' already exists; pick another name with --remote-name NAME."
  run hub --noop create --remote-name=origin app
  assert_failure
  assert_output_equals "Aborted: a remote named 'origin' already exists; pick another name with --remote-name NAME."
  local name
  for name in 'bad name' --mirror=fetch -x 'a..b'; do
    run hub --noop create --remote-name "$name"
    assert_failure
    assert_output_equals "Aborted: not a remote name: '$name'"
  done
  run hub --noop create --remote-name ''
  assert_failure
  assert_output_equals "Aborted: --remote-name needs a value."
  run hub --noop create --remote-name
  assert_failure
  assert_output_equals "Aborted: --remote-name needs a value."
  [[ $(gh_calls) != *"repo create"* ]]
}

@test "create takes none of gh's other options" {
  make_repo dotfiles
  local opt
  for opt in -r --remote=x -s --source=. --clone --template=x -y --push=false -g -l --add-readme --disable-wiki --team=x; do
    run hub --noop create "$opt" Go
    assert_failure
    assert_line_equals 0 "hub create: unknown option: $opt"
    assert_output_contains "Usage: hub create"
  done
  run hub --noop create -ys../other
  assert_failure
  assert_line_equals 0 "hub create: unknown option: -y"
  assert_gh_not_called
}

@test "create --push pushes the current branch through gh" {
  make_repo dotfiles
  run hub --noop create --push
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$(git rev-parse --show-toplevel) --remote=origin --private --push"
}

@test "create -o opens https://HOST/OWNER/NAME and -c copies it, once gh has created the repository" {
  make_repo dotfiles
  local top
  top=$(git rev-parse --show-toplevel)
  run hub --noop create -o
  assert_success
  assert_output_equals $'gh repo create github.com/mislav/dotfiles --source='"$top"$' --remote=origin --private\nopen https://github.com/mislav/dotfiles'
  run hub --noop create --browse myorg/new.repo
  assert_output_equals $'gh repo create github.com/myorg/new.repo --source='"$top"$' --remote=origin --private\nopen https://github.com/myorg/new.repo'
  run hub --noop create -c -o
  assert_output_equals $'gh repo create github.com/mislav/dotfiles --source='"$top"$' --remote=origin --private\ncopy to clipboard: https://github.com/mislav/dotfiles\nopen https://github.com/mislav/dotfiles'
  stub_gh 'config get user -h ghe.example.com' 'mona'
  GH_HOST=ghe.example.com run hub --noop create -o
  assert_success
  assert_line_equals 1 "open https://ghe.example.com/mona/dotfiles"
  fake_browser
  fake_clipboard
  stub_gh 'repo create *' '' 1
  run hub create -o -c
  assert_failure
  [[ ! -e $HUB_TEST_TMP/browsed && ! -e $HUB_TEST_TMP/clipboard ]]
  stub_gh 'repo create *' 'https://github.com/mislav/dotfiles'
  run hub create -o -c
  assert_success
  assert_equals "$(cat "$HUB_TEST_TMP/browsed")" https://github.com/mislav/dotfiles
  assert_equals "$(cat "$HUB_TEST_TMP/clipboard")" https://github.com/mislav/dotfiles
}

@test "create fails as gh, the browser or the clipboard tool fail" {
  make_repo dotfiles
  stub_gh 'repo create *' '' 4
  run hub create
  [[ $status -eq 4 ]]
  stub_gh 'repo create *' 'https://github.com/mislav/dotfiles'
  fake_browser 19
  run hub create -o
  [[ $status -eq 19 ]]
  assert_line_equals 0 "https://github.com/mislav/dotfiles"
  fake_clipboard 17
  run hub create -c
  [[ $status -eq 17 ]]
  fake_browser 0
  run hub create -o -c # the clipboard fails and the browser works: still a failure
  [[ $status -eq 17 ]]
  assert_equals "$(wc -l <"$HUB_TEST_TMP/browsed" | tr -d ' ')" 2
}

@test "create gives the remote hub's protocol when gh's differs" {
  make_repo dotfiles
  local top
  top=$(git rev-parse --show-toplevel)
  fake_gh_create
  git config hub.protocol ssh
  run hub --noop create
  assert_success
  assert_output_equals $'gh repo create github.com/mislav/dotfiles --source='"$top"$' --remote=origin --private\ngit remote set-url origin git@github.com:mislav/dotfiles.git'
  run hub create
  assert_success
  assert_equals "$(remote_url origin)" git@github.com:mislav/dotfiles.git
  stub_gh 'config get git_protocol -h github.com' 'ssh' # gh's own setting agrees: nothing to correct
  run hub --noop create --remote-name second
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=second --private"
  git config --unset hub.protocol
  : >"$HUB_TEST_LOG"
  run hub --noop create --remote-name second
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$top --remote=second --private"
  [[ $(gh_calls) != *git_protocol* ]] # without hub.protocol, gh's choice stands unasked
}

@test "create refuses what gh cannot create from: a linked work tree, --git-dir and GIT_DIR" {
  make_repo dotfiles
  git worktree add -q ../linked -b topic
  cd ../linked
  run hub --noop create
  assert_failure
  assert_output_contains "Aborted: gh repo create --source takes a work tree with its .git directory inside it, not a linked work tree (git worktree) or a repository reached through --git-dir or GIT_DIR"
  cd ../dotfiles
  run hub --noop --git-dir="$PWD/.git" --work-tree="$PWD" create
  assert_failure
  assert_output_contains "Aborted: gh repo create --source takes a work tree"
  run hub --noop --git-dir=.git --work-tree=. create # here git itself says .git, as gh needs
  assert_success
  assert_output_equals "gh repo create github.com/mislav/dotfiles --source=$(git rev-parse --show-toplevel) --remote=origin --private"
  run env GIT_DIR="$PWD/.git" "$HUB_BIN" --noop create
  assert_failure
  assert_output_contains "Aborted: gh repo create --source takes a work tree"
  [[ $(gh_calls) != *"repo create"* ]]
}

@test "create works from a bare repository, named after it" {
  git init -q --bare bare.git
  cd bare.git
  run hub --noop create
  assert_success
  assert_output_equals "gh repo create github.com/mislav/bare --source=$(pwd -P) --remote=origin --private"
}

@test "create outside a repository fails" {
  run hub --noop create
  assert_failure
  assert_output_contains "not a git repository"
  assert_gh_not_called
}
