#!/usr/bin/env bats
# The shared helpers of lib/hub/core.sh, sourced into the test's shell.

load test_helper

setup() {
  hub_test_setup
  export HUB_ROOT=$HUB_TEST_ROOT HUB_LIB=$HUB_TEST_ROOT/lib/hub HUB_COMMAND=test
  # shellcheck source=lib/hub/core.sh
  source "$HUB_LIB/core.sh"
}

# url_fields URL : HUB_URL's fields after hub::parse_github_url, joined by |.
url_fields() {
  hub::parse_github_url "$1" || return
  local key out=
  for key in host owner repo kind number sha format range; do out+=${HUB_URL[$key]-}'|'; done
  printf '%s\n' "${out%|}"
}

# args_of FUNCTION ARGS... : HUB_ARGS after FUNCTION ARGS..., each word in <>.
args_of() {
  "$@" || return
  printf '<%s>' "${HUB_ARGS[@]}"
}

# parses_to URL EXPECTED : hub::parse_url URL prints EXPECTED, or fails when EXPECTED is empty.
parses_to() {
  run hub::parse_url "$1"
  if [[ -n $2 ]]; then assert_success || return; else assert_failure || return; fi
  assert_output_equals "$2" || {
    printf 'for URL: %s\n' "$1"
    return 1
  }
}

@test "die, warn and usage_error print hub's message format on stderr" {
  run hub::die 'feature is not pushed to origin (use -p to push it)'
  assert_status 1
  assert_output_equals 'hub test: feature is not pushed to origin (use -p to push it)'
  run --separate-stderr hub::die 'on stderr'
  assert_output_equals ''
  run hub::warn two words
  assert_success
  assert_output_equals 'hub test: warning: two words'
  HUB_COMMAND='' run hub::die 'no command yet'
  assert_output_equals 'hub: no command yet'
  HUB_COMMAND=version run hub::usage_error 'unknown option: -x'
  assert_status 1
  local usage=$'Usage: hub version [--build-options]\n       hub --version [--build-options]'
  assert_output_equals "hub version: unknown option: -x"$'\n'"$usage"
  HUB_COMMAND=version run --separate-stderr hub::usage_error 'unknown option: -x'
  assert_output_equals ''
}

@test "module_doc prints the leading comment block and usage prints the module's" {
  printf '%s\n' '# shellcheck shell=bash' '# shellcheck disable=SC2034  # a reason' \
    '# Summary: A thing.' '# Usage: hub thing' '#' '#   $ hub thing' '' '# not this' >thing.sh
  run hub::module_doc thing.sh
  assert_output_equals $'Summary: A thing.\nUsage: hub thing\n\n  $ hub thing'
  HUB_COMMAND=version run hub::usage
  assert_success
  assert_output_equals "$(hub::module_doc "$HUB_LIB/cmd/version.sh")"
}

@test "quote prints the words on one line, quoted to paste back" {
  run hub::quote git tag 'two words' '' '*' "it's" $'a\nb'
  assert_output_equals "git tag two\\ words '' \\* it\\'s \$'a\\nb'"
}

@test "run, git and gh print instead of running under --noop, while queries run" {
  make_repo r
  stub_gh 'api user' octo
  HUB_NOOP=1
  run hub::git tag 'v 1'
  assert_output_equals 'git tag v\ 1'
  run hub::gh repo fork --org o
  assert_output_equals 'gh repo fork --org o'
  run hub::run touch file
  assert_output_equals 'touch file'
  run hub::exec_git push origin main
  assert_success
  assert_output_equals 'git push origin main'
  run hub::exec_gh pr list
  assert_output_equals 'gh pr list'
  run hub::git_query rev-parse --abbrev-ref HEAD
  assert_output_equals main
  run hub::gh_query api user
  assert_output_equals octo
  assert_equals "$(git tag)" ''
  assert_equals "$(gh_calls)" 'gh api user'
  assert_equals "$(ls)" ''
}

@test "run, git and gh run the command and return its status" {
  make_repo r
  hub::git tag v1
  assert_equals "$(git tag)" v1
  stub_gh 'repo fork *' forked
  stub_gh 'failing' oops 3
  GH_REPO=github.com/o/r run hub::gh repo fork --remote
  assert_output_equals forked
  assert_gh_called 'GH_REPO=github.com/o/r gh repo fork --remote'
  run hub::gh failing
  assert_status 3
  run hub::exec_git rev-parse --abbrev-ref HEAD
  assert_output_equals main
  run hub::git_query rev-parse --verify nothing
  assert_status 128
  assert_output_equals ''
}

@test "require_gh and the gh runners die without gh on PATH" {
  local path
  path=$(no_gh_path)
  PATH=$path run hub::require_gh
  assert_status 1
  assert_output_equals 'hub test: this command needs the GitHub CLI, gh (https://cli.github.com)'
  PATH=$path run hub::gh repo fork
  assert_output_contains 'needs the GitHub CLI'
  PATH=$path run hub::gh_query api user
  assert_status 1
  PATH=$path run hub::exec_gh pr list
  assert_status 1
  assert_output_contains 'needs the GitHub CLI'
  assert_gh_not_called
}

@test "require_repo passes in a work tree and relays git's message otherwise" {
  run hub::require_repo
  assert_status 1
  assert_output_contains 'fatal: not a git repository'
  make_repo r
  run hub::require_repo
  assert_success
  assert_output_equals ''
  cd .git
  run hub::require_repo
  assert_status 1
  assert_output_equals 'hub test: not inside a work tree'
  cd ..
  git config push.default banana
  run hub::require_repo
  assert_status 1
  assert_output_contains "fatal: bad config variable 'push.default'"
}

@test "toplevel and current_branch read the work tree and the branch HEAD is on" {
  make_repo r
  mkdir sub
  cd sub
  run hub::toplevel
  assert_output_equals "$HUB_TEST_TMP/r"
  git tag topic
  git switch -q -c topic
  run hub::current_branch
  assert_success
  assert_output_equals topic
  git switch -q --detach
  run hub::current_branch
  assert_status 1
  assert_output_equals ''
}

@test "remotes, remote_exists and valid_remote_name know the remotes" {
  make_repo r origin=https://github.com/o/r.git fork=git@github.com:me/r.git
  mkdir -p .git/remotes
  printf 'URL: https://github.com/o/legacy.git\n' >.git/remotes/legacy
  run hub::remotes
  assert_output_equals $'fork\norigin'
  hub::remote_exists origin
  hub::remote_exists legacy
  run hub::remote_exists https://github.com/o/r.git
  assert_failure
  run hub::remote_exists nope
  assert_failure
  # git remote add refuses -x, git config does not; git push reads both kinds below.
  git config remote.-x.url https://github.com/x/r.git
  hub::remote_exists -x
  git config --global remote.two.url https://github.com/mislav/two.git
  hub::remote_exists two
  GIT_CONFIG_PARAMETERS="'remote.three.url=https://github.com/x/three.git'" \
    hub::remote_exists three
  hub::valid_remote_name alice
  hub::valid_remote_name my.fork-2
  local name
  for name in -x --push '' 'a b' a..b 'a:b'; do
    run hub::valid_remote_name "$name"
    assert_failure
  done
}

@test "require_new_remote refuses a name that cannot be a remote's, or is one" {
  make_repo r origin=https://github.com/o/r.git
  run hub::require_new_remote fresh
  assert_success
  assert_output_equals ''
  run hub::require_new_remote origin
  assert_status 1
  assert_output_equals \
    'hub test: remote already exists: origin (name another with --remote-name NAME)'
  run hub::require_new_remote -x
  assert_status 1
  assert_output_equals 'hub test: not a remote name: -x'
  run hub::require_new_remote ''
  assert_output_equals "hub test: not a remote name: ''"
  assert_equals "$(git remote)" origin
}

@test "remote_head names the branch the remote's HEAD points at, when both exist" {
  make_repo r origin=https://github.com/o/r.git
  run hub::remote_head origin
  assert_failure
  assert_output_equals ''
  set_remote_head origin develop
  run hub::remote_head origin
  assert_success
  assert_output_equals develop
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
  run hub::remote_head origin
  assert_failure
  assert_output_equals ''
  git symbolic-ref refs/remotes/origin/HEAD refs/heads/main
  run hub::remote_head origin
  assert_failure
  run hub::remote_head ''
  assert_failure
}

@test "default_branch follows the remote HEAD, else asks gh, else fails" {
  make_repo r origin=https://github.com/o/r.git
  set_remote_head origin develop
  run hub::default_branch github.com o r origin
  assert_output_equals develop
  assert_gh_not_called
  git update-ref -d refs/remotes/origin/develop
  stub_gh 'repo view github.com/o/r --json defaultBranchRef *' trunk
  run hub::default_branch github.com o r origin
  assert_success
  assert_output_equals trunk
  assert_gh_called 'repo view github.com/o/r --json defaultBranchRef --jq .defaultBranchRef.name'
  stub_gh 'repo view ghe.example/o/r *' '' 1
  run hub::default_branch ghe.example o r
  assert_status 1
  assert_output_equals ''
}

@test "default_branch skips gh without a host or without gh, and fails quietly" {
  make_repo r origin=https://gitlab.com/o/r.git
  run hub::default_branch '' '' '' origin
  assert_status 1
  assert_output_equals ''
  assert_gh_not_called
  PATH=$(no_gh_path) run hub::default_branch github.com o r origin
  assert_status 1
  assert_output_equals ''
  set_remote_head origin trunk
  PATH=$(no_gh_path) run hub::default_branch github.com o r origin
  assert_success
  assert_output_equals trunk
}

@test "repo_name is the project's name, else the directory's" {
  make_repo proj origin=https://github.com/o/Real-Name.git
  mkdir sub && cd sub
  run hub::repo_name
  assert_output_equals Real-Name
  cd "$HUB_TEST_TMP"
  make_repo 'my project!'
  run hub::repo_name
  assert_output_equals my-project-
  cd .git
  run hub::repo_name
  assert_output_equals my-project-
  cd "$HUB_TEST_TMP"
  git init -q --bare tool.git
  cd tool.git
  run hub::repo_name
  assert_output_equals tool
}

@test "repo_name fails on an invalid GH_REPO instead of taking the directory's name" {
  make_repo myrepo
  GH_REPO='not a repo' run hub::repo_name
  assert_status 1
  assert_output_equals 'hub test: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
  GH_REPO=o/other run hub::repo_name
  assert_output_equals other
}

@test "push_remote takes branch.NAME.pushRemote, then remote.pushDefault" {
  make_repo r origin=https://github.com/o/r.git fork=https://github.com/mislav/r.git
  git config remote.pushDefault origin
  git config branch.main.pushRemote other
  run hub::push_remote main
  assert_output_equals other
  git config --unset branch.main.pushRemote
  run hub::push_remote main
  assert_output_equals origin
  assert_gh_not_called
}

@test "push_remote fails on an empty pushRemote or pushDefault, as git push does" {
  make_repo r origin=https://github.com/o/r.git
  git config branch.main.pushRemote ''
  git config remote.pushDefault origin
  run hub::push_remote main
  assert_status 1
  assert_output_equals ''
  git config --unset branch.main.pushRemote
  git config remote.pushDefault ''
  run hub::push_remote main
  assert_status 1
  assert_output_equals ''
}

@test "push_remote takes the remote of an upstream of the branch's own name" {
  make_repo r origin=https://github.com/o/r.git other=https://github.com/x/r.git
  git branch topic
  git config branch.topic.remote other
  git config branch.topic.merge refs/heads/topic
  run hub::push_remote topic
  assert_output_equals other
}

@test "push_remote skips an upstream in the repository itself" {
  make_repo r origin=https://github.com/o/r.git other=https://github.com/x/r.git
  git branch topic
  git config branch.topic.remote .
  git config branch.topic.merge refs/heads/topic
  run hub::push_remote topic
  assert_output_equals origin
}

@test "push_remote skips a start-point upstream and takes the only remote" {
  make_repo r origin=https://github.com/o/r.git
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b fix --track origin/main
  run hub::push_remote fix
  assert_output_equals origin
  git remote rename origin up
  run hub::push_remote fix
  assert_output_equals up
}

@test "push_remote takes your fork next to the parent, whichever is origin" {
  make_repo r origin=https://github.com/o/r.git mine=git@github.com:Mislav/r.git
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b fix --track origin/main
  run hub::push_remote fix
  assert_output_equals mine
  assert_gh_called 'config get user -h github.com'
  cd "$HUB_TEST_TMP"
  make_repo r2 origin=https://github.com/mislav/r.git upstream=https://github.com/o/r.git
  git update-ref refs/remotes/upstream/main HEAD
  git checkout -q -b fix --track upstream/main
  run hub::push_remote fix
  assert_output_equals origin
  cd "$HUB_TEST_TMP"
  make_repo r3 origin=https://github.com/o/r.git parent=https://github.com/o/r.git
  git remote set-url --push parent https://github.com/mislav/r.git
  run hub::push_remote main
  assert_output_equals parent
}

@test "push_remote fails without your login rather than guess origin, the parent" {
  make_repo r origin=https://github.com/o/r.git mine=https://github.com/mislav/r.git \
    other=https://github.com/x/r.git
  stub_gh 'config get user -h github.com' '' 1
  run hub::push_remote main
  assert_status 1
  assert_output_equals ''
  assert_equals "$(gh_calls)" 'gh config get user -h github.com'
}

@test "push_remote takes origin when two remotes are forks of your login" {
  make_repo r up=https://github.com/o/r.git a=https://github.com/mislav/r.git \
    b=git@github.com:MISLAV/r2.git origin=https://github.com/o/r.git
  run hub::push_remote main
  assert_output_equals origin
}

@test "push_remote falls back to origin, and fails without one" {
  make_repo r origin=https://github.com/o/r.git other=https://github.com/x/r.git
  run hub::push_remote main
  assert_output_equals origin
  git remote rename origin first
  run hub::push_remote main
  assert_status 1
  assert_output_equals ''
  cd "$HUB_TEST_TMP"
  make_repo none
  run hub::push_remote main
  assert_status 1
  assert_output_equals ''
}

@test "pushed says whether the remote branch contains HEAD, else how far behind it is" {
  make_repo r origin=https://github.com/o/r.git
  run hub::pushed main origin
  assert_status 1
  assert_output_equals ''
  git update-ref refs/remotes/origin/main HEAD
  run hub::pushed main origin
  assert_success
  assert_output_equals ''
  git commit -q --allow-empty -m two
  git commit -q --allow-empty -m three
  run hub::pushed main origin
  assert_status 2
  assert_output_equals 2
}

@test "pushed reads the branch it is given, not HEAD" {
  make_repo r origin=https://github.com/o/r.git
  git branch topic
  git update-ref refs/remotes/origin/topic HEAD
  git commit -q --allow-empty -m on-main
  run hub::pushed topic origin
  assert_success
  commit_on topic on-topic
  git update-ref refs/remotes/origin/main HEAD
  run hub::pushed topic origin
  assert_status 2
  assert_output_equals 1
  run hub::pushed main origin
  assert_success
}

@test "pushed returns 1 quietly for an unborn branch" {
  make_repo r origin=https://github.com/o/r.git
  git update-ref refs/remotes/origin/topic HEAD
  git checkout -q --orphan topic
  run hub::pushed topic origin
  assert_status 1
  assert_output_equals ''
  run hub::pushed nothing origin
  assert_status 1
  assert_output_equals ''
}

@test "gh_hosts reads gh's hosts.yml where gh keeps it, quoted keys included" {
  run hub::gh_hosts
  assert_output_equals ''
  mkdir -p "$GH_CONFIG_DIR"
  printf '%s\n' 'ghe.example.com:' '    user: me' '    git_protocol: ssh' \
    '"github.com": # a comment' '    users:' '        me:' "'other.example':" \
    '# github.io:' >"$GH_CONFIG_DIR/hosts.yml"
  run hub::gh_hosts
  assert_output_equals $'ghe.example.com\ngithub.com\nother.example'
  unset GH_CONFIG_DIR
  mkdir -p "$XDG_CONFIG_HOME/gh"
  printf 'xdg.example:\n' >"$XDG_CONFIG_HOME/gh/hosts.yml"
  run hub::gh_hosts
  assert_output_equals xdg.example
  unset XDG_CONFIG_HOME
  mkdir -p "$HOME/.config/gh"
  printf 'home.example:\n' >"$HOME/.config/gh/hosts.yml"
  run hub::gh_hosts
  assert_output_equals home.example
}

@test "host is GH_HOST, else the only gh host, else github.com" {
  run hub::host
  assert_output_equals github.com
  mkdir -p "$GH_CONFIG_DIR"
  printf 'ghe.example.com:\n    user: me\n' >"$GH_CONFIG_DIR/hosts.yml"
  run hub::host
  assert_output_equals ghe.example.com
  printf 'github.com:\n' >>"$GH_CONFIG_DIR/hosts.yml"
  run hub::host
  assert_output_equals github.com
  GH_HOST=other.example run hub::host
  assert_output_equals other.example
}

@test "host is in lowercase, and an invalid GH_HOST is refused" {
  GH_HOST=GHE.Example.com run hub::host
  assert_output_equals ghe.example.com
  mkdir -p "$GH_CONFIG_DIR"
  printf 'GHE.Example.com:\n    user: me\n' >"$GH_CONFIG_DIR/hosts.yml"
  run hub::host
  assert_output_equals ghe.example.com
  local host
  for host in -x ghe.example/o; do
    GH_HOST=$host run hub::host
    assert_status 1
    assert_output_equals "hub test: not a host name: $host"
  done
  GH_HOST='a b' run hub::host
  assert_status 1
  assert_output_equals 'hub test: not a host name: a\ b'
}

@test "known_host knows github.com, GH_HOST and gh's hosts, in any case" {
  mkdir -p "$GH_CONFIG_DIR"
  printf 'ghe.example.com:\n' >"$GH_CONFIG_DIR/hosts.yml"
  hub::known_host GitHub.COM
  hub::known_host GHE.example.com
  run hub::known_host other.example
  assert_failure
  run hub::known_host ''
  assert_failure
  GH_HOST=Other.Example hub::known_host other.example
}

@test "GITHUB_HOST is exported as GH_HOST when GH_HOST is not set" {
  export GITHUB_HOST=old.example
  source "$HUB_LIB/core.sh"
  run bash -c 'printf %s "$GH_HOST"'
  assert_output_equals old.example
  export GH_HOST=new.example
  source "$HUB_LIB/core.sh"
  assert_equals "$GH_HOST" new.example
}

@test "parse_url reads every GitHub remote URL form" {
  local url
  for url in https://github.com/o/r https://github.com/o/r.git https://github.com/o/r/ \
    https://github.com/o/r.git/ https://user:secret@GitHub.com:443/o/r.git http://github.com/o/r \
    ssh://git@github.com/o/r.git ssh://git@ssh.github.com:443/o/r.git git://github.com/o/r.git \
    git+ssh://git@github.com/o/r ssh+git://github.com/o/r git@github.com:o/r.git github.com:o/r \
    org-123@GitHub.com:o/r.git git@ssh.github.com:o/r; do
    parses_to "$url" 'github.com o r'
  done
  GH_HOST=ghe.example parses_to git@GHE.example:Org/Repo.git 'ghe.example Org Repo'
}

@test "parse_url refuses paths, other hosts and other shapes" {
  local url
  for url in /local/path/repo.git ../relative dir/x:y o/r https://github.com/just-owner \
    file:///srv/o/r.git https://github.com/o/r/extra https://gitlab.com/o/r not-a-url \
    'git@-oProxyCommand=x:o/r' 'https://github.com/o/r x' https://github.com//r '' \
    'https://github.com/o/r?x=1' 'https://github.com/o/r#x' ssh://git@github.com/~o/r \
    https://github.com/o/.. https://github.com/-o/r https://github.com/o_x/r \
    https://ssh.github.com/o/r; do
    parses_to "$url" ''
  done
  # None reaches ssh -G: -oProxyCommand=x would be an option there.
  assert_equals "$(cat "$HUB_TEST_TMP/ssh.log" 2>/dev/null)" ''
}

@test "parse_url resolves an ssh alias once with ssh -G, never an https host" {
  mkdir -p "$HOME/.ssh"
  printf '%s\n' 'Host gh-work' '  HostName ssh.github.com' 'Host gh-plain' \
    '  HostName GitHub.com' 'Host Gh-Work' '  HostName github.com' >"$HOME/.ssh/config"
  parses_to gh-work:o/r.git 'github.com o r'
  assert_equals "$(<"$HUB_TEST_TMP/ssh.log")" '-G gh-work'
  parses_to ssh://git@gh-plain/o/r 'github.com o r'
  parses_to https://gh-work/o/r ''
  parses_to git@github.com:o/r 'github.com o r'
  parses_to git@nowhere.example:o/r ''
  # ssh matches Host patterns case-sensitively, as git hands the host over.
  parses_to git@Gh-Work:o/r 'github.com o r'
  assert_equals "$(<"$HUB_TEST_TMP/ssh.log")" \
    $'-G gh-work\n-G gh-plain\n-G nowhere.example\n-G Gh-Work'
}

@test "remote_project reads a remote's fetch or push URL" {
  make_repo r origin=https://github.com/o/r.git
  git remote set-url --push origin git@github.com:me/r.git
  run hub::remote_project origin
  assert_output_equals 'github.com o r'
  run hub::remote_project origin push
  assert_output_equals 'github.com me r'
  run hub::remote_project nope
  assert_failure
}

@test "project prefers upstream, github, origin, then any GitHub remote" {
  make_repo r
  run hub::project
  assert_status 1
  assert_output_equals 'hub test: no GitHub remote found (looked for upstream, github, origin)'
  run hub::project_remote
  assert_failure
  git remote add aaa https://gitlab.com/x/y.git
  git remote add zed https://github.com/z/r.git
  run hub::project
  assert_output_equals 'github.com z r'
  run hub::project_remote
  assert_output_equals zed
  git remote add origin https://github.com/o/r.git
  run hub::project
  assert_output_equals 'github.com o r'
  git remote add github https://github.com/g/r.git
  run hub::project
  assert_output_equals 'github.com g r'
  git remote add upstream https://github.com/u/r.git
  run hub::project
  assert_output_equals 'github.com u r'
  run hub::project_remote
  assert_output_equals upstream
}

@test "project takes GH_REPO, and project_remote finds the remote it names" {
  make_repo r origin=https://github.com/o/r.git fork=https://github.com/Me/r.git
  GH_REPO=ghe.example/a/b run hub::project
  assert_output_equals 'ghe.example a b'
  GH_REPO=ghe.example/a/b run hub::project_remote
  assert_failure
  GH_REPO=ME/R run hub::project_remote
  assert_output_equals fork
  GH_REPO=o/r/ run hub::project
  assert_status 1
  assert_output_equals 'hub test: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
  GH_HOST=ghe.corp:8443 GH_REPO=o/r run hub::project
  assert_status 1
  assert_output_equals 'hub test: not a host name: ghe.corp:8443'
}

@test "parse_project reads OWNER/REPO, HOST/OWNER/REPO and URLs" {
  run hub::parse_project o/r
  assert_output_equals 'github.com o r'
  GH_HOST=ghe.example run hub::parse_project o/r
  assert_output_equals 'ghe.example o r'
  run hub::parse_project GHE.Example/org/repo
  assert_output_equals 'ghe.example org repo'
  run hub::parse_project o/r.git
  assert_output_equals 'github.com o r'
  run hub::parse_project ghe.example/o/r.git
  assert_output_equals 'ghe.example o r'
  run hub::parse_project https://github.com/o/r.git/
  assert_output_equals 'github.com o r'
  run hub::parse_project git@github.com:o/r.git
  assert_output_equals 'github.com o r'
}

@test "parse_project refuses anything else" {
  local str
  for str in o/r/ /o/r o//r host/o/r/ o 'o/r x' o/r/x/y '' https://gitlab.com/o/r; do
    run hub::parse_project "$str"
    assert_failure
  done
}

@test "parse_project checks the owner, repository and host it reads" {
  local str
  for str in -o/r o_x/r o/. o/.. 'o/r!' o/r/ cli/cli/issues -x.example/o/r a_b.example/o/r \
    ghe.example/-o/r ghe.example/o/.. o/.git ghe.example/o/.git; do
    run hub::parse_project "$str"
    assert_failure
    assert_output_equals ''
  done
  run hub::parse_project my-org/some.repo_name
  assert_output_equals 'github.com my-org some.repo_name'
  GH_HOST=GHE.Example run hub::parse_project o/r
  assert_output_equals 'ghe.example o r'
  GH_HOST=ghe run hub::parse_project GHE/o/r
  assert_output_equals 'ghe o r'
  GH_REPO=-o/r run hub::project
  assert_status 1
  assert_output_equals 'hub test: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
}

@test "parse_github_url reads the kinds of GitHub web URLs" {
  run url_fields https://github.com/o/r
  assert_output_equals 'github.com|o|r|repo||||'
  run url_fields https://GitHub.com/o/r.git/
  assert_output_equals 'github.com|o|r|repo||||'
  run url_fields 'https://github.com/o/r/pull/12/files?diff=split#top'
  assert_output_equals 'github.com|o|r|pull|12|||'
  run url_fields https://github.com/o/r/pull/12.patch
  assert_output_equals 'github.com|o|r|pull|12||patch|'
  run url_fields https://github.com/o/r/pull/12/commits/ABCDEF1234.diff
  assert_output_equals 'github.com|o|r|pull|12|ABCDEF1234|diff|'
  run url_fields https://github.com/o/r/commit/abc1234#diff
  assert_output_equals 'github.com|o|r|commit||abc1234||'
  run url_fields http://github.com/o/r/issues/7
  assert_output_equals 'github.com|o|r|issues|7|||'
  run url_fields https://github.com/o/r/compare/main...feature/x.patch
  assert_output_equals 'github.com|o|r|compare|||patch|main...feature/x'
  run url_fields https://github.com/o/r/tree/main/src
  assert_output_equals 'github.com|o|r|tree||||'
  GH_HOST=ghe.example run url_fields https://ghe.example/o/r/pull/3
  assert_output_equals 'ghe.example|o|r|pull|3|||'
}

@test "parse_github_url reads pull/N/commits as the pull request and a bare compare as no range" {
  run url_fields https://github.com/o/r/pull/12/commits
  assert_success
  assert_output_equals 'github.com|o|r|pull|12|||'
  run url_fields https://github.com/o/r/pull/12/commits/
  assert_output_equals 'github.com|o|r|pull|12|||'
  run url_fields https://github.com/o/r/compare
  assert_success
  assert_output_equals 'github.com|o|r|compare||||'
  run url_fields https://github.com/o/r/compare/
  assert_output_equals 'github.com|o|r|compare||||'
  hub::parse_github_url https://github.com/o/r/compare
  assert_equals "${HUB_URL[range]-unset}" unset
}

@test "parse_github_url refuses other hosts and commits that are not hex" {
  local url
  for url in https://gitlab.com/o/r/pull/1 https://github.com/o/r/commit/main \
    https://github.com/o/r/commit/v1.0 https://github.com/o/r/commit/abc \
    https://github.com/o/r/pull/1/commits/main not-a-url https://github.com/just-owner; do
    run url_fields "$url"
    assert_failure
  done
}

@test "login reads gh's cached user, unless a token variable is set" {
  run hub::login
  assert_output_equals mislav
  assert_equals "$(gh_calls)" 'gh config get user -h github.com'
  : >"$HUB_TEST_GH_LOG"
  stub_gh 'api --hostname github.com user --jq .login' octocat
  local var
  for var in GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; do
    export "$var=token"
    run hub::login github.com
    assert_output_equals octocat
    unset "$var"
  done
  run grep -c 'config get user' "$HUB_TEST_GH_LOG"
  assert_output_equals 0
}

@test "login dies when nothing answers, asking the API only with a token variable" {
  local message='hub test: could not determine your GitHub login for ghe.example'
  stub_gh 'config get user -h ghe.example' '' 1
  stub_gh 'api --hostname ghe.example user --jq .login' bob
  run hub::login ghe.example
  assert_status 1
  assert_output_equals "$message (run: gh auth login -h ghe.example)"
  assert_equals "$(gh_calls)" 'gh config get user -h ghe.example'
  stub_gh 'api --hostname ghe.example user --jq .login' '' 1
  GH_TOKEN=token run hub::login ghe.example
  assert_status 1
  assert_output_equals "$message (run: gh auth login -h ghe.example)"
}

@test "login without gh says gh is needed, once" {
  PATH=$(no_gh_path) run hub::login ghe.example
  assert_status 1
  assert_output_equals 'hub test: this command needs the GitHub CLI, gh (https://cli.github.com)'
}

@test "protocol is gh's git_protocol for the host, https by default" {
  run hub::protocol
  assert_output_equals https
  stub_gh 'config get git_protocol -h ghe.example' ssh
  run hub::protocol ghe.example
  assert_output_equals ssh
  GH_HOST=ghe.example run hub::protocol
  assert_output_equals ssh
  stub_gh 'config get git_protocol -h other.example' '' 1
  run hub::protocol other.example
  assert_output_equals https
}

@test "protocol is https without gh, with no message" {
  stub_gh 'config get git_protocol -h ghe.example' ssh
  PATH=$(no_gh_path) run hub::protocol ghe.example
  assert_success
  assert_output_equals https
  assert_gh_not_called
}

@test "clone_url builds https and ssh URLs, with the ghe.com tenant as the ssh user" {
  run hub::clone_url github.com o r
  assert_output_equals https://github.com/o/r.git
  run hub::clone_url github.com o r ssh
  assert_output_equals git@github.com:o/r.git
  run hub::clone_url acme.ghe.com o r ssh
  assert_output_equals acme@acme.ghe.com:o/r.git
  run hub::clone_url acme.ghe.com o r https
  assert_output_equals https://acme.ghe.com/o/r.git
}

@test "clone_url takes hub::protocol when the protocol is omitted or empty" {
  stub_gh 'config get git_protocol -h ghe.example' ssh
  run hub::clone_url ghe.example o r
  assert_output_equals git@ghe.example:o/r.git
  run hub::clone_url ghe.example o r ''
  assert_output_equals git@ghe.example:o/r.git
  run hub::clone_url ghe.example o r https
  assert_output_equals https://ghe.example/o/r.git
  assert_equals "$(gh_calls)" "$(printf '%s\n' 'gh config get git_protocol -h ghe.example' \
    'gh config get git_protocol -h ghe.example')"
  PATH=$(no_gh_path) run hub::clone_url ghe.example o r
  assert_output_equals https://ghe.example/o/r.git
}

@test "is_owner accepts the names of GitHub users and organizations" {
  local str
  for str in mislav my-org 0x a; do
    hub::is_owner "$str"
  done
  for str in -x o_r o.r o/r '' 'a b'; do
    run hub::is_owner "$str"
    assert_failure
  done
}

@test "is_shorthand accepts OWNER/REPO and REPO only" {
  local str
  for str in mislav/hub dotfiles .github my-org/some.repo_name _repo r.wiki; do
    hub::is_shorthand "$str"
  done
  for str in https://github.com/o/r a/b/c . .. ./x ../x /abs 'a b' o/. o/.. '' -x/r o_r/x; do
    run hub::is_shorthand "$str"
    assert_failure
  done
}

@test "local_source sees paths, NAME.git repositories and work trees, and bundles" {
  mkdir dir plain.git
  git init -q --bare repo.git
  touch tool.bundle
  git init -q work.git
  hub::local_source dir
  hub::local_source repo
  hub::local_source work
  hub::local_source tool bundle
  local str
  for str in plain tool nothing; do
    run hub::local_source "$str"
    assert_failure
  done
}

@test "fetch_source names the remote that fetches the repository, else its URL" {
  make_repo r origin=https://github.com/O/R.git
  run hub::fetch_source github.com o r
  assert_output_equals origin
  run hub::fetch_source github.com x y
  assert_output_equals https://github.com/x/y.git
  stub_gh 'config get git_protocol -h github.com' ssh
  run hub::fetch_source github.com x y
  assert_output_equals git@github.com:x/y.git
}

@test "patch_url accepts the pull, commit and compare URLs GitHub serves as patches" {
  local url
  for url in https://github.com/o/r/pull/12 https://github.com/o/r/pull/12.patch \
    https://github.com/o/r/pull/12.diff 'https://github.com/o/r/pull/12/files?diff=split#top' \
    https://github.com/o/r/pull/12/ https://github.com/o/r/pull/12/commits \
    https://github.com/o/r/pull/12/commits/abc1234 https://github.com/o/r/commit/abc1234.patch \
    https://github.com/o/r/compare/a...b; do
    hub::patch_url "$url"
  done
  hub::patch_url https://github.com/o/r/pull/12/commits/abc1234.diff
  assert_equals "${HUB_URL[number]}:${HUB_URL[sha]}:${HUB_URL[format]}" 12:abc1234:diff
}

@test "patch_url refuses deeper pages, URLs without a number, sha or range, and other kinds" {
  local url
  for url in https://github.com/o/r/pull/12/files/abc1234 \
    https://github.com/o/r/pull/12/changes/abc1234 https://github.com/o/r/pull/12/files/a..b \
    https://github.com/o/r/pull/abc/commits/abc1234 https://github.com/o/r/pull/new/topic \
    https://github.com/o/r/compare https://github.com/o/r/compare/ \
    https://github.com/o/r/compare/feature 'https://github.com/o/r/compare/feature?expand=1' \
    https://github.com/o/r/issues/3 https://github.com/o/r/tree/main https://github.com/o/r \
    https://gitlab.com/o/r/commit/abc1234 https://github.com/o/r/commit/main not-a-url; do
    run hub::patch_url "$url"
    assert_failure
  done
}

@test "pull_url accepts a pull request's URL and its pages, and nothing else" {
  local url
  for url in https://github.com/o/r/pull/12 https://github.com/o/r/pull/12/files/abc1234 \
    https://github.com/o/r/pull/12/commits/abc1234 https://github.com/o/r/pull/12.patch; do
    hub::pull_url "$url"
  done
  assert_equals "${HUB_URL[owner]}/${HUB_URL[repo]}#${HUB_URL[number]}" o/r#12
  for url in https://github.com/o/r/pull/new/topic https://github.com/o/r/issues/12 \
    https://gitlab.com/o/r/pull/12 https://github.com/o/r/pull not-a-url; do
    run hub::pull_url "$url"
    assert_failure
  done
}

# downloads FORMAT ARGS... : hub::download_patches, then HUB_ARGS each in <>, a file as NAME:TEXT.
downloads() {
  local word
  hub::download_patches "$@" || return
  for word in "${HUB_ARGS[@]}"; do
    if [[ -f $word ]]; then
      printf '<%s:%s>' "${word#"$TMPDIR"/hub-test.??????/}" "$(<"$word")"
    else
      printf '<%s>' "$word"
    fi
  done
}

@test "download_patches puts each patch URL's download in its place, up to --, and cleans up" {
  stub_gh 'api --help' 'FLAGS'
  stub_gh 'api --hostname github.com repos/o/r/pulls/12 *' 'From pull'
  stub_gh 'api --hostname github.com repos/o/r/commits/abc1234 *' 'From commit'
  stub_gh 'api --hostname github.com repos/o/r/compare/a...b *' 'From compare'
  mkdir tmp
  local deeper=https://github.com/o/r/pull/12/files/abc1234
  TMPDIR=$HUB_TEST_TMP/tmp run downloads diff -3 https://github.com/o/r/pull/12 x "$deeper" \
    https://github.com/o/r/commit/abc1234 https://github.com/o/r/compare/a...b \
    https://github.com/o/r/issues/3 -- https://github.com/o/r/pull/12
  assert_success
  assert_output_equals "<-3><1.diff:From pull><x><$deeper><2.diff:From commit>\
<3.diff:From compare><https://github.com/o/r/issues/3><--><https://github.com/o/r/pull/12>"
  assert_gh_called 'api --hostname github.com repos/o/r/pulls/12 -H Accept: *.github.diff'
  assert_equals "$(gh_calls | grep -c 'issues\|files')" 0
  assert_equals "$(ls tmp)" ''
  TMPDIR=$HUB_TEST_TMP/tmp run downloads patch --end-of-options https://github.com/o/r/pull/12
  assert_output_equals '<--end-of-options><https://github.com/o/r/pull/12>'
  assert_equals "$(gh_calls | grep -c pulls/12)" 1
}

@test "download_patches stops with gh's status, naming the URL, and cleans up" {
  stub_gh 'api --help' 'FLAGS'
  stub_gh 'api --hostname github.com repos/o/r/commits/abc1234 *' 'gh: Not Found' 4
  mkdir tmp
  TMPDIR=$HUB_TEST_TMP/tmp run downloads patch https://github.com/o/r/commit/abc1234
  assert_status 4
  assert_output_equals 'hub test: could not download: https://github.com/o/r/commit/abc1234'
  assert_equals "$(ls tmp)" ''
}

@test "download_patches asks gh api --help once and adds the flag only when listed" {
  local url=https://github.com/o/r/commit/abc1234 accept='-H Accept: application/vnd.github'
  stub_gh 'api --help' 'FLAGS\n  --jq string'
  stub_gh 'api --hostname github.com repos/o/r/commits/abc1234 *' 'From commit'
  mkdir tmp
  TMPDIR=$HUB_TEST_TMP/tmp run downloads patch "$url" "$url.patch"
  assert_output_equals '<1.patch:From commit><2.patch:From commit>'
  assert_equals "$(grep -c 'api --help' "$HUB_TEST_GH_LOG")" 1
  assert_equals "$(gh_calls | grep -c "repos/o/r/commits/abc1234 $accept.patch\$")" 2
  : >"$HUB_TEST_GH_LOG"
  stub_gh 'api --help' 'FLAGS\n  --allow-escape-sequences   Keep them'
  TMPDIR=$HUB_TEST_TMP/tmp run downloads diff "$url"
  assert_gh_called "api --hostname github.com repos/o/r/commits/abc1234 $accept.diff\
 --allow-escape-sequences"
}

@test "scan finds the operands around separate, attached and long values" {
  HUB_COMMAND=clone
  hub::scan '-b -o --branch --depth' -b main --depth 1 o/r -q --origin=up -ofork dir
  assert_equals "${HUB_OPERANDS[*]}" '4 8'
  hub::scan '-b' -b x -- -b y
  assert_equals "${HUB_OPERANDS[*]}" '3 4'
  hub::scan '' - x --flag
  assert_equals "${HUB_OPERANDS[*]}" '0 1'
  hub::scan '--reference --reference-if-able' --reference x o/r
  assert_equals "${HUB_OPERANDS[*]}" 2
  hub::scan '-b' -qv o/r
  assert_equals "${HUB_OPERANDS[*]}" 1
}

@test "scan records the option words up to -- in HUB_OPTIONS" {
  HUB_COMMAND=clone
  hub::scan '-b -o' -q -b main o/r --origin=up -- -x dir
  assert_equals "${HUB_OPTIONS[*]}" '0 1 4 5'
  assert_equals "${HUB_OPERANDS[*]}" '3 6 7'
  hub::scan '-b' - x --end-of-options -q
  assert_equals "${HUB_OPTIONS[*]}" 2
}

@test "scan skips separate option values, whatever they look like" {
  HUB_COMMAND=clone
  hub::scan '-b -o --branch --depth' -b main --depth 1 o/r -q --origin=up -ofork -o -x dir
  assert_equals "${HUB_OPERANDS[*]}" '4 10'
  assert_equals "${HUB_OPTIONS[*]}" '0 2 5 6 7 8'
}

@test "scan hands -h anywhere among a cluster's flags to git, and not a value's h" {
  HUB_COMMAND=merge HUB_NOOP=1
  local word
  for word in -h -qh -hq -vqh; do
    run hub::scan '-m -b' "$word" x
    assert_output_equals "git merge $word x"
  done
  hub::scan '-m -b' -bh x -mhello -- -h
  assert_equals "${HUB_OPERANDS[*]}" '1 4'
}

@test "scan reads an -X= letter's attached value as the rest of the cluster" {
  HUB_COMMAND=merge HUB_NOOP=1
  hub::scan '-m -S=' -Sme nosuch -qSmx -qShx -S -m msg x
  assert_equals "${HUB_OPERANDS[*]}" '1 7'
  run hub::scan '-m -S=' -S=
  assert_output_equals ''
}

@test "takes_value follows git's reading of the next word" {
  local table='-o --origin -b --branch --depth -S=' word
  for word in -b --branch --depth --dep --or -qb -vqo; do
    hub::takes_value "$table" "$word"
  done
  for word in -bmain -qbmain -qob --depth=1 -- --end-of-options --quiet --branchx -q x - \
    -S -qS -Sb -qSb -S= '-o --origin' ''; do
    run hub::takes_value "$table" "$word"
    assert_failure
  done
}

@test "scan reads every word after --end-of-options as an operand, as git does" {
  HUB_COMMAND=clone
  hub::scan '-b -o --branch --depth' -q --end-of-options -b o/r -- dir
  assert_equals "${HUB_OPERANDS[*]}" '2 3 4 5'
}

@test "scan hands an unclear command line to git untouched" {
  HUB_COMMAND=clone HUB_NOOP=1
  run hub::scan '--depth' --dep 1 o/r
  assert_output_equals 'git clone --dep 1 o/r'
  run hub::scan '-b' -qb main o/r
  assert_output_equals 'git clone -qb main o/r'
  run hub::scan '--depth' o/r --depth
  assert_output_equals 'git clone o/r --depth'
  run hub::scan '-b' o/r -b
  assert_output_equals 'git clone o/r -b'
  run hub::scan '-b' -qbmain o/r
  assert_output_equals 'git clone -qbmain o/r'
  run hub::scan '-b' o/r --help
  assert_output_equals 'git clone o/r --help'
  run hub::scan '-b' --help-all o/r
  assert_output_equals 'git clone --help-all o/r'
  run hub::scan '-b' -- --help
  assert_output_equals ''
}

@test "drop_flag removes a flag letter wherever git reads it as a flag, and only there" {
  run args_of hub::drop_flag p '-o -b' -p -qp -pomine -po x -o -p -b p -p-x -- -p
  assert_output_equals '<-q><-omine><-o><x><-o><-p><-b><p><-p-x><--><-p>'
  run args_of hub::drop_flag p '-o' -q --push x -op
  assert_status 1
  assert_output_equals ''
  hub::drop_flag p '-o' -q --push x -op || true
  assert_equals "${HUB_ARGS[*]}" '-q --push x -op'
}

@test "the operand tables name options of git, and no flag of git is a proper prefix of one" {
  local -a tables=(
    'clone|-o --origin -b --branch -u --upload-pack --reference --reference-if-able
      --separate-git-dir --depth --shallow-since --shallow-exclude -j --jobs --template -c
      --config --filter --bundle-uri --server-option --ref-format --revision'
    'fetch|--depth --deepen --shallow-since --shallow-exclude --refmap -j --jobs -o
      --server-option --upload-pack --negotiation-tip --filter'
    'push|-o --push-option --repo --receive-pack --exec --recurse-submodules'
    'remote add|-t --track -m --master'
    'merge|-m --message -F --file -s --strategy -X --strategy-option --into-name --cleanup'
  )
  local spec cmd table entry word problems=''
  local -a longs
  make_repo r
  for spec in "${tables[@]}"; do
    cmd=${spec%%|*} table=" ${spec#*|} "
    table=${table//$'\n'/ }
    # shellcheck disable=SC2086  # "remote add" is two words
    run git $cmd -h
    longs=()
    while read -r word; do
      if [[ $word == '--[no-]'* ]]; then
        longs+=("--${word#'--[no-]'}" "--no-${word#'--[no-]'}")
      else
        longs+=("$word")
      fi
    done < <(grep -oE -- '--(\[no-\])?[a-z0-9][a-z0-9-]*' <<<"$output")
    for entry in $table; do
      if [[ $entry == --* && " ${longs[*]} " != *" $entry "* ]]; then
        problems+="git $cmd -h does not list $entry"$'\n'
      elif [[ $entry != --* && ! $output =~ [[:space:]]${entry}[,[:space:]] ]]; then
        problems+="git $cmd -h does not list $entry"$'\n'
      fi
      for word in "${longs[@]}"; do
        if [[ $table != *" $word "* && $entry == "$word"?* ]]; then
          problems+="git $cmd: the flag $word is a proper prefix of $entry"$'\n'
        fi
      done
    done
  done
  assert_equals "$problems" ''
}

@test "gh_subcommand maps show to view and inserts list where no subcommand is" {
  run args_of hub::gh_subcommand -s closed -L 5
  assert_output_equals '<list><-s><closed><-L><5>'
  run args_of hub::gh_subcommand
  assert_output_equals '<list>'
  run args_of hub::gh_subcommand -R o/r show 1
  assert_output_equals '<-R><o/r><view><1>'
  run args_of hub::gh_subcommand -Ro/r --repo=o/r --repo x/y show 1
  assert_output_equals '<-Ro/r><--repo=o/r><--repo><x/y><view><1>'
  run args_of hub::gh_subcommand -R o/r
  assert_output_equals '<-R><o/r><list>'
  run args_of hub::gh_subcommand -- show
  assert_output_equals '<list><--><show>'
  run args_of hub::gh_subcommand view -- show
  assert_output_equals '<view><--><show>'
  run args_of hub::gh_subcommand view --help
  assert_output_equals '<view><--help>'
  run args_of hub::gh_subcommand create --body $'one\n\ntwo words'
  assert_output_equals $'<create><--body><one\n\ntwo words>'
}

@test "gh_subcommand leaves a -R without its value for gh to refuse" {
  run args_of hub::gh_subcommand -R
  assert_output_equals '<-R>'
  run args_of hub::gh_subcommand --repo
  assert_output_equals '<--repo>'
  run args_of hub::gh_subcommand -R o/r --repo
  assert_output_equals '<-R><o/r><--repo>'
}

@test "gh_subcommand returns 1 for help before the subcommand" {
  run hub::gh_subcommand -h
  assert_status 1
  run hub::gh_subcommand -R o/r --help
  assert_status 1
}

@test "gh_subcommand returns 1 for help given as the value of -R or --repo" {
  local args
  for args in '-R --help' '--repo -h' '-R o/r --repo --help' '-R --help -R o/r'; do
    # shellcheck disable=SC2086  # the words of args are separate arguments
    run hub::gh_subcommand $args
    assert_status 1
  done
  run args_of hub::gh_subcommand -R-h view
  assert_output_equals '<-R-h><view>'
}

@test "gh_subcommand leaves -R --help before a subcommand for gh to refuse" {
  run args_of hub::gh_subcommand -R --help list
  assert_output_equals '<-R><--help><list>'
  run args_of hub::gh_subcommand --repo -h show 1
  assert_output_equals '<--repo><-h><view><1>'
}

@test "normalize_opts splits clusters and detaches values" {
  run args_of hub::normalize_opts bhm '--base --head --message' -uc -bmain --base=dev \
    --head topic -m 'two words' - -- -b x
  assert_output_equals '<-u><-c><-b><main><--base><dev><--head><topic><-m><two words><-><--><-b><x>'
  run args_of hub::normalize_opts m --message --message -pd -m -x -pfmmsg -pfm msg
  assert_output_equals '<--message><-pd><-m><-x><-p><-f><-m><msg><-p><-f><-m><msg>'
  run args_of hub::normalize_opts m '' -m
  assert_output_equals '<-m>'
  run args_of hub::normalize_opts '' '' --flag=v -u- --message=x
  assert_output_equals '<--flag=v><-u-><--message=x>'
  run args_of hub::normalize_opts b --base -s. -ub-x -bx- -u-b x
  assert_output_equals '<-s.><-u><-b><-x><-b><x-><-u-b><x>'
}

@test "url_escape keeps branch names readable and encodes the rest" {
  run hub::url_escape 'feature/x y#1%é~a:b@c-d_e.f'
  assert_output_equals 'feature/x%20y%231%25%C3%A9~a:b@c-d_e.f'
}

@test "show_url prints, copies or opens the URL as asked, with the tool's status" {
  run hub::show_url 1 0 https://github.com/o/r
  assert_success
  assert_output_equals https://github.com/o/r
  run ls browser.log clipboard
  assert_failure
  run hub::show_url 0 1 https://github.com/o/r/pulls
  assert_output_equals ''
  assert_equals "$(<clipboard)" https://github.com/o/r/pulls
  HUB_TEST_CLIPBOARD_STATUS=17 run hub::show_url 1 1 https://github.com/o/r/issues
  assert_status 17
  assert_output_equals https://github.com/o/r/issues
  assert_equals "$(<clipboard)" https://github.com/o/r/issues
  run ls browser.log
  assert_failure
  HUB_TEST_BROWSER_STATUS=19 run hub::show_url 0 0 https://github.com/o/r/wiki
  assert_status 19
  assert_output_equals ''
  assert_equals "$(<browser.log)" https://github.com/o/r/wiki
}

@test "open_url runs GH_BROWSER, else BROWSER, else open, and returns its status" {
  run hub::open_url https://github.com/o/r
  assert_success
  HUB_TEST_BROWSER_STATUS=19 run hub::open_url https://github.com/o/r/issues
  assert_status 19
  GH_BROWSER='' BROWSER="$HUB_TEST_ROOT/test/stubs/browser --new-window" \
    run hub::open_url https://github.com/o/r/pulls
  assert_success
  BROWSER=false run hub::open_url https://github.com/o/r/wiki
  assert_success
  unset GH_BROWSER
  run hub::open_url https://github.com/o/r/actions
  assert_success
  assert_equals "$(<browser.log)" 'https://github.com/o/r
https://github.com/o/r/issues
https://github.com/o/r/pulls
https://github.com/o/r/wiki
https://github.com/o/r/actions'
  PATH=$HUB_TEST_TMP/empty run hub::open_url https://github.com/o/r
  assert_status 1
  assert_output_contains 'no browser found'
}

@test "open_url falls back to xdg-open without open" {
  unset GH_BROWSER
  PATH=$(no_gh_path xdg-open) run hub::open_url https://github.com/o/r/releases
  assert_success
  assert_equals "$(<browser.log)" https://github.com/o/r/releases
}

@test "copy puts the text on the clipboard and returns the tool's status" {
  run hub::copy https://github.com/o/r
  assert_success
  assert_equals "$(<clipboard)" https://github.com/o/r
  HUB_TEST_CLIPBOARD_STATUS=17 run hub::copy other
  assert_status 17
  PATH=$HUB_TEST_TMP/empty run hub::copy text
  assert_status 1
  assert_output_contains 'no clipboard tool found'
}

@test "copy falls back to wl-copy, then to xclip with the clipboard selection" {
  PATH=$(no_gh_path cat wl-copy) run hub::copy one
  assert_success
  assert_equals "$(<clipboard)" one
  mkdir xbin
  printf '#!/usr/bin/env bash\nprintf "%%s|" "$@" >xclip.args\ncat >clipboard\n' >xbin/xclip
  chmod +x xbin/xclip
  PATH=$(no_gh_path cat):$HUB_TEST_TMP/xbin run hub::copy two
  assert_success
  assert_equals "$(<clipboard)" two
  assert_equals "$(<xclip.args)" '-selection|clipboard|'
}

@test "open_url and copy print under --noop" {
  HUB_NOOP=1
  run hub::open_url 'https://github.com/o/r?a=1&b=2'
  assert_output_equals 'open https://github.com/o/r\?a=1\&b=2'
  run hub::copy https://github.com/o/r
  assert_output_equals 'copy https://github.com/o/r'
  run ls browser.log clipboard
  assert_failure
}
