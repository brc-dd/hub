#!/usr/bin/env bats
# hub create: gh repo create from the work tree, the remote's URL, --push, -o and -c.

load test_helper

setup() {
  hub_test_setup
  stub_gh 'repo create *' ''
}

# gh_adds_remote URL : gh repo create, as the real one does, adds its --remote at its --source.
gh_adds_remote() {
  mkdir -p "$HUB_TEST_TMP/bin" || return 1
  cat >"$HUB_TEST_TMP/bin/gh" <<'EOF' || return 1
#!/usr/bin/env bash
"$HUB_TEST_ROOT/test/stubs/gh" "$@" || exit
[[ $1 == repo && $2 == create ]] || exit 0
for arg; do
  case $arg in
    --source=*) source=${arg#*=} ;;
    --remote=*) remote=${arg#*=} ;;
  esac
done
git -C "$source" remote add "$remote" "$HUB_TEST_CREATED_URL"
EOF
  chmod +x "$HUB_TEST_TMP/bin/gh" || return 1
  export PATH=$HUB_TEST_TMP/bin:$PATH HUB_TEST_CREATED_URL=$1
}

@test "hub create makes a private repository of yours named after the top directory" {
  make_repo dotfiles
  mkdir sub
  cd sub
  run hub create
  assert_success
  local source=$HUB_TEST_TMP/dotfiles
  assert_gh_called \
    "repo create github.com/mislav/dotfiles --source=$source --remote=origin --private"
}

@test "hub create replaces characters a repository name cannot have" {
  make_repo 'my dot+files'
  run hub create
  assert_success
  assert_gh_called 'repo create github.com/mislav/my-dot-files *'
}

@test "hub create takes the name of the project when there is one" {
  make_repo work upstream=https://github.com/other/tools.git
  run hub create
  assert_success
  assert_gh_called 'repo create github.com/mislav/tools *'
}

@test "hub create uses the default host and your login there when no NAME is given" {
  make_repo work
  stub_gh 'config get user -h example.com' octo
  stub_gh 'config get git_protocol -h example.com' https
  GH_HOST=example.com run hub create
  assert_success
  assert_gh_called 'repo create example.com/octo/work *'
}

@test "hub create takes NAME, OWNER/NAME, HOST/OWNER/NAME and URLs, without .git" {
  make_repo work
  stub_gh 'config get user -h example.com' octo
  run hub create tools.git
  assert_success
  assert_gh_called "repo create github.com/mislav/tools --source=$HUB_TEST_TMP/work *"
  run hub create myorg/tools
  assert_success
  assert_gh_called 'repo create github.com/myorg/tools *'
  run hub create Example.COM/myorg/kit.git
  assert_success
  assert_gh_called 'repo create example.com/myorg/kit *'
  run hub create https://github.com/myorg/site.git
  assert_success
  assert_gh_called 'repo create github.com/myorg/site *'
  run hub create git@github.com:myorg/scp.git
  assert_success
  assert_gh_called 'repo create github.com/myorg/scp *'
  run hub create ssh://git@github.com/myorg/ssh.git
  assert_success
  assert_gh_called 'repo create github.com/myorg/ssh *'
  run hub create -- dash
  assert_success
  assert_gh_called 'repo create github.com/mislav/dash *'
  GH_HOST=example.com run hub create gadget
  assert_success
  assert_gh_called 'repo create example.com/octo/gadget *'
}

@test "hub create passes the visibility, the last one given, and never gh's -p" {
  make_repo work
  run hub create --public
  assert_gh_called 'repo create github.com/mislav/work --source=* --remote=origin --public'
  run hub create --private --internal
  assert_gh_called 'repo create github.com/mislav/work --source=* --remote=origin --internal'
  : >"$HUB_TEST_GH_LOG"
  run hub create --public -p
  assert_success
  assert_gh_called 'repo create github.com/mislav/work --source=* --remote=origin --private'
  : >"$HUB_TEST_GH_LOG"
  run hub create --public -pc
  assert_success
  assert_gh_called 'repo create github.com/mislav/work --source=* --remote=origin --private'
  assert_equals "$(copied)" https://github.com/mislav/work
}

@test "hub create passes the description, the home page and the remote's name" {
  make_repo work
  run hub create -d 'My tools' -h https://example.com --remote-name gh
  assert_success
  local rest='--description My tools --homepage https://example.com'
  assert_gh_called "repo create github.com/mislav/work --source=* --remote=gh --private $rest"
  run hub create --description=--public --homepage=x --remote-name=up
  assert_success
  assert_gh_called '* --remote=up --private --description --public --homepage x'
  run hub create -dabc
  assert_gh_called '* --remote=origin --private --description abc'
}

@test "hub create sets gh's remote URL to the one gh's git_protocol gives" {
  make_repo work
  gh_adds_remote git@github.com:mislav/work.git
  run hub create
  assert_success
  assert_equals "$(git remote get-url origin)" https://github.com/mislav/work.git
}

@test "hub create sets an ssh URL when gh's git_protocol is ssh and gh recorded https" {
  make_repo work
  stub_gh 'config get git_protocol -h github.com' ssh
  gh_adds_remote https://github.com/mislav/work.git
  run hub create
  assert_success
  assert_equals "$(git remote get-url origin)" git@github.com:mislav/work.git
}

@test "hub create keeps the remote URL gh recorded when it is the expected one" {
  make_repo work
  stub_gh 'config get git_protocol -h github.com' ssh
  gh_adds_remote git@github.com:mislav/work.git
  GIT_TRACE=$HUB_TEST_TMP/trace.log run hub create
  assert_success
  assert_equals "$(git remote get-url origin)" git@github.com:mislav/work.git
  run grep -c 'remote add origin' "$HUB_TEST_TMP/trace.log"
  assert_output_equals 1
  run grep 'remote set-url' "$HUB_TEST_TMP/trace.log"
  assert_failure
}

@test "hub create reads gh's git_protocol before it creates the repository" {
  make_repo work
  run hub create
  assert_success
  assert_equals "$(gh_calls)" "gh config get user -h github.com
gh config get git_protocol -h github.com
gh repo create github.com/mislav/work --source=$HUB_TEST_TMP/work --remote=origin --private"
}

@test "hub create --push pushes the current branch with git and tracks it" {
  git init -q --bare "$(server_dir mislav/work)"
  make_repo work
  commit_on main 'second commit'
  gh_adds_remote https://github.com/mislav/work.git
  run hub create --push
  assert_success
  assert_gh_called 'repo create github.com/mislav/work --source=* --remote=origin --private'
  assert_equals "$(server_ref mislav/work refs/heads/main)" "$(tip main)"
  assert_equals "$(server_branches mislav/work)" main
  assert_equals "$(git config branch.main.remote)" origin
  assert_equals "$(git config branch.main.merge)" refs/heads/main
}

@test "hub create --push exits with git's status when the push fails, before the browser" {
  make_repo work
  gh_adds_remote https://github.com/mislav/work.git
  run hub create --push -o
  assert_status 128
  assert_output_contains 'fatal:'
  assert_equals "$(git config branch.main.remote)" ''
  run test -e "$HUB_TEST_TMP/browser.log"
  assert_failure
}

@test "hub create --push refuses a detached HEAD and a branch without commits" {
  make_repo work
  git checkout -q --detach
  run hub create --push
  assert_status 1
  assert_output_equals 'hub create: not on a branch (--push pushes the current branch)'
  git init -q -b trunk fresh
  cd fresh
  run hub create --push
  assert_status 1
  assert_output_equals \
    'hub create: trunk has no commits to push (commit first, or leave out --push)'
  assert_gh_not_called
}

@test "hub create -c copies and -o opens the repository's URL" {
  make_repo work
  run hub create -c -o myorg/tools
  assert_success
  assert_equals "$(copied)" https://github.com/myorg/tools
  assert_equals "$(opened)" https://github.com/myorg/tools
  run hub create --copy --browse
  assert_success
  assert_equals "$(copied)" https://github.com/mislav/work
  assert_equals "$(opened | tail -n 1)" https://github.com/mislav/work
}

@test "hub create exits with the browser's status when it fails" {
  make_repo work
  HUB_TEST_BROWSER_STATUS=3 run hub create -o
  assert_status 3
  assert_equals "$(opened)" https://github.com/mislav/work
}

@test "hub create exits with the clipboard's status when it fails" {
  make_repo work
  HUB_TEST_CLIPBOARD_STATUS=4 run hub create -c
  assert_status 4
  assert_gh_called 'repo create github.com/mislav/work *'
}

@test "hub create stops when gh fails, before the remote, the push and the browser" {
  git init -q --bare "$(server_dir mislav/work)"
  make_repo work
  stub_gh 'repo create *' 'GraphQL: Name already exists on this account' 1
  run hub create --push -o
  assert_status 1
  assert_output_contains 'Name already exists'
  assert_equals "$(server_branches mislav/work)" ''
  assert_equals "$(git remote)" ''
  run test -e "$HUB_TEST_TMP/browser.log"
  assert_failure
}

@test "hub create refuses bad names and remotes before asking gh anything" {
  make_repo work
  run hub create 'my repo'
  assert_status 1
  assert_output_equals \
    'hub create: not a repository name: my repo (use letters, digits, -, _ and .)'
  run hub create .git
  assert_output_equals "hub create: not a repository name: '' (use letters, digits, -, _ and .)"
  run hub create a/b/c/d
  assert_status 1
  local forms='NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL'
  assert_output_equals "hub create: not a repository: a/b/c/d (use $forms)"
  local owner
  for owner in .. . - -x .x 'a$b'; do
    run hub create -- "$owner/tools"
    assert_status 1
    assert_output_equals "hub create: not a repository: $owner/tools (use $forms)"
  done
  run hub create myorg/..
  assert_status 1
  assert_output_equals "hub create: not a repository: myorg/.. (use $forms)"
  run hub create --remote-name ''
  assert_status 1
  assert_output_equals "hub create: not a remote name: ''"
  run hub create --remote-name -x
  assert_output_equals 'hub create: not a remote name: -x'
  run hub create --remote-name 'a b'
  assert_output_equals 'hub create: not a remote name: a b'
  git remote add origin https://example.com/x.git
  run hub create
  assert_status 1
  assert_output_equals \
    'hub create: remote already exists: origin (name another with --remote-name NAME)'
  assert_gh_not_called
}

@test "hub create refuses unknown options, gh's own options and extra arguments" {
  make_repo work
  local word usage='Usage: hub create [-p | --public | --internal] [-d DESCRIPTION]'
  usage+=' [-h HOMEPAGE]'
  for word in --clone -r --source=. --template=x -y --push=1; do
    run hub create "$word"
    assert_status 1
    assert_line_equals 0 "hub create: unknown option: $word"
    assert_line_equals 1 "$usage"
  done
  run hub create one two
  assert_status 1
  assert_line_equals 0 'hub create: unexpected argument: two'
  run hub create -d
  assert_line_equals 0 'hub create: -d needs a value'
  run hub create --remote-name
  assert_line_equals 0 'hub create: --remote-name needs a value'
  run hub create -h
  assert_status 1
  assert_line_equals 0 'hub create: -h needs a value'
  assert_gh_not_called
}

@test "hub create stops when your login is unknown" {
  make_repo work
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user --jq .login' '' 1
  run hub create
  assert_status 1
  local login='could not determine your GitHub login for github.com'
  assert_output_equals "hub create: $login (run: gh auth login -h github.com)"
  run hub create myorg/tools
  assert_success
  assert_gh_called 'repo create github.com/myorg/tools *'
}

@test "hub create refuses a bare repository and a directory outside a repository" {
  git init -q --bare bare.git
  cd bare.git
  run hub create
  assert_status 1
  assert_output_equals 'hub create: run hub create from a work tree'
  cd objects
  run hub create
  assert_status 1
  assert_output_equals 'hub create: run hub create from a work tree'
  cd "$HUB_TEST_TMP"
  make_repo work
  cd .git
  run hub create
  assert_status 1
  assert_output_equals 'hub create: not inside a work tree'
  mkdir "$HUB_TEST_TMP/none"
  cd "$HUB_TEST_TMP/none"
  run hub create
  assert_status 1
  assert_output_contains 'fatal: not a git repository'
  assert_gh_not_called
}

@test "hub create --help prints its manual" {
  make_repo work
  run hub create --help
  assert_success
  assert_line_equals 0 \
    'Summary: Create a GitHub repository for this repository and add it as a remote.'
  assert_line_equals 1 \
    'Usage: hub create [-p | --public | --internal] [-d DESCRIPTION] [-h HOMEPAGE]'
  assert_gh_not_called
}
