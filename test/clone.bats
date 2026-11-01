#!/usr/bin/env bats
# hub clone: [OWNER/]REPO shorthands become clone URLs; everything else is git clone's.

load test_helper

# second_commit [HOST/]OWNER/REPO : a second commit on the served repository's main.
second_commit() {
  local dir commit
  dir=$(server_dir "$1")
  commit=$(git -C "$dir" commit-tree -p main -m second 'main^{tree}') || return 1
  git -C "$dir" update-ref refs/heads/main "$commit"
}

# empty_dir : cd into a new empty directory, where nothing but a clone can appear.
empty_dir() {
  mkdir dest || return 1
  cd dest || return 1
}

@test "clone OWNER/REPO clones the GitHub repository over https" {
  serve_github alice/dotfiles
  run hub clone alice/dotfiles
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" https://github.com/alice/dotfiles.git
  assert_equals "$(git -C dotfiles rev-parse HEAD)" "$(server_ref alice/dotfiles main)"
  assert_equals "$(git -C dotfiles symbolic-ref HEAD)" refs/heads/main
}

@test "clone OWNER/REPO asks gh only for the protocol, never for the login" {
  serve_github alice/dotfiles
  run hub clone alice/dotfiles
  assert_success
  assert_equals "$(gh_calls)" 'gh config get git_protocol -h github.com'
}

@test "clone REPO clones your own repository" {
  serve_github mislav/dotfiles
  run hub clone dotfiles
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" https://github.com/mislav/dotfiles.git
  assert_gh_called 'config get user -h github.com'
}

@test "clone REPO asks gh api for the login when a token variable is set" {
  serve_github octocat/dotfiles
  stub_gh 'api --hostname github.com user --jq .login' octocat
  GH_TOKEN=secret run hub clone dotfiles
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" https://github.com/octocat/dotfiles.git
  assert_gh_called 'api --hostname github.com user --jq .login'
}

@test "clone REPO without a known login fails before git runs" {
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user --jq .login' '' 1
  empty_dir
  run hub clone dotfiles
  assert_status 1
  local message='hub clone: could not determine your GitHub login for github.com'
  assert_output_equals "$message (run: gh auth login -h github.com)"
  assert_equals "$(ls -A)" ''
}

@test "clone takes dotted names, wikis and .github as repository names" {
  serve_github mislav/.github mislav/mislav.github.io alice/dotfiles.wiki alice/_x
  run hub clone .github
  assert_success
  assert_equals "$(git -C .github remote get-url origin)" https://github.com/mislav/.github.git
  run hub clone mislav.github.io
  assert_success
  assert_equals "$(git -C mislav.github.io remote get-url origin)" \
    https://github.com/mislav/mislav.github.io.git
  run hub clone alice/dotfiles.wiki
  assert_success
  assert_equals "$(git -C dotfiles.wiki remote get-url origin)" \
    https://github.com/alice/dotfiles.wiki.git
  run hub clone alice/_x
  assert_success
  assert_equals "$(git -C _x remote get-url origin)" https://github.com/alice/_x.git
}

@test "clone drops a trailing .git of the shorthand" {
  serve_github alice/dotfiles mislav/tool
  run hub clone alice/dotfiles.git
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" https://github.com/alice/dotfiles.git
  run hub clone tool.git
  assert_success
  assert_equals "$(git -C tool remote get-url origin)" https://github.com/mislav/tool.git
}

@test "clone -p clones over ssh without asking gh" {
  serve_github alice/dotfiles
  run hub clone -p alice/dotfiles
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" git@github.com:alice/dotfiles.git
  assert_equals "$(git -C dotfiles rev-parse HEAD)" "$(server_ref alice/dotfiles main)"
  assert_gh_not_called
}

@test "clone takes -p anywhere outside an option's value, and never passes it to git" {
  serve_github alice/dotfiles
  run hub clone --depth 1 alice/dotfiles -p dots
  assert_success
  assert_equals "$(git -C dots remote get-url origin)" git@github.com:alice/dotfiles.git
  run hub clone alice/dotfiles last -p
  assert_success
  assert_equals "$(git -C last remote get-url origin)" git@github.com:alice/dotfiles.git
}

@test "clone takes -p among the flags of a cluster" {
  serve_github alice/dotfiles
  run hub clone -qp alice/dotfiles first
  assert_success
  assert_output_lacks 'Cloning into'
  assert_equals "$(git -C first remote get-url origin)" git@github.com:alice/dotfiles.git
  run hub clone -pomine alice/dotfiles second
  assert_success
  assert_equals "$(git -C second remote get-url mine)" git@github.com:alice/dotfiles.git
  run hub clone -po mine alice/dotfiles third
  assert_success
  assert_equals "$(git -C third remote get-url mine)" git@github.com:alice/dotfiles.git
  assert_gh_not_called
}

@test "clone -p REPO asks gh only for the login" {
  serve_github mislav/dotfiles
  run hub clone -p dotfiles
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" git@github.com:mislav/dotfiles.git
  assert_equals "$(gh_calls)" 'gh config get user -h github.com'
}

@test "clone uses https when gh has no git_protocol for the host" {
  serve_github alice/dotfiles
  stub_gh 'config get git_protocol -h github.com' '' 1
  run hub clone alice/dotfiles
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" https://github.com/alice/dotfiles.git
}

@test "clone without gh uses https for OWNER/REPO and refuses REPO" {
  serve_github alice/dotfiles
  local nogh
  nogh=$(no_gh_path ssh)
  PATH=$nogh run hub clone alice/dotfiles
  assert_success
  assert_output_lacks 'hub clone'
  assert_equals "$(git -C dotfiles remote get-url origin)" https://github.com/alice/dotfiles.git
  PATH=$nogh run hub clone -p alice/dotfiles dots
  assert_success
  assert_equals "$(git -C dots remote get-url origin)" git@github.com:alice/dotfiles.git
  empty_dir
  PATH=$nogh run hub clone dotfiles
  assert_status 1
  assert_output_equals 'hub clone: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_equals "$(ls -A)" ''
  assert_gh_not_called
}

@test "clone uses ssh when gh's git_protocol for the host is ssh" {
  serve_github alice/dotfiles
  stub_gh 'config get git_protocol -h github.com' ssh
  run hub clone alice/dotfiles
  assert_success
  assert_equals "$(git -C dotfiles remote get-url origin)" git@github.com:alice/dotfiles.git
}

@test "clone uses GH_HOST for the host, the login and the protocol" {
  serve_github ghe.example.com/kim/tool
  stub_gh 'config get user -h ghe.example.com' kim
  stub_gh 'config get git_protocol -h ghe.example.com' https
  GH_HOST=ghe.example.com run hub clone tool
  assert_success
  assert_equals "$(git -C tool remote get-url origin)" https://ghe.example.com/kim/tool.git
  assert_gh_called 'config get user -h ghe.example.com'
  assert_gh_called 'config get git_protocol -h ghe.example.com'
}

@test "clone writes a mixed-case GH_HOST in lowercase and refuses one that is no host name" {
  serve_github ghe.example.com/kim/tool
  stub_gh 'config get git_protocol -h ghe.example.com' https
  GH_HOST=GHE.Example.com run hub clone kim/tool
  assert_success
  assert_equals "$(git -C tool remote get-url origin)" https://ghe.example.com/kim/tool.git
  GH_HOST=-oProxyCommand=x run hub clone kim/lib
  assert_status 1
  assert_output_equals 'hub clone: not a host name: -oProxyCommand=x'
  run ls lib
  assert_failure
}

@test "clone takes the default host from gh's only host, or from GITHUB_HOST" {
  serve_github ghe.example.com/kim/tool ghe.example.com/kim/lib
  mkdir -p "$GH_CONFIG_DIR"
  printf 'ghe.example.com:\n    user: kim\n' >"$GH_CONFIG_DIR/hosts.yml"
  stub_gh 'config get user -h ghe.example.com' kim
  stub_gh 'config get git_protocol -h ghe.example.com' https
  run hub clone tool
  assert_success
  assert_equals "$(git -C tool remote get-url origin)" https://ghe.example.com/kim/tool.git
  rm "$GH_CONFIG_DIR/hosts.yml"
  GITHUB_HOST=ghe.example.com run hub clone kim/lib
  assert_success
  assert_equals "$(git -C lib remote get-url origin)" https://ghe.example.com/kim/lib.git
}

@test "clone -p on a ghe.com host uses the tenant as the ssh user" {
  serve_github acme.ghe.com/kim/tool
  GH_HOST=acme.ghe.com run hub clone -p kim/tool
  assert_success
  assert_equals "$(git -C tool remote get-url origin)" acme@acme.ghe.com:kim/tool.git
}

@test "clone keeps options and the directory in place around the repository" {
  serve_github alice/dotfiles
  second_commit alice/dotfiles
  run hub clone --depth 1 alice/dotfiles --single-branch dots
  assert_success
  assert_equals "$(git -C dots remote get-url origin)" https://github.com/alice/dotfiles.git
  assert_equals "$(git -C dots rev-list --count HEAD)" 1
  assert_equals "$(git -C dots rev-parse --is-shallow-repository)" true
  assert_equals "$(git -C dots config remote.origin.fetch)" \
    '+refs/heads/main:refs/remotes/origin/main'
}

@test "clone never takes an option's separate value for the repository" {
  serve_github alice/dotfiles
  git -C "$(server_dir alice/dotfiles)" branch feature main
  run hub clone -o mine -b feature alice/dotfiles first
  assert_success
  assert_equals "$(git -C first remote get-url mine)" https://github.com/alice/dotfiles.git
  assert_equals "$(git -C first symbolic-ref HEAD)" refs/heads/feature
  run hub clone --origin mine --branch feature -c hub.test=yes alice/dotfiles second
  assert_success
  assert_equals "$(git -C second remote get-url mine)" https://github.com/alice/dotfiles.git
  assert_equals "$(git -C second config hub.test)" yes
  mkdir tmpl
  run hub clone --template tmpl alice/dotfiles third
  assert_success
  assert_equals "$(git -C third remote get-url origin)" https://github.com/alice/dotfiles.git
}

@test "clone never takes the value of any option of its table for the repository" {
  # --noop: --server-option, --shallow-exclude and others cannot run against the test server.
  local option
  for option in -o --origin -b --branch -u --upload-pack --reference --reference-if-able \
    --separate-git-dir --depth --shallow-since --shallow-exclude -j --jobs --template -c \
    --config --filter --bundle-uri --server-option --ref-format --revision; do
    run hub --noop clone "$option" v1 alice/dotfiles dir
    assert_success
    assert_output_equals "git clone $option v1 https://github.com/alice/dotfiles.git dir"
  done
}

@test "clone reads attached values as one word" {
  serve_github alice/dotfiles
  run hub clone -omine --branch=main --depth=1 alice/dotfiles dots
  assert_success
  assert_equals "$(git -C dots remote get-url mine)" https://github.com/alice/dotfiles.git
  assert_equals "$(git -C dots rev-parse --is-shallow-repository)" true
}

@test "clone leaves a -p that is an option's value to git" {
  serve_github alice/dotfiles
  run hub clone -o -p alice/dotfiles
  assert_success
  assert_equals "$(git -C dotfiles config remote.-p.url)" https://github.com/alice/dotfiles.git
}

@test "clone expands a shorthand after -- or --end-of-options" {
  serve_github alice/dotfiles
  run hub clone -- alice/dotfiles dots
  assert_success
  assert_equals "$(git -C dots remote get-url origin)" https://github.com/alice/dotfiles.git
  run hub clone --end-of-options alice/dotfiles eoo
  assert_success
  assert_equals "$(git -C eoo remote get-url origin)" https://github.com/alice/dotfiles.git
}

@test "clone passes words that only look like shorthands to git untouched" {
  serve_github alice/dotfiles
  empty_dir
  local word
  for word in owner_x/r o/r/ x/..git .git; do
    run hub clone "$word"
    assert_failure
    assert_output_contains "repository '$word' does not exist"
  done
  assert_gh_not_called
  assert_equals "$(ls -A)" ''
}

@test "clone passes URLs to git untouched, dropping -p" {
  serve_github alice/dotfiles
  run hub clone -p https://github.com/alice/dotfiles.git first
  assert_success
  assert_equals "$(git -C first remote get-url origin)" https://github.com/alice/dotfiles.git
  run hub clone git@github.com:alice/dotfiles.git second
  assert_success
  assert_equals "$(git -C second remote get-url origin)" git@github.com:alice/dotfiles.git
  run hub clone ssh://git@github.com/alice/dotfiles third
  assert_success
  assert_equals "$(git -C third remote get-url origin)" ssh://git@github.com/alice/dotfiles
  assert_gh_not_called
}

@test "clone passes HOST/OWNER/REPO to git as a path" {
  serve_github alice/dotfiles
  empty_dir
  run hub clone github.com/alice/dotfiles
  assert_failure
  assert_output_contains "repository 'github.com/alice/dotfiles' does not exist"
  assert_gh_not_called
  assert_equals "$(ls -A)" ''
}

@test "clone leaves an existing path of the shorthand's name to git" {
  serve_github mislav/proj alice/proj
  make_repo proj && cd ..
  run hub clone proj copy
  assert_success
  assert_equals "$(git -C copy remote get-url origin)" "$HUB_TEST_TMP/proj"
  mkdir -p alice/proj
  run hub clone alice/proj other
  assert_failure
  assert_output_contains "repository 'alice/proj' does not exist"
  assert_gh_not_called
}

@test "clone leaves NAME to git when NAME.git holds a repository" {
  serve_github mislav/proj
  make_repo src && cd ..
  git clone -q --bare src proj.git
  run hub clone proj copy
  assert_success
  assert_equals "$(git -C copy rev-parse HEAD)" "$(git -C src rev-parse HEAD)"
  assert_equals "$(git -C copy remote get-url origin)" "$HUB_TEST_TMP/proj"
  assert_gh_not_called
}

@test "clone leaves NAME to git when NAME.git is a work tree" {
  serve_github mislav/proj
  make_repo proj.git && cd ..
  run hub clone proj copy
  assert_success
  assert_equals "$(git -C copy rev-parse HEAD)" "$(git -C proj.git rev-parse HEAD)"
  assert_equals "$(git -C copy remote get-url origin)" "$HUB_TEST_TMP/proj"
  assert_gh_not_called
}

@test "clone leaves NAME to git when NAME.bundle exists" {
  serve_github mislav/proj
  make_repo src && cd ..
  git -C src bundle create -q ../proj.bundle main
  run hub clone proj copy
  assert_success
  assert_equals "$(git -C copy rev-parse HEAD)" "$(git -C src rev-parse HEAD)"
  assert_equals "$(git -C copy remote get-url origin)" "$HUB_TEST_TMP/proj"
  assert_gh_not_called
}

@test "clone expands NAME when NAME.git is a directory without a repository" {
  serve_github mislav/plain
  mkdir plain.git
  run hub clone plain
  assert_success
  assert_equals "$(git -C plain remote get-url origin)" https://github.com/mislav/plain.git
}

@test "clone without a repository is git clone's, without -p" {
  run hub clone -p
  assert_status 129
  assert_output_contains 'You must specify a repository to clone.'
  run hub clone --depth 1
  assert_status 129
  assert_output_contains 'You must specify a repository to clone.'
  assert_gh_not_called
}

@test "clone hands a line it cannot read with certainty to git untouched" {
  serve_github alice/dotfiles
  empty_dir
  run hub clone --dep 1 alice/dotfiles
  assert_failure
  assert_output_contains "repository 'alice/dotfiles' does not exist"
  run hub clone -qb main alice/dotfiles
  assert_failure
  assert_output_contains "repository 'alice/dotfiles' does not exist"
  run hub clone alice/dotfiles --depth
  assert_status 129
  assert_output_contains "requires a value"
  assert_gh_not_called
  assert_equals "$(ls -A)" ''
}

@test "clone relays git's failure for a repository that does not exist" {
  empty_dir
  run hub clone alice/missing
  assert_failure
  assert_output_contains 'nothing is served at https://github.com/alice/missing.git'
  assert_equals "$(ls -A)" ''
}

@test "clone runs in the subdirectory it was started from" {
  serve_github alice/dotfiles
  make_repo work
  mkdir sub && cd sub
  run hub clone alice/dotfiles
  assert_success
  assert_equals "$(git -C "$HUB_TEST_TMP/work/sub/dotfiles" remote get-url origin)" \
    https://github.com/alice/dotfiles.git
  cd "$HUB_TEST_TMP"
  mkdir there
  run hub -C there clone alice/dotfiles
  assert_success
  assert_equals "$(git -C there/dotfiles remote get-url origin)" \
    https://github.com/alice/dotfiles.git
}

@test "clone -h prints git's usage" {
  run hub clone -h
  assert_git_help clone
  assert_output_contains 'usage: git clone'
  run hub clone -qph alice/dotfiles
  assert_git_help clone
  assert_output_contains 'usage: git clone'
  assert_output_lacks 'unknown switch'
  assert_gh_not_called
}

@test "clone --help hands the line to git without -p" {
  # git clone --help opens a manual page, which cannot run here.
  run hub --noop clone -p --help
  assert_success
  assert_output_equals 'git clone --help'
  run hub clone -p alice/dotfiles --help
  assert_git_help clone
  assert_output_contains 'usage: git clone'
  assert_output_lacks 'unknown switch'
  assert_gh_not_called
}

@test "help clone prints hub's manual, ending with git's" {
  run hub help clone
  assert_success
  assert_line_equals 0 'Summary: Clone a GitHub repository by its [OWNER/]REPO name.'
  assert_equals "${lines[-1]}" "git's own manual: git clone --help"
}
