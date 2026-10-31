#!/usr/bin/env bats
load test_helper

setup() {
  hub_test_setup
  export HUB_ROOT=$HUB_TEST_ROOT
  # shellcheck source=../lib/hub/core.sh
  source "$HUB_TEST_ROOT/lib/hub/core.sh"
}

@test "parse_remote_url understands https, ssh, scp-like and git URLs, by scheme" {
  hub::parse_remote_url https://github.com/mislav/hub.git
  [[ $HUB_URL_SCHEME == https && $HUB_URL_HOST == github.com && $HUB_URL_OWNER == mislav && $HUB_URL_REPO == hub && -z $HUB_URL_USER ]]
  hub::parse_remote_url git@github.com:mislav/hub.git
  [[ $HUB_URL_SCHEME == ssh && $HUB_URL_USER == git && $HUB_URL_HOST == github.com && $HUB_URL_OWNER == mislav && $HUB_URL_REPO == hub ]]
  hub::parse_remote_url ssh://git@ssh.github.com:443/mislav/hub
  [[ $HUB_URL_SCHEME == ssh && $HUB_URL_HOST == ssh.github.com && $HUB_URL_PORT == 443 && $HUB_URL_REPO == hub ]]
  hub::parse_remote_url git://github.com/mislav/hub.git
  [[ $HUB_URL_SCHEME == git && $HUB_URL_OWNER == mislav ]]
  hub::parse_remote_url https://GHE.Example.com/org/repo/
  [[ $HUB_URL_HOST == ghe.example.com && $HUB_URL_OWNER == org && $HUB_URL_REPO == repo ]]
  hub::parse_remote_url https://github.com/o/r.git/
  [[ $HUB_URL_REPO == r ]]
  hub::parse_remote_url org-123@github.com:o/r.git
  [[ $HUB_URL_USER == org-123 ]]
  hub::parse_remote_url git+ssh://git@gh-alias/o/r
  [[ $HUB_URL_SCHEME == ssh && $HUB_URL_HOST == gh-alias ]]
  hub::parse_remote_url https://user:secret@enterprise.example:8443/o/r
  [[ $HUB_URL_USER == user && $HUB_URL_HOST == enterprise.example && $HUB_URL_PORT == 8443 ]]
  local bad
  for bad in /local/path/repo.git ../relative dir/x:y https://github.com/just-owner file://github.com/o/r.git \
    https://github.com/o/r/sub.git https://github.com:notaport/o/r not-a-url; do
    run hub::parse_remote_url "$bad"
    assert_failure
  done
}

@test "SSH remotes are resolved through the ssh git uses; HTTPS hosts are taken literally" {
  cat >ssh_config <<'EOF'
Host gh-443
  HostName ssh.github.com
  Port 443
Match originalhost scoped user git
  HostName enterprise.example
Host scoped
  HostName github.com
Host github.internal
  HostName github.com
Host remapped.example
  HostName enterprise.example
EOF
  export GIT_SSH_COMMAND="ssh -F $PWD/ssh_config"
  git config --global --add hub.host enterprise.example
  git config --global --add hub.host remapped.example
  make_repo r a=git@gh-443:o/r.git b=git@scoped:o/r.git c=scoped:o/r.git d=https://github.internal/o/r.git \
    e=git@unknown.example:o/r.git f=git@remapped.example:o/r.git g=https://remapped.example/o/r.git
  hub::remote_project a >/dev/null
  [[ $HUB_PROJECT_HOST == github.com && $HUB_PROJECT == o/r ]]
  hub::remote_project b >/dev/null
  [[ $HUB_PROJECT_HOST == enterprise.example ]] # the Match rule sees the URL's user
  hub::remote_project c >/dev/null
  [[ $HUB_PROJECT_HOST == github.com ]]
  run hub::remote_project d # ssh_config does not rewrite HTTPS
  assert_failure
  run hub::remote_project e
  assert_failure
  hub::remote_project f >/dev/null
  [[ $HUB_PROJECT_HOST == enterprise.example ]] # a known host is still resolved
  hub::remote_project g >/dev/null
  [[ $HUB_PROJECT_HOST == remapped.example ]]
  # a custom SSH program that is not OpenSSH is not asked; the alias then means nothing to hub
  GIT_SSH_COMMAND=plink run hub::remote_project a
  assert_failure
  GIT_SSH_COMMAND=plink run hub::remote_project c
  assert_failure
  # core.sshCommand counts too, below GIT_SSH_COMMAND; so does GIT_SSH
  unset GIT_SSH_COMMAND
  git config core.sshCommand "ssh -F $HUB_TEST_TMP/ssh_config"
  [[ $(hub::remote_project a) == o/r ]]
  git config --unset core.sshCommand
  run hub::remote_project a
  assert_failure
  printf '#!/usr/bin/env bash\nexec ssh -F %q "$@"\n' "$HUB_TEST_TMP/ssh_config" >ssh
  chmod +x ssh
  GIT_SSH=$PWD/ssh hub::remote_project a >/dev/null
  [[ $HUB_PROJECT_HOST == github.com ]]
}

@test "the push URL of a remote can be read separately" {
  make_repo r origin=https://github.com/me/r.git
  git remote set-url --push origin git@github.com:other/r.git
  [[ $(hub::remote_project origin) == me/r ]]
  [[ $(hub::remote_project origin push) == other/r ]]
}

@test "parse_project follows gh's rule for GH_REPO and -R" {
  hub::parse_project o/r
  [[ $HUB_PROJECT == o/r && $HUB_PROJECT_HOST == github.com ]]
  hub::parse_project ghe.example.com/org/repo
  [[ $HUB_PROJECT == org/repo && $HUB_PROJECT_HOST == ghe.example.com ]]
  hub::parse_project https://github.com/o/r.git/
  [[ $HUB_PROJECT == o/r && $HUB_PROJECT_HOST == github.com ]]
  hub::parse_project git@github.com:o/r.git
  [[ $HUB_PROJECT == o/r ]]
  GH_HOST=ghe.example.com hub::parse_project o/r
  [[ $HUB_PROJECT_HOST == ghe.example.com ]]
  local bad
  for bad in o/r/ /o/r o//r host/o/r/ o 'o/r x' o/r/x/y ''; do
    run hub::parse_project "$bad"
    assert_failure
  done
  make_repo r
  GH_REPO=o/r/ run hub::main_project
  assert_failure
  assert_output_contains "GH_REPO must be"
  [[ $(GH_REPO=cli/cli hub::main_project) == cli/cli ]]
  GH_REPO=ghe.example.com/org/repo hub::main_project >/dev/null
  [[ $HUB_PROJECT == org/repo && $HUB_PROJECT_HOST == ghe.example.com ]]
}

@test "parse_github_url classifies web URLs, raw patch and diff forms included" {
  hub::parse_github_url https://github.com/mislav/hub/pull/123
  [[ $HUB_URL_KIND == pull && $HUB_URL_NUMBER == 123 && $HUB_URL_OWNER == mislav && $HUB_URL_REPO == hub && -z $HUB_URL_SHA && -z $HUB_URL_FORMAT ]]
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
  hub::parse_github_url https://github.com/mislav/hub/pull/123.patch
  [[ $HUB_URL_KIND == pull && $HUB_URL_NUMBER == 123 && $HUB_URL_FORMAT == patch ]]
  hub::parse_github_url https://github.com/mislav/hub/pull/123.diff
  [[ $HUB_URL_NUMBER == 123 && $HUB_URL_FORMAT == diff ]]
  hub::parse_github_url https://github.com/mislav/hub/commit/deadbeef.patch
  [[ $HUB_URL_SHA == deadbeef && $HUB_URL_FORMAT == patch ]]
  hub::parse_github_url https://github.com/mislav/hub/pull/123/commits/abcdef0123.diff
  [[ $HUB_URL_SHA == abcdef0123 && $HUB_URL_FORMAT == diff ]]
  hub::parse_github_url https://github.com/mislav/hub/commit/ABCDEF01
  [[ $HUB_URL_SHA == ABCDEF01 ]]
  local bad
  for bad in https://gitlab.com/mislav/hub/pull/1 https://github.com/mislav/hub/pull/not-a-number \
    https://github.com/mislav/hub/pull/123/commits/main https://github.com/mislav/hub/commit/main \
    https://github.com/mislav/hub/commit/v1.0 https://github.com/mislav/hub/pull/123.txt not-a-url; do
    run hub::parse_github_url "$bad"
    assert_failure
  done
}

@test "enterprise hosts come from hub.host, GH_HOST and GITHUB_HOST" {
  run hub::is_known_host ghe.example.com
  assert_failure
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
  git remote remove upstream
  git remote remove github
  git remote remove origin
  [[ -z $(hub::main_remote) ]]
  git remote add fork https://github.com/someone/r.git
  [[ $(hub::main_remote) == fork ]]
}

@test "default_branch reads a remote HEAD that still points at a branch, then asks gh, and fails when neither knows" {
  make_repo r origin=https://github.com/me/r.git
  stub_gh 'repo view github.com/me/r --json defaultBranchRef *' 'trunk'
  [[ $(hub::default_branch) == trunk ]]
  [[ $(GH_HOST=enterprise.example hub::default_branch) == trunk ]]
  set_remote_head origin develop
  [[ $(hub::default_branch) == develop ]]
  [[ $(hub::default_branch origin) == develop ]]
  git branch origin/develop # a local branch of that name does not confuse the full-ref lookup
  [[ $(hub::default_branch) == develop ]]
  git update-ref -d refs/remotes/origin/develop # the remote HEAD dangles after a rename and prune
  [[ $(hub::default_branch) == trunk ]]
  stub_gh 'repo view github.com/me/r --json defaultBranchRef *' '' 1
  run hub::default_branch
  assert_failure
  assert_output_equals ""
  [[ $(hub::default_branch || echo main) == main ]] # what a command that only builds a URL does
  git remote remove origin
  run hub::default_branch
  assert_failure
  assert_output_equals ""
}

@test "current_branch is the full ref's name, even next to a tag of the same name" {
  make_repo r
  git checkout -q -b topic
  git tag topic
  [[ $(git symbolic-ref --short HEAD) == heads/topic ]]
  [[ $(hub::current_branch) == topic ]]
  git checkout -q --detach
  run hub::current_branch
  assert_failure
}

@test "push_target follows git's own push rules" {
  serve_github o/r
  clone_served o/r
  git checkout -q -b topic
  git commit -q --allow-empty -m t
  run hub::push_target topic # no upstream, push.default simple: git refuses
  assert_failure
  git push -q -u origin topic
  hub::push_target topic
  [[ $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == topic ]]
  # an upstream of another name: simple refuses, upstream uses it, current uses the branch's own name
  git config branch.topic.merge refs/heads/main
  run hub::push_target topic
  assert_failure
  git config push.default upstream
  hub::push_target topic
  [[ $HUB_PUSH_BRANCH == main ]]
  git config push.default current
  hub::push_target topic
  [[ $HUB_PUSH_BRANCH == topic ]]
  git config push.default nothing
  run hub::push_target topic
  assert_failure
  git config --unset push.default
  # remote.*.push decides, whatever the fetch mapping
  git config remote.origin.push refs/heads/topic:refs/heads/publish
  git config --unset branch.topic.remote
  git config --unset branch.topic.merge
  hub::push_target topic
  [[ $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == publish ]]
  git config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
  hub::push_target topic
  [[ $HUB_PUSH_BRANCH == publish ]]
  git config remote.origin.fetch '+refs/heads/*:refs/cache/origin/*'
  hub::push_target topic
  [[ $HUB_PUSH_BRANCH == publish ]]
  run git push --dry-run --porcelain origin
  assert_output_contains "refs/heads/topic:refs/heads/publish"
  # a triangular workflow: remote.pushDefault wins over the upstream remote
  git config --unset remote.origin.push
  git remote add fork https://github.com/me/r.git
  git config branch.topic.remote origin
  git config branch.topic.merge refs/heads/topic
  git config remote.pushDefault fork
  hub::push_target topic
  [[ $HUB_PUSH_REMOTE == fork && $HUB_PUSH_BRANCH == topic ]]
  git config remote.fork.push refs/heads/topic:refs/for/topic # not a branch
  run hub::push_target topic
  assert_failure
  git config remote.pushDefault nowhere
  run hub::push_target topic
  assert_failure
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
  [[ $(HUB_PROTOCOL=https hub::git_url mislav/hub) == https://github.com/mislav/hub.git ]]
  [[ $(HUB_PROTOCOL=git hub::git_url mislav/hub) == git@github.com:mislav/hub.git ]]
}

@test "GitHub Enterprise Cloud SSH URLs use the tenant as the user, with or without a port in the host" {
  [[ $(hub::git_url org/repo tenant.ghe.com ssh) == tenant@tenant.ghe.com:org/repo.git ]]
  [[ $(hub::git_url org/repo tenant.ghe.com:443 ssh) == ssh://tenant@tenant.ghe.com/org/repo.git ]]
  [[ $(hub::git_url org/repo ghe.example.com ssh) == git@ghe.example.com:org/repo.git ]]
  [[ $(hub::git_url org/repo tenant.ghe.com https) == https://tenant.ghe.com/org/repo.git ]]
  [[ $(hub::git_url org/repo tenant.ghe.com:443 https) == https://tenant.ghe.com:443/org/repo.git ]]
}

@test "shorthand is lexical; what git reads as local is a separate question" {
  hub::is_project_name mislav/hub
  hub::is_project_name dotfiles
  hub::is_project_name .github
  hub::is_project_name my_org/some.repo-name
  hub::is_project_name _repo
  local bad
  for bad in https://github.com/mislav/hub git@github.com:mislav/hub.git a/b/c . .. ./x ../x /abs 'a b' o/. o/.. ''; do
    run hub::is_project_name "$bad"
    assert_failure
  done
  make_repo r
  run hub::local_source nothing-here
  assert_failure
  mkdir existing-dir
  hub::local_source existing-dir
  git init -q --bare repo.git
  hub::local_source repo # git's own suffix rule
  mkdir plain.git
  run hub::local_source plain # not a repository
  assert_failure
  : >tool.bundle
  run hub::local_source tool
  assert_failure
  hub::local_source tool bundle
  [[ $(hub::expand_project dotfiles) == mislav/dotfiles ]]
  [[ $(hub::expand_project someone/dotfiles) == someone/dotfiles ]]
}

@test "remote_exists knows configured remotes and the legacy remote files" {
  make_repo r origin=https://github.com/me/r.git
  hub::remote_exists origin
  run hub::remote_exists nowhere
  assert_failure
  run hub::remote_exists https://github.com/me/r.git
  assert_failure
  mkdir -p .git/remotes
  printf 'URL: %s\nPull: refs/heads/main:refs/remotes/legacy/main\n' "$PWD" >.git/remotes/legacy
  hub::remote_exists legacy 2>/dev/null
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
  [[ $(GH_ENTERPRISE_TOKEN=x hub::current_user) == mislav ]]
  stub_gh 'config get user -h ghe.example.com' 'ghe-cached'
  stub_gh 'api --hostname ghe.example.com user -q .login' 'ghe-token'
  [[ $(GH_TOKEN=x hub::current_user ghe.example.com) == ghe-cached ]]
  [[ $(GH_ENTERPRISE_TOKEN=x hub::current_user ghe.example.com) == ghe-token ]]
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

@test "message reads -m paragraphs or a file, and fails when the read does" {
  hub::message '' 'Title here' 'Body para'
  [[ $HUB_MSG_TITLE == "Title here" && $HUB_MSG_BODY == "Body para" ]]
  printf 'From a file\n\nwith body\n' >msg.txt
  hub::message msg.txt
  [[ $HUB_MSG_TITLE == "From a file" && $HUB_MSG_BODY == "with body" ]]
  hub::message - <<<$'From stdin\n\nbody'
  [[ $HUB_MSG_TITLE == "From stdin" && $HUB_MSG_BODY == body ]]
  run hub::message msg.txt 'also -m'
  assert_failure
  run hub::message missing.txt
  assert_failure
  run hub::message - <.
  assert_failure
  mkdir fakecat
  printf '#!/usr/bin/env bash\nprintf "Partial title\\n"\nexit 7\n' >fakecat/cat
  chmod +x fakecat/cat
  PATH=$PWD/fakecat:$PATH run hub::message - <<<"full"
  assert_failure
}

@test "quote only quotes what the shell would mangle, a literal tilde included" {
  [[ $(hub::quote git push origin feature/x) == "git push origin feature/x" ]]
  [[ $(hub::quote git commit -m 'two words') == "git commit -m two\\ words" ]]
  [[ $(hub::quote git add '~' 'x=~' '' '*') == "git add \\~ x=\\~ '' \\*" ]]
}

@test "url_escape keeps paths; url_segment encodes one path segment" {
  [[ $(hub::url_escape 'feat#1 x/y') == 'feat%231%20x/y' ]]
  [[ $(hub::url_segment 'feature#123') == feature%23123 ]]
  [[ $(hub::url_segment 'feature%2Fother') == feature%252Fother ]]
  [[ $(hub::url_segment 'a/b c') == a%2Fb%20c ]]
  [[ $(hub::url_segment 'plain-1.2_x~') == 'plain-1.2_x~' ]]
}

@test "normalize_opts splits clusters and attached values and keeps -- operands" {
  hub::normalize_opts bhm '--base --head' -pf -bmain --base=dev --head topic -m 'two words' - -- -b x
  [[ $(printf '%s|' "${HUB_ARGS[@]}") == '-p|-f|-b|main|--base|dev|--head|topic|-m|two words|-|--|-b|x|' ]]
  hub::normalize_opts m '' -m
  [[ $(printf '%s|' "${HUB_ARGS[@]}") == '-m|' ]]
  hub::normalize_opts '' '--flag' --other=1 --flag=2
  [[ $(printf '%s|' "${HUB_ARGS[@]}") == '--other=1|--flag|2|' ]]
  hub::normalize_opts m '' -pm msg
  [[ $(printf '%s|' "${HUB_ARGS[@]}") == '-p|-m|msg|' ]]
  hub::normalize_opts '' ''
  [[ ${#HUB_ARGS[@]} -eq 0 ]]
}

@test "noop prints instead of running, with the user's global options, while queries still run" {
  make_repo r
  HUB_NOOP=1
  [[ $(hub::git tag v1) == "git tag v1" ]]
  HUB_GIT_GLOBALS=(-C r -c 'a.b=x y')
  [[ $(hub::git tag v1) == "git -C r -c a.b=x\\ y tag v1" ]]
  HUB_GIT_GLOBALS=()
  [[ -z $(git tag) ]]
  [[ $(hub::current_branch) == main ]]
  HUB_NOOP=0
  hub::git tag v1 >/dev/null
  [[ $(git tag) == v1 ]]
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

@test "open_url prefers GH_BROWSER over BROWSER and returns the browser's status" {
  [[ $(GH_BROWSER='echo gh-browser' BROWSER='echo browser' hub::open_url https://example.test) == "gh-browser https://example.test" ]]
  [[ $(BROWSER='echo browser' hub::open_url https://example.test) == "browser https://example.test" ]]
  printf '#!/usr/bin/env bash\nexit 19\n' >browser
  chmod +x browser
  BROWSER=$PWD/browser run hub::open_url https://example.test
  [[ $status -eq 19 ]]
}

@test "copy returns the clipboard tool's status" {
  mkdir bin
  printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 17\n' >bin/pbcopy
  chmod +x bin/pbcopy
  PATH=$PWD/bin:$PATH run hub::copy text
  [[ $status -eq 17 ]]
}

@test "host follows gh's default: the only logged-in host, else github.com" {
  [[ $(hub::host) == github.com ]]
  mkdir -p "$GH_CONFIG_DIR"
  printf 'ghe.example.com:\n    user: me\n    git_protocol: ssh\n' >"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_GH_HOSTS
  [[ $(hub::host) == ghe.example.com ]]
  [[ $(hub::git_url org/repo) == https://ghe.example.com/org/repo.git ]]
  printf 'github.com:\n    user: me\n' >>"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_GH_HOSTS
  [[ $(hub::host) == github.com ]]
  [[ $(GH_HOST=other.example.com hub::host) == other.example.com ]]
}

@test "hosts gh is logged in to count as GitHub hosts, however hosts.yml quotes them" {
  make_repo r origin=https://enterprise.example/org/canonical.git
  run hub::remote_project origin
  assert_failure
  mkdir -p "$GH_CONFIG_DIR"
  printf "'enterprise.example':\n    user: me\n\"second.example\": # comment\n    user: me\nthird.example:\n    user: me\n" >"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_GH_HOSTS
  [[ $(hub::remote_project origin) == org/canonical ]]
  [[ $(hub::main_project) == org/canonical ]]
  [[ $(hub::known_hosts | sort | tr '\n' ' ') == "enterprise.example github.com second.example third.example " ]]
  printf "'enterprise.example':\n    user: me\n" >"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_GH_HOSTS
  [[ $(hub::host) == enterprise.example ]]
}

@test "hosts with a port are recognized and get sensible URLs" {
  make_repo r origin=https://enterprise.example:8443/org/repo.git
  GH_HOST=enterprise.example:8443
  hub::is_known_host enterprise.example
  hub::is_known_host enterprise.example:8443
  [[ $(hub::remote_project origin) == org/repo ]]
  [[ $(hub::git_url org/repo) == https://enterprise.example:8443/org/repo.git ]]
  [[ $(HUB_PROTOCOL=ssh hub::git_url org/repo) == ssh://git@enterprise.example/org/repo.git ]]
  unset GH_HOST
}

@test "project_or_dir names the project, else the directory without a .git suffix" {
  make_repo r origin=https://github.com/me/r.git
  [[ $(hub::project_or_dir) == "github.com r" ]]
  cd ..
  git init -q --bare tool.git
  cd tool.git
  [[ $(hub::project_or_dir) == "github.com tool" ]]
  cd ..
  mkdir 'my project'
  cd 'my project'
  git init -q
  [[ $(hub::project_or_dir) == "github.com my-project" ]]
}

@test "shared helpers: same_host, project variables, remote_for_project" {
  hub::same_host A.example:8443 a.example
  run hub::same_host a.example b.example
  assert_failure
  make_repo r origin=https://github.com/alice/r.git upstream=git@github.com:ORG/r.git
  hub::main_project >/dev/null
  [[ $HUB_PROJECT == ORG/r && $HUB_PROJECT_HOST == github.com ]]
  hub::remote_project origin >/dev/null
  [[ $HUB_PROJECT == alice/r ]]
  [[ $(hub::remote_for_project org/R GitHub.com) == upstream ]]
  run hub::remote_for_project nobody/r github.com
  assert_failure
  [[ $(hub::toplevel) == "$(pwd -P)" ]]
}

@test "gh_subcommand_args finds the subcommand word as gh does and maps show and the missing word" {
  local shown
  hub::gh_subcommand_args -s closed -L 5
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[list][-s][closed][-L][5]'
  hub::gh_subcommand_args -R o/r show 1 --comments
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[-R][o/r][view][1][--comments]'
  hub::gh_subcommand_args -Ro/r --repo=o/r '' - show 1 # complete options and non-words are skipped, not read
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[-Ro/r][--repo=o/r][][-][view][1]'
  hub::gh_subcommand_args -- show # nothing after -- is a word
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[list][--][show]'
  hub::gh_subcommand_args view -- show
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[view][--][show]'
  hub::gh_subcommand_args -s # a dangling value-taking option is gh's to reject
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[list][-s]'
  hub::gh_subcommand_args
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[list]'
  hub::gh_subcommand_args view --help # help after the word is gh's
  assert_equals "$(printf '[%s]' "${HUB_ARGS[@]}")" '[view][--help]'
  shown=0
  hub::gh_subcommand_args -R o/r --help || shown=1 # help before the word is hub's manual
  [[ $shown -eq 1 ]]
  hub::gh_subcommand_args -h || shown=2
  [[ $shown -eq 2 ]]
}

@test "valid_remote_name accepts remote names and refuses option-like, empty or malformed ones" {
  hub::valid_remote_name alice
  hub::valid_remote_name my.fork-2
  run ! hub::valid_remote_name -x
  run ! hub::valid_remote_name --push
  run ! hub::valid_remote_name ''
  run ! hub::valid_remote_name 'a b'
  run ! hub::valid_remote_name 'a..b'
}

@test "git_option reads a command's options as the installed git does" {
  make_repo r
  hub::git_option clone bcjou '' --depth
  [[ ${HUB_OPTS[*]} == --depth && $HUB_OPT_NEXT == 1 ]]
  hub::git_option clone bcjou '' --depth=1
  [[ ${HUB_OPTS[*]} == --depth && $HUB_OPT_NEXT == 0 ]]
  hub::git_option clone bcjou '' --dep # an abbreviation, as git resolves it
  [[ ${HUB_OPTS[*]} == --depth && $HUB_OPT_NEXT == 1 ]]
  hub::git_option clone bcjou '' --no-checkout
  [[ ${HUB_OPTS[*]} == --no-checkout && $HUB_OPT_NEXT == 0 ]]
  hub::git_option clone bcjou '' --recurse # --recurse-submodules takes only an attached value
  [[ ${HUB_OPTS[*]} == --recurse-submodules && $HUB_OPT_NEXT == 0 ]]
  run hub::git_option clone bcjou '' --re # ambiguous
  assert_failure
  run hub::git_option clone bcjou '' --nonsense
  assert_failure
  hub::git_option 'remote add' tm '' --tra
  [[ ${HUB_OPTS[*]} == --track && $HUB_OPT_NEXT == 1 ]]
  # a cluster of short options stops at the first that takes a value, attached or next
  hub::git_option fetch jo '' -pj3
  [[ ${HUB_OPTS[*]} == "-p -j" && $HUB_OPT_NEXT == 0 ]]
  hub::git_option fetch jo '' -qj
  [[ ${HUB_OPTS[*]} == "-q -j" && $HUB_OPT_NEXT == 1 ]]
  hub::git_option fetch jo '' -nq
  [[ ${HUB_OPTS[*]} == "-n -q" && $HUB_OPT_NEXT == 0 ]]
  # an optional value is read only attached, and takes the rest of the cluster
  hub::git_option am pC S -3S
  [[ ${HUB_OPTS[*]} == "-3 -S" && $HUB_OPT_NEXT == 0 ]]
  hub::git_option am pC S -Skeyp
  [[ ${HUB_OPTS[*]} == -S && $HUB_OPT_NEXT == 0 ]]
  hub::git_option am pC S -3p
  [[ ${HUB_OPTS[*]} == "-3 -p" && $HUB_OPT_NEXT == 1 ]]
  # cherry-pick and revert take no abbreviation: git keeps an unknown option for its revision parser
  hub::git_option cherry-pick mX S --strategy-option
  [[ ${HUB_OPTS[*]} == --strategy-option && $HUB_OPT_NEXT == 1 ]]
  run hub::git_option cherry-pick mX S --strat
  assert_failure
  # short options come from the usage git prints for -h: an unknown switch is git's to refuse
  run hub::git_option fetch jo '' -z
  assert_failure
  run hub::git_option fetch jo '' -pz
  assert_failure
  hub::git_option fetch jo '' -pq
  [[ ${HUB_OPTS[*]} == "-p -q" && $HUB_OPT_NEXT == 0 ]]
  hub::git_option fetch jo '' -4
  [[ ${HUB_OPTS[*]} == -4 && $HUB_OPT_NEXT == 0 ]]
  hub::git_option am pC S -3
  [[ ${HUB_OPTS[*]} == -3 && $HUB_OPT_NEXT == 0 ]]
  run hub::git_option cherry-pick mX S -h
  assert_failure
  local c shorts valued
  hub::git_short_options remote add >/dev/null
  [[ $HUB_GIT_USAGE_FOR == "remote add" ]] # the usage is read once per command
  shorts=$(hub::git_short_options remote add)
  for c in f t m; do [[ $shorts == *"$c"* ]]; done
  hub::git_short_options fetch >/dev/null
  [[ $HUB_GIT_USAGE_FOR == fetch ]]
  shorts=$(hub::git_short_options fetch)
  [[ $shorts != *z* ]]
  for c in j o p q 4 6; do [[ $shorts == *"$c"* ]]; done
  # the usage also says which long options take a value, optional (--log[=<n>]) or read by the
  # option itself (--file <file>), which the completion table lists as switches
  valued=$'\n'$(hub::git_valued_options merge)$'\n'
  [[ $valued == *$'\nlog\n'* && $valued == *$'\nfile\n'* && $valued == *$'\nstrategy\n'* && $valued != *$'\nsquash\n'* && $valued != *$'\nno-\n'* ]]
  valued=$'\n'$(hub::git_valued_options checkout)$'\n'
  [[ $valued == *$'\nrecurse-submodules\n'* && $valued == *$'\ntrack\n'* && $valued != *$'\ndetach\n'* ]]
  # the table of a command is read once, through git_option too, and another command's replaces it
  hub::git_option fetch jo '' -q
  [[ $HUB_GIT_USAGE_FOR == fetch && $HUB_GIT_SHORTS == *q* ]]
  hub::git_option fetch jo '' --jobs
  [[ $HUB_GIT_OPTIONS_FOR == fetch ]]
  hub::git_options clone >/dev/null
  [[ $HUB_GIT_OPTIONS_FOR == clone && $'\n'$HUB_GIT_OPTIONS$'\n' == *$'\n--depth=\n'* ]]
  HUB_GIT_OPTIONS=cached
  [[ $(hub::git_options clone) == cached ]]
  hub::git_options fetch >/dev/null
  [[ $HUB_GIT_OPTIONS_FOR == fetch && $'\n'$HUB_GIT_OPTIONS$'\n' == *$'\n--jobs=\n'* ]]
}

@test "git_option has no table outside a repository for a command that needs one" {
  run hub::git_option checkout bBU '' --detach
  assert_failure
  hub::git_option clone bcjou '' --depth # clone needs none
  [[ ${HUB_OPTS[*]} == --depth && $HUB_OPT_NEXT == 1 ]]
  hub::git_option fetch jo '' -q # fetch prints its usage anywhere
  [[ ${HUB_OPTS[*]} == -q ]]
  run hub::git_option 'remote add' tm '' -f # a subcommand prints none outside a repository
  assert_failure
}

@test "git_option takes an attached value only where git does: never on a switch" {
  make_repo r
  hub::git_option checkout bBU '' --recurse-submodules=no # an optional value, which only comes attached
  [[ ${HUB_OPTS[*]} == --recurse-submodules && $HUB_OPT_NEXT == 0 ]]
  hub::git_option checkout bBU '' --recurse=yes # abbreviated too
  [[ ${HUB_OPTS[*]} == --recurse-submodules && $HUB_OPT_NEXT == 0 ]]
  hub::git_option merge sXmF S --log=5
  [[ ${HUB_OPTS[*]} == --log && $HUB_OPT_NEXT == 0 ]]
  hub::git_option merge sXmF S --file=msg.txt # a value the option reads by itself, attached
  [[ ${HUB_OPTS[*]} == --file && $HUB_OPT_NEXT == 0 ]]
  hub::git_option fetch jo '' --jobs=3 # a required value, attached
  [[ ${HUB_OPTS[*]} == --jobs && $HUB_OPT_NEXT == 0 ]]
  hub::git_option fetch jo '' --recurse-submodules=on-demand
  [[ ${HUB_OPTS[*]} == --recurse-submodules && $HUB_OPT_NEXT == 0 ]]
  # a switch refuses a value ("option `detach' takes no value"), and so does hub, for git to say so
  run hub::git_option checkout bBU '' --detach=1
  assert_failure
  run hub::git_option checkout bBU '' --det=1
  assert_failure
  run hub::git_option fetch jo '' --multiple=oops
  assert_failure
  run hub::git_option merge sXmF S --squash=1
  assert_failure
  # a negation never takes one, optional value or not
  run hub::git_option checkout bBU '' --no-recurse-submodules=no
  assert_failure
  run hub::git_option merge sXmF S --no-log=1
  assert_failure
  # outside a repository the usage of a subcommand is missing, so the value cannot be judged: git's
  cd ..
  run hub::git_option 'remote add' tm '' --fetch=1
  assert_failure
}

# push_why BRANCH [verify] : why hub::push_target would not push BRANCH (empty when git would push it).
@test "push_target reads the upstream as git push does, mapped to a remote-tracking ref or not" {
  make_repo r origin=https://github.com/o/r.git
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  git branch -q --set-upstream-to=origin/feature
  git config --unset-all remote.origin.fetch
  git config --add remote.origin.fetch '+refs/heads/release:refs/remotes/origin/main' # feature's upstream has no remote-tracking ref now
  [[ -z $(git for-each-ref --format='%(upstream)' refs/heads/feature) ]]
  hub::push_target feature # push.default simple: the names match, as git push checks
  [[ $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == feature ]]
  git config push.default upstream
  hub::push_target feature
  [[ $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == feature ]]
  git config branch.feature.merge refs/heads/main # an upstream of another name: upstream pushes to it, simple refuses
  hub::push_target feature
  [[ $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == main ]]
  git config push.default simple
  if hub::push_target feature; then false; fi
  [[ $HUB_PUSH_WHY == upstream ]]
  # an upstream is branch.*.remote and branch.*.merge together, as for git push
  git config branch.feature.merge refs/heads/feature
  git config --unset branch.feature.remote
  if hub::push_target feature; then false; fi
  [[ $HUB_PUSH_WHY == upstream && $HUB_PUSH_REMOTE == origin ]]
  git config branch.feature.remote origin
  hub::push_target feature
  [[ $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == feature ]]
}

@test "tracking_ref maps a branch through the remote's fetch refspecs, as git fetch does" {
  make_repo r origin=https://github.com/o/r.git
  [[ $(hub::tracking_ref origin feature) == refs/remotes/origin/feature ]]
  [[ $(hub::tracking_ref origin topic/sub) == refs/remotes/origin/topic/sub ]]
  # another namespace, a renamed branch, and the first matching refspec
  git config --unset-all remote.origin.fetch
  git config --add remote.origin.fetch '+refs/heads/release:refs/remotes/origin/next'
  git config --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/mirror/*'
  git config --add remote.origin.fetch '+refs/heads/release:refs/remotes/origin/again'
  [[ $(hub::tracking_ref origin release) == refs/remotes/origin/next ]]
  [[ $(hub::tracking_ref origin feature) == refs/remotes/origin/mirror/feature ]]
  [[ $(hub::tracking_ref origin next) == refs/remotes/origin/mirror/next ]] # the remote's next, not release
  # a refspec with a * in the middle of a name, and a * standing for nothing
  git config --unset-all remote.origin.fetch
  git config --add remote.origin.fetch '+refs/heads/qa-*-done:refs/remotes/origin/done/*'
  [[ $(hub::tracking_ref origin qa-1-done) == refs/remotes/origin/done/1 ]]
  [[ $(hub::tracking_ref origin qa--done) == refs/remotes/origin/done/ ]]
  run hub::tracking_ref origin qa-1
  assert_failure
  # a negative refspec keeps a branch from being fetched, wherever it stands and whatever maps it
  git config --unset-all remote.origin.fetch
  git config --add remote.origin.fetch '^refs/heads/wip-*'
  git config --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git config --add remote.origin.fetch '^refs/heads/secret'
  [[ $(hub::tracking_ref origin feature) == refs/remotes/origin/feature ]]
  run hub::tracking_ref origin wip-1
  assert_failure
  run hub::tracking_ref origin secret
  assert_failure
  # a source without refs/heads/, which git resolves at fetch time, maps nothing here (as for %(upstream));
  # nor does a refspec without a destination, or a remote without fetch refspecs
  git config --unset-all remote.origin.fetch
  git config --add remote.origin.fetch '+main:refs/remotes/origin/main'
  git config --add remote.origin.fetch 'refs/heads/feature'
  run hub::tracking_ref origin main
  assert_failure
  run hub::tracking_ref origin feature
  assert_failure
  git config --unset-all remote.origin.fetch
  run hub::tracking_ref origin main
  assert_failure
  run hub::tracking_ref nosuch main
  assert_failure
}

push_why() {
  hub::push_target "$@" || true
  printf '%s\n' "$HUB_PUSH_WHY"
}

@test "push_target under push.default matching pushes only a branch the remote has" {
  serve_github o/r o/fork
  clone_served o/r
  git config push.default matching
  git checkout -q -b topic
  git commit -q --allow-empty -m t
  [[ $(push_why topic) == matching ]]        # the remote-tracking ref shows no branch of that name there
  [[ $(push_why topic verify) == matching ]] # nor does the remote itself
  hub::push_target topic verify || [[ $HUB_PUSH_WHY == matching && $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == topic ]]
  git push -q origin topic
  [[ -z $(push_why topic) && -z $(push_why topic verify) ]]
  hub::push_target topic verify
  [[ $HUB_PUSH_REMOTE == origin && $HUB_PUSH_BRANCH == topic ]]
  # deleted on the remote since the last fetch: the remote-tracking ref still says yes, the remote says no
  git -C "$(server_dir o/r)" update-ref -d refs/heads/topic
  [[ -z $(push_why topic) && $(push_why topic verify) == matching ]]
  # the push URL is what git pushes to: it is asked, whatever the fetch URL has
  git remote set-url --push origin https://github.com/o/fork.git
  git -C "$(server_dir o/r)" update-ref refs/heads/topic HEAD
  git fetch -q origin
  [[ -z $(push_why topic) && $(push_why topic verify) == matching ]]
  git -C "$(server_dir o/fork)" fetch -q "$(server_dir o/r)" refs/heads/topic:refs/heads/topic
  [[ -z $(push_why topic verify) ]]
  # every push URL must have it
  git remote set-url --add --push origin https://github.com/o/r.git
  [[ -z $(push_why topic verify) ]]
  git -C "$(server_dir o/r)" update-ref -d refs/heads/topic
  [[ $(push_why topic verify) == matching ]]
  # a remote-tracking ref is needed only under matching; current and upstream push as before
  git config push.default current
  [[ -z $(push_why topic verify) ]]
  # a destination that cannot be asked is an error, not a guess
  git config --unset-all remote.origin.pushurl
  git remote set-url --push origin https://github.com/o/none.git
  git config push.default matching
  run hub::push_target topic verify
  assert_failure
  assert_output_contains "Aborted: could not list the branches of https://github.com/o/none.git, to tell whether git push would push topic (push.default matching):"
}

@test "push_target says why git would not push a branch" {
  serve_github o/r
  clone_served o/r
  git checkout -q -b topic
  git commit -q --allow-empty -m t
  [[ $(push_why topic) == upstream ]] # no upstream yet, under push.default simple
  git config push.default nothing
  [[ $(push_why topic) == nothing ]]
  git config push.default simple
  git push -q -u origin topic
  [[ -z $(push_why topic) ]]
  git config branch.topic.merge refs/heads/main # an upstream of another name
  [[ $(push_why topic) == upstream ]]
  git config branch.topic.remote nowhere
  [[ $(push_why topic) == remote ]]
  git config branch.topic.remote origin
  git config branch.topic.merge refs/heads/topic
  # remote.*.push refspecs that map other branches: git push would push those and leave topic alone
  git config remote.origin.push refs/heads/main:refs/heads/main
  [[ $(push_why topic) == refspec ]]
  run git push --dry-run --porcelain origin
  assert_success
  assert_output_lacks refs/heads/topic
  git config --add remote.origin.push refs/heads/topic:refs/heads/topic
  [[ -z $(push_why topic) ]]
  git config --replace-all remote.origin.push refs/heads/topic:refs/tags/topic # not to a branch
  [[ $(push_why topic) == destination ]]
}

@test "hosts.yml in flow style names its hosts too" {
  mkdir -p "$GH_CONFIG_DIR"
  printf "{'enterprise.example': {user: cached, oauth_token: dummy, git_protocol: https}}\n" >"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_GH_HOSTS
  [[ $(hub::gh_hosts) == enterprise.example ]]
  [[ $(hub::host) == enterprise.example ]]
  [[ $(hub::git_url o/r) == https://enterprise.example/o/r.git ]]
  # several hosts, quoted or bare, over several lines with a comment; values and nested keys never count
  printf '# gh hosts\n{ "second.example": {user: me, oauth_token: "gho:xyz", git_protocol: ssh},\n  third.example : { user: me, users: { me: { oauth_token: x } } } }\n' >"$GH_CONFIG_DIR/hosts.yml"
  unset HUB_GH_HOSTS
  [[ $(hub::gh_hosts | sort | tr '\n' ' ') == "second.example third.example " ]]
  [[ $(hub::host) == github.com ]]
}

@test "gh_line adds the cd that -C would need, and only then" {
  mkdir inner
  HUB_INVOKED_PWD=$PWD
  [[ $(hub::gh_line gh pr list) == "gh pr list" ]]
  cd inner
  [[ $(hub::gh_line gh pr list) == "(cd $(hub::quote "$PWD") && gh pr list)" ]]
  [[ $(hub::gh_line env GH_HOST=ghe.example.com gh pr checkout URL) == "(cd $(hub::quote "$PWD") && env GH_HOST=ghe.example.com gh pr checkout URL)" ]]
  HUB_INVOKED_PWD=$PWD
  [[ $(hub::gh_line gh pr list) == "gh pr list" ]]
  unset HUB_INVOKED_PWD
  [[ $(hub::gh_line gh pr list) == "gh pr list" ]]
}

@test "gh_line prints what git's global options put in the environment, a --config-env value by its variable" {
  make_repo r
  HUB_INVOKED_PWD=$PWD
  local line expected
  # -c and --config-env: GIT_CONFIG_PARAMETERS, quoted as git quotes it
  HUB_GIT_GLOBALS=(-c user.name=Mislav -c 'alias.st=status -sb' -c core.quotepath -c "x.y=it's" --config-env=http.extraheader=HUB_TEST_AUTH)
  line=$(hub::gh_line gh pr list)
  [[ $line == "env GIT_CONFIG_PARAMETERS=\"'user.name'='Mislav' 'alias.st'='status -sb' 'core.quotepath'= 'x.y'='it'\\\\''s' 'http.extraheader'=\$(git rev-parse --sq-quote \"\$HUB_TEST_AUTH\" | cut -c2-)\" gh pr list" ]]
  [[ $line != *secret* ]]
  # run, the line gives gh exactly what git gave it, whatever the variable holds (git quotes ' and !)
  mkdir bin
  printf '#!/bin/sh\nprintf "%%s" "$GIT_CONFIG_PARAMETERS"\n' >bin/gh
  chmod +x bin/gh
  expected=$(HUB_TEST_AUTH="Authorization: it's secret!" git -c user.name=Mislav -c 'alias.st=status -sb' -c core.quotepath -c "x.y=it's" --config-env=http.extraheader=HUB_TEST_AUTH -c 'alias.hubtest=!printf "%s" "$GIT_CONFIG_PARAMETERS"' hubtest)
  expected=${expected% \'alias.hubtest\'=*}
  [[ $expected == *"'Authorization: it'\\''s secret'\\!''"* ]]
  [[ $(PATH=$PWD/bin:$PATH HUB_TEST_AUTH="Authorization: it's secret!" bash -c "$line") == "$expected" ]]
  [[ $(PATH=$PWD/bin:$PATH HUB_TEST_AUTH="Authorization: it's secret!" sh -c "$line") == "$expected" ]]
  # the other options, as gh has them in the environment; merged with the caller's env words and the cd
  HUB_GIT_GLOBALS=(--git-dir .git --work-tree . --no-optional-locks --literal-pathspecs --no-replace-objects -C .)
  [[ $(GIT_DIR=.git GIT_WORK_TREE=. GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 GIT_NO_REPLACE_OBJECTS=1 hub::gh_line env GH_HOST=ghe.example.com gh pr list) == "env GIT_DIR=.git GIT_WORK_TREE=. GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 GIT_NO_REPLACE_OBJECTS=1 GH_HOST=ghe.example.com gh pr list" ]]
  HUB_GIT_GLOBALS=(--bare -c a.b=c)
  [[ $(GIT_DIR=$PWD GIT_IMPLICIT_WORK_TREE=0 hub::gh_line gh pr list) == "env GIT_DIR=$(hub::quote "$PWD") GIT_IMPLICIT_WORK_TREE=0 GIT_CONFIG_PARAMETERS=\"'a.b'='c'\" gh pr list" ]]
  HUB_GIT_GLOBALS=(-c a.b=c -c a.b=d) # repeated: one variable, both entries, in order
  [[ $(hub::gh_line gh pr list) == "env GIT_CONFIG_PARAMETERS=\"'a.b'='c' 'a.b'='d'\" gh pr list" ]]
  # what gh inherited before the command line (hub's own GIT_CONFIG_PARAMETERS has it in front of
  # the command line's entries) comes along by reference, unprinted; the entries alone do not
  GIT_CONFIG_PARAMETERS="'a.b'='inherited' 'a.b'='c' 'a.b'='d'"
  [[ $(hub::gh_line gh pr list) == "env GIT_CONFIG_PARAMETERS=\"\${GIT_CONFIG_PARAMETERS:+\$GIT_CONFIG_PARAMETERS }'a.b'='c' 'a.b'='d'\" gh pr list" ]]
  GIT_CONFIG_PARAMETERS="'a.b'='c' 'a.b'='d'"
  [[ $(hub::gh_line gh pr list) == "env GIT_CONFIG_PARAMETERS=\"'a.b'='c' 'a.b'='d'\" gh pr list" ]]
  unset GIT_CONFIG_PARAMETERS
  # a variable the shell cannot expand (git reads any name) is read with printenv
  HUB_GIT_GLOBALS=(--config-env=a.b=CONFIG.VAR)
  [[ $(hub::gh_line gh pr list) == "env GIT_CONFIG_PARAMETERS=\"'a.b'=\$(git rev-parse --sq-quote \"\$(printenv CONFIG.VAR)\" | cut -c2-)\" gh pr list" ]]
  cd ..
  HUB_GIT_GLOBALS=(-C r --no-advice)
  [[ $(GIT_ADVICE=0 hub::gh_line gh pr list) == "(cd $(hub::quote "$PWD") && env GIT_ADVICE=0 gh pr list)" ]]
  HUB_GIT_GLOBALS=(-C r -p --no-pager) # options that export nothing gh reads print nothing
  [[ $(hub::gh_line gh pr list) == "(cd $(hub::quote "$PWD") && gh pr list)" ]]
  HUB_GIT_GLOBALS=()
}
