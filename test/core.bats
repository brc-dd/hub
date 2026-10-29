#!/usr/bin/env bats
load test_helper

setup() {
  # bats calls the helper's setup via load; re-run it explicitly because we override setup here.
  export HUB_ROOT=$HUB_TEST_ROOT
  HUB_TEST_TMP=$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/hub-test.XXXXXX"); export HUB_TEST_TMP
  export HOME=$HUB_TEST_TMP/home; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=$HUB_TEST_TMP/gitconfig GH_CONFIG_DIR=$HUB_TEST_TMP/gh
  export PATH=$HUB_TEST_ROOT/test/stubs:$PATH
  export HUB_TEST_LOG=$HUB_TEST_TMP/gh.log HUB_TEST_GH_STUBS=$HUB_TEST_TMP/gh.stubs
  : >"$HUB_TEST_LOG"; : >"$HUB_TEST_GH_STUBS"
  unset GH_HOST GITHUB_HOST GH_REPO
  git config --global user.name t; git config --global user.email t@example.test; git config --global init.defaultBranch main
  stub_gh 'config get user -h github.com' 'mislav'
  stub_gh 'config get git_protocol -h github.com' 'https'
  cd "$HUB_TEST_TMP"
  # shellcheck source=../lib/hub/core.sh
  source "$HUB_TEST_ROOT/lib/hub/core.sh"
  hub::find_git
}

@test "parse_remote_url understands https, ssh, scp-like and git URLs" {
  hub::parse_remote_url https://github.com/mislav/hub.git
  [[ $HUB_URL_HOST == github.com && $HUB_URL_OWNER == mislav && $HUB_URL_REPO == hub ]]
  hub::parse_remote_url git@github.com:mislav/hub.git
  [[ $HUB_URL_HOST == github.com && $HUB_URL_OWNER == mislav && $HUB_URL_REPO == hub ]]
  hub::parse_remote_url ssh://git@ssh.github.com:443/mislav/hub
  [[ $HUB_URL_HOST == github.com && $HUB_URL_REPO == hub ]]
  hub::parse_remote_url git://github.com/mislav/hub.git
  [[ $HUB_URL_OWNER == mislav ]]
  hub::parse_remote_url https://ghe.example.com/org/repo
  [[ $HUB_URL_HOST == ghe.example.com && $HUB_URL_OWNER == org && $HUB_URL_REPO == repo ]]
  ! hub::parse_remote_url /local/path/repo.git
  ! hub::parse_remote_url ../relative
  ! hub::parse_remote_url https://github.com/just-owner
}

@test "parse_github_url classifies web URLs" {
  hub::parse_github_url https://github.com/mislav/hub/pull/123
  [[ $HUB_URL_KIND == pull && $HUB_URL_NUMBER == 123 && $HUB_URL_OWNER == mislav && $HUB_URL_REPO == hub && -z $HUB_URL_SHA ]]
  hub::parse_github_url https://github.com/mislav/hub/pull/123/commits/abcdef0123
  [[ $HUB_URL_KIND == pull && $HUB_URL_NUMBER == 123 && $HUB_URL_SHA == abcdef0123 ]]
  hub::parse_github_url 'https://github.com/mislav/hub/pull/123/files?diff=split#r1'
  [[ $HUB_URL_KIND == pull && $HUB_URL_NUMBER == 123 ]]
  hub::parse_github_url https://github.com/mislav/hub/issues/7
  [[ $HUB_URL_KIND == issues && $HUB_URL_NUMBER == 7 ]]
  hub::parse_github_url https://github.com/mislav/hub/commit/deadbeef
  [[ $HUB_URL_KIND == commit && $HUB_URL_SHA == deadbeef ]]
  hub::parse_github_url https://github.com/mislav/hub
  [[ $HUB_URL_KIND == repo ]]
  hub::parse_github_url https://github.com/mislav/hub.git/
  [[ $HUB_URL_KIND == repo && $HUB_URL_REPO == hub ]]
  hub::parse_github_url https://github.com/mislav/hub/tree/main/lib
  [[ $HUB_URL_KIND == tree && $HUB_URL_PATH == main/lib ]]
  hub::parse_github_url https://gist.github.com/mislav/abc123
  [[ $HUB_URL_KIND == gist && $HUB_URL_OWNER == mislav && $HUB_URL_NUMBER == abc123 ]]
  hub::parse_github_url https://gist.github.com/abc123
  [[ $HUB_URL_KIND == gist && $HUB_URL_NUMBER == abc123 ]]
  ! hub::parse_github_url https://gitlab.com/mislav/hub/pull/1
  ! hub::parse_github_url https://github.com/mislav/hub/pull/not-a-number
  ! hub::parse_github_url not-a-url
}

@test "enterprise hosts come from hub.host, GH_HOST and GITHUB_HOST" {
  ! hub::is_known_host ghe.example.com
  git config --global --add hub.host ghe.example.com
  hub::is_known_host GHE.Example.com
  GH_HOST=other.example.com hub::is_known_host other.example.com
  GITHUB_HOST=third.example.com hub::is_known_host third.example.com
}

@test "main_remote prefers upstream, then github, then origin, then any GitHub remote" {
  make_repo r origin=https://github.com/me/r.git mirror=https://gitlab.com/me/r.git
  [[ $(hub::main_remote) == origin ]]
  git remote add github git@github.com:org/r.git
  [[ $(hub::main_remote) == github ]]
  git remote add upstream https://github.com/upstream/r.git
  [[ $(hub::main_remote) == upstream ]]
  [[ $(hub::main_project) == upstream/r ]]
  git remote remove upstream; git remote remove github; git remote remove origin
  [[ -z $(hub::main_remote) ]]
  git remote add fork https://github.com/someone/r.git
  [[ $(hub::main_remote) == fork ]]
}

@test "main_project honours GH_REPO with and without a host" {
  make_repo r
  [[ $(GH_REPO=cli/cli hub::main_project) == cli/cli ]]
  GH_REPO=ghe.example.com/org/repo hub::main_project >/dev/null
  GH_REPO=ghe.example.com/org/repo
  [[ $(hub::main_project) == org/repo ]]
  hub::main_project >/dev/null; [[ $HUB_PROJECT_HOST == ghe.example.com ]]
}

@test "default_branch reads the remote HEAD, then asks gh, then falls back to main" {
  make_repo r origin=https://github.com/me/r.git
  stub_gh 'repo view github.com/me/r --json defaultBranchRef *' 'trunk'
  [[ $(hub::default_branch) == trunk ]]
  [[ $(GH_HOST=enterprise.example hub::default_branch) == trunk ]]
  set_remote_head origin develop
  [[ $(hub::default_branch) == develop ]]
  [[ $(hub::default_branch origin) == develop ]]
  git remote remove origin
  [[ $(hub::default_branch) == main ]]
}

@test "git_url follows hub.protocol, then gh's git_protocol, then https" {
  make_repo r
  [[ $(hub::git_url mislav/hub) == https://github.com/mislav/hub.git ]]
  stub_gh 'config get git_protocol -h github.com' 'ssh'
  [[ $(hub::git_url mislav/hub) == git@github.com:mislav/hub.git ]]
  git config --global hub.protocol https
  [[ $(hub::git_url mislav/hub) == https://github.com/mislav/hub.git ]]
  git config --global hub.protocol ssh
  [[ $(hub::git_url mislav/hub) == git@github.com:mislav/hub.git ]]
  [[ $(hub::git_url mislav/hub ghe.example.com https) == https://ghe.example.com/mislav/hub.git ]]
}

@test "shorthand detection and expansion" {
  hub::is_shorthand mislav/hub
  hub::is_shorthand dotfiles
  hub::is_shorthand my_org/some.repo-name
  ! hub::is_shorthand https://github.com/mislav/hub
  ! hub::is_shorthand git@github.com:mislav/hub.git
  ! hub::is_shorthand a/b/c
  mkdir existing-dir
  ! hub::is_shorthand existing-dir
  [[ $(hub::expand_project dotfiles) == mislav/dotfiles ]]
  [[ $(hub::expand_project someone/dotfiles) == someone/dotfiles ]]
}

@test "current_user falls back to the API when gh has no cached login" {
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user -q .login' 'apiuser'
  [[ $(hub::current_user) == apiuser ]]
}

@test "current_user ignores the cached login when a token overrides gh's credentials" {
  stub_gh 'api --hostname github.com user -q .login' 'tokenuser'
  [[ $(hub::current_user) == mislav ]]
  [[ $(GH_TOKEN=x hub::current_user) == tokenuser ]]
  [[ $(GITHUB_TOKEN=x hub::current_user) == tokenuser ]]
  [[ $(GH_ENTERPRISE_TOKEN=x hub::current_user) == tokenuser ]]
}

@test "split_message takes the first paragraph as title and the rest as body" {
  hub::split_message $'Title line\n\nBody line 1\nBody line 2\n\n'
  [[ $HUB_MSG_TITLE == "Title line" && $HUB_MSG_BODY == $'Body line 1\nBody line 2' ]]
  hub::split_message $'\n\nTwo line\ntitle\n\n\nbody'
  [[ $HUB_MSG_TITLE == "Two line title" && $HUB_MSG_BODY == body ]]
  hub::split_message 'only a title'
  [[ $HUB_MSG_TITLE == "only a title" && -z $HUB_MSG_BODY ]]
  hub::split_message ''
  [[ -z $HUB_MSG_TITLE && -z $HUB_MSG_BODY ]]
}

@test "quote only quotes what the shell would mangle" {
  [[ $(hub::quote git push origin feature/x) == "git push origin feature/x" ]]
  [[ $(hub::quote git commit -m 'two words') == "git commit -m two\\ words" ]]
}

@test "noop prints instead of running, while queries still run" {
  make_repo r
  HUB_NOOP=1
  [[ $(hub::git tag v1) == "git tag v1" ]]
  [[ -z $(git tag) ]]
  [[ $(hub::current_branch) == main ]]
  HUB_NOOP=0
  hub::git tag v1 >/dev/null
  [[ $(git tag) == v1 ]]
}

@test "HUB_PROTOCOL wins over hub.protocol and gh's setting" {
  make_repo r
  git config --global hub.protocol https
  [[ $(HUB_PROTOCOL=ssh hub::git_url mislav/hub) == git@github.com:mislav/hub.git ]]
  [[ $(HUB_PROTOCOL=https hub::git_url mislav/hub) == https://github.com/mislav/hub.git ]]
  [[ $(HUB_PROTOCOL=git hub::git_url mislav/hub) == git@github.com:mislav/hub.git ]]
}

@test "GitHub Enterprise Cloud SSH URLs use the tenant as the user" {
  [[ $(hub::git_url org/repo tenant.ghe.com ssh) == tenant@tenant.ghe.com:org/repo.git ]]
  [[ $(hub::git_url org/repo ghe.example.com ssh) == git@ghe.example.com:org/repo.git ]]
  [[ $(hub::git_url org/repo tenant.ghe.com https) == https://tenant.ghe.com/org/repo.git ]]
}

@test "GITHUB_HOST is passed on to gh as GH_HOST" {
  run env -u GH_HOST GITHUB_HOST=ghe.example.com bash -c 'source "$HUB_TEST_ROOT/lib/hub/core.sh"; printf "%s\n" "$GH_HOST"'
  [[ $output == ghe.example.com ]]
  run env GH_HOST=other.example.com GITHUB_HOST=ghe.example.com bash -c 'source "$HUB_TEST_ROOT/lib/hub/core.sh"; printf "%s\n" "$GH_HOST"'
  [[ $output == other.example.com ]]
}

@test "default_branch asks gh about the remote's own host" {
  make_repo r origin=https://ghe.example.com/org/r.git
  git config --global --add hub.host ghe.example.com
  stub_gh 'repo view ghe.example.com/org/r --json defaultBranchRef *' 'develop'
  [[ $(hub::default_branch) == develop ]]
  hub::default_branch >/dev/null
  [[ $HUB_PROJECT_HOST == ghe.example.com ]]
}

@test "open_url prefers GH_BROWSER over BROWSER" {
  [[ $(GH_BROWSER='echo gh-browser' BROWSER='echo browser' hub::open_url https://example.test) == "gh-browser https://example.test" ]]
  [[ $(BROWSER='echo browser' hub::open_url https://example.test) == "browser https://example.test" ]]
}

@test "host follows gh's default: the only logged-in host, else github.com" {
  [[ $(hub::host) == github.com ]]
  mkdir -p "$GH_CONFIG_DIR"
  printf 'ghe.example.com:\n    user: me\n    git_protocol: ssh\n' >"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_DEFAULT_HOST
  [[ $(hub::host) == ghe.example.com ]]
  [[ $(hub::git_url org/repo) == https://ghe.example.com/org/repo.git ]]
  printf 'github.com:\n    user: me\n' >>"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_DEFAULT_HOST
  [[ $(hub::host) == github.com ]]
  [[ $(GH_HOST=other.example.com hub::host) == other.example.com ]]
}
