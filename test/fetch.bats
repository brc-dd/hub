#!/usr/bin/env bats
# hub fetch: GitHub users' copies of the project added as remotes and fetched; the rest is git's.

load test_helper

# serve_branch [HOST/]OWNER/REPO BRANCH MSG : a new commit on the served repository's BRANCH.
serve_branch() {
  local dir commit
  dir=$(server_dir "$1")
  commit=$(git -C "$dir" commit-tree -p refs/heads/main -m "$3" 'refs/heads/main^{tree}') \
    && git -C "$dir" update-ref "refs/heads/$2" "$commit"
}

# The project mislav/dotfiles with alice's and bob's copies, each with a branch of its own.
setup() {
  hub_test_setup
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  serve_branch alice/dotfiles topic 'alice topic'
  serve_branch bob/dotfiles feature 'bob feature'
  stub_gh 'repo view github.com/alice/dotfiles --json name' '{"name":"dotfiles"}'
  stub_gh 'repo view github.com/bob/dotfiles --json name' '{"name":"dotfiles"}'
  stub_gh 'repo view github.com/carol/dotfiles --json name' \
    "GraphQL: Could not resolve to a Repository with the name 'carol/dotfiles'. (repository)" 1
  clone_served mislav/dotfiles
}

remotes() { git remote | tr '\n' ' '; }

@test "hub fetch USER adds the user's copy as a remote and fetches it" {
  run hub fetch alice
  assert_success
  assert_equals "$(git remote get-url alice)" https://github.com/alice/dotfiles.git
  assert_equals "$(git rev-parse refs/remotes/alice/topic)" "$(server_ref alice/dotfiles topic)"
  assert_gh_called 'repo view github.com/alice/dotfiles --json name'
}

@test "hub fetch USER REFSPEC keeps the refspec and the options in place" {
  run hub fetch --no-tags alice topic:refs/heads/alice-topic --quiet
  assert_success
  assert_equals "$(tip alice-topic)" "$(server_ref alice/dotfiles topic)"
  assert_equals "$(git config remote.alice.url)" https://github.com/alice/dotfiles.git
}

@test "hub fetch USER uses ssh when gh's git_protocol is ssh" {
  stub_gh 'config get git_protocol -h github.com' ssh
  run hub fetch alice
  assert_success
  assert_equals "$(git remote get-url alice)" git@github.com:alice/dotfiles.git
  assert_equals "$(git rev-parse refs/remotes/alice/topic)" "$(server_ref alice/dotfiles topic)"
}

@test "hub fetch USER,USER adds both and fetches them with --multiple" {
  run hub fetch --prune alice,bob --no-tags
  assert_success
  assert_equals "$(remotes)" 'alice bob origin '
  assert_equals "$(git remote get-url bob)" https://github.com/bob/dotfiles.git
  assert_equals "$(git rev-parse refs/remotes/alice/topic)" "$(server_ref alice/dotfiles topic)"
  assert_equals "$(git rev-parse refs/remotes/bob/feature)" "$(server_ref bob/dotfiles feature)"
}

@test "hub fetch puts --multiple first and the members where the list was" {
  run hub --noop fetch --prune -- alice,origin bob
  assert_success
  assert_line_equals 0 'git remote add alice https://github.com/alice/dotfiles.git'
  assert_line_equals 1 'git fetch --multiple --prune -- alice origin bob'
  assert_equals "$(remotes)" 'origin '
}

@test "hub fetch with options around a list fetches every member" {
  git remote add bob https://github.com/bob/dotfiles.git
  serve_branch mislav/dotfiles fresh 'fresh on origin'
  run hub fetch --prune -- alice,origin bob
  assert_success
  assert_equals "$(remotes)" 'alice bob origin '
  assert_equals "$(git rev-parse refs/remotes/alice/topic)" "$(server_ref alice/dotfiles topic)"
  assert_equals "$(git rev-parse refs/remotes/bob/feature)" "$(server_ref bob/dotfiles feature)"
  assert_equals "$(git rev-parse refs/remotes/origin/fresh)" "$(server_ref mislav/dotfiles fresh)"
}

@test "hub fetch leaves refspecs after a list to git, which refuses them" {
  run hub fetch alice,bob topic
  assert_status 128
  assert_output_contains 'no such remote or remote group: topic'
  assert_equals "$(remotes)" 'alice bob origin '
}

@test "hub fetch keeps members that are remotes or groups, and looks up only the others" {
  serve_branch mislav/dotfiles fresh 'fresh on origin'
  git config remotes.mine origin
  run hub fetch origin,alice,mine
  assert_success
  assert_equals "$(remotes)" 'alice origin '
  assert_equals "$(git rev-parse refs/remotes/origin/fresh)" "$(server_ref mislav/dotfiles fresh)"
  assert_equals "$(gh_calls | grep -c 'repo view')" 1
  assert_gh_called 'repo view github.com/alice/dotfiles --json name'
}

@test "hub fetch with a list of existing remotes asks gh nothing" {
  git remote add bob https://github.com/bob/dotfiles.git
  run hub fetch origin,bob
  assert_success
  assert_equals "$(git rev-parse refs/remotes/bob/feature)" "$(server_ref bob/dotfiles feature)"
  assert_gh_not_called
}

@test "hub fetch adds a user named twice once" {
  run hub fetch alice,alice
  assert_success
  assert_equals "$(remotes)" 'alice origin '
  assert_equals "$(git rev-parse refs/remotes/alice/topic)" "$(server_ref alice/dotfiles topic)"
}

@test "hub fetch refuses a user without a copy before adding any remote" {
  run hub fetch alice,carol
  assert_status 1
  assert_output_equals \
    'hub fetch: carol is not a remote, and github.com/carol/dotfiles does not exist'
  assert_equals "$(remotes)" 'origin '
  run hub fetch carol
  assert_status 1
  assert_equals "$(remotes)" 'origin '
}

@test "hub fetch relays gh's error when gh cannot answer, and adds nothing" {
  local denied='HTTP 401: Bad credentials (https://api.github.com/graphql)'
  stub_gh 'repo view github.com/alice/dotfiles --json name' \
    "$denied\\nTry authenticating with:  gh auth login" 1
  run hub fetch alice
  assert_status 1
  assert_line_equals 0 "$denied"
  assert_line_equals 1 'Try authenticating with:  gh auth login'
  assert_equals "${#lines[@]}" 2
  assert_equals "$(remotes)" 'origin '
}

@test "hub fetch without gh says gh is needed before adding any remote" {
  PATH=$(no_gh_path) run hub fetch alice
  assert_status 1
  assert_output_equals 'hub fetch: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_equals "$(remotes)" 'origin '
}

@test "hub fetch refuses a login that is a remote in another case" {
  run hub fetch alice
  assert_success
  run hub fetch Alice
  assert_status 1
  assert_output_equals 'hub fetch: Alice is not a remote, but alice is (use alice)'
  run hub fetch bob,ALICE
  assert_status 1
  assert_output_equals 'hub fetch: ALICE is not a remote, but alice is (use alice)'
  assert_equals "$(remotes)" 'alice origin '
  assert_equals "$(gh_calls | grep -c 'repo view')" 1
}

@test "hub fetch refuses a list with an empty name" {
  local list
  for list in alice,,bob 'alice,' ,alice; do
    run hub fetch "$list"
    assert_status 1
    assert_output_equals "hub fetch: empty name in the list: $list"
  done
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub fetch hands an existing remote, a group or a local repository to git" {
  git remote add alice https://github.com/bob/dotfiles.git
  run hub fetch alice
  assert_success
  assert_equals "$(git rev-parse refs/remotes/alice/feature)" "$(server_ref bob/dotfiles feature)"
  git config remotes.friends 'alice origin'
  serve_branch bob/dotfiles later 'bob later'
  run hub fetch friends
  assert_success
  assert_equals "$(git rev-parse refs/remotes/alice/later)" "$(server_ref bob/dotfiles later)"
  git init -q -b main ../bob
  git -C ../bob commit -q --allow-empty -m 'local bob'
  ln -s ../bob bob
  run hub fetch bob
  assert_success
  assert_equals "$(git rev-parse FETCH_HEAD)" "$(git -C ../bob rev-parse HEAD)"
  assert_equals "$(remotes)" 'alice origin '
  assert_gh_not_called
}

@test "hub fetch hands a list with a local repository as a member to git" {
  git init -q -b main ../carol
  ln -s ../carol carol
  run hub fetch carol,alice
  assert_failure
  assert_output_contains "'carol,alice' does not appear to be a git repository"
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub fetch from a subdirectory hands a local repository at the top to git" {
  git init -q -b main alice
  git -C alice commit -q --allow-empty -m 'local alice'
  mkdir sub
  cd sub
  run hub fetch alice
  assert_success
  assert_equals "$(git rev-parse FETCH_HEAD)" "$(git -C ../alice rev-parse HEAD)"
  run hub fetch bob,alice
  assert_failure
  assert_output_contains "'bob,alice' does not appear to be a git repository"
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub fetch refuses an option inside the list before any lookup" {
  git remote add -- -p https://github.com/bob/dotfiles.git
  git update-ref refs/remotes/origin/gone HEAD
  run hub fetch origin,-p
  assert_status 1
  assert_output_equals 'hub fetch: not a remote name: -p (write options outside the list)'
  run hub fetch alice,--prune
  assert_status 1
  assert_output_equals 'hub fetch: not a remote name: --prune (write options outside the list)'
  assert_equals "$(git rev-parse --verify --quiet refs/remotes/origin/gone)" "$(git rev-parse HEAD)"
  assert_equals "$(remotes)" '-p origin '
  assert_gh_not_called
}

@test "hub fetch hands a list with a line break to git" {
  run hub fetch $'alice\n,bob'
  assert_failure
  assert_output_contains 'does not appear to be a git repository'
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub fetch hands a remote named with a comma to git" {
  git remote add alice,bob https://github.com/bob/dotfiles.git
  run hub fetch alice,bob
  assert_success
  local ref=refs/remotes/alice,bob/feature
  assert_equals "$(git rev-parse "$ref")" "$(server_ref bob/dotfiles feature)"
  assert_equals "$(remotes)" 'alice,bob origin '
  assert_gh_not_called
}

@test "hub fetch hands URLs and names that are not logins to git" {
  run hub fetch https://github.com/alice/dotfiles.git topic
  assert_success
  assert_equals "$(git rev-parse FETCH_HEAD)" "$(server_ref alice/dotfiles topic)"
  run hub fetch not.a.login
  assert_failure
  assert_output_contains "'not.a.login' does not appear to be a git repository"
  run hub fetch alice,not.a.login
  assert_failure
  assert_output_contains "'alice,not.a.login' does not appear to be a git repository"
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub fetch with --multiple, --all, -m or -h is git's" {
  run hub fetch --multiple alice
  assert_failure
  assert_output_contains 'no such remote or remote group: alice'
  run hub fetch --mul alice,bob
  assert_failure
  run hub fetch -qm alice
  assert_failure
  assert_output_contains 'no such remote or remote group: alice'
  run hub fetch --no-multiple alice,bob
  assert_failure
  run hub fetch --all alice
  assert_failure
  assert_output_contains 'fetch --all does not take a repository argument'
  run hub fetch -h alice
  assert_git_help fetch
  assert_output_contains 'usage: git fetch'
  run hub fetch -qh alice
  assert_git_help fetch
  assert_output_contains 'usage: git fetch'
  run hub fetch --multiple=yes alice
  assert_status 129
  assert_output_contains "option \`multiple' takes no value"
  run hub fetch --all=1 alice
  assert_status 129
  assert_output_contains "option \`all' takes no value"
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub fetch without an operand is git's" {
  serve_branch mislav/dotfiles fresh 'fresh on origin'
  run hub fetch --all
  assert_success
  assert_equals "$(git rev-parse refs/remotes/origin/fresh)" "$(server_ref mislav/dotfiles fresh)"
  run hub fetch --prune
  assert_success
  assert_gh_not_called
}

@test "hub fetch never takes an option's value for the user" {
  run hub fetch --depth 5 -j 3 --negotiation-tip main alice
  assert_success
  assert_equals "$(remotes)" 'alice origin '
  assert_equals "$(gh_calls | grep -c 'repo view')" 1
  assert_equals "$(git rev-parse FETCH_HEAD)" "$(server_ref alice/dotfiles main)"
}

@test "hub fetch reads an option's value spelled like an option as a value" {
  run hub --noop fetch -o -m alice
  assert_success
  assert_line_equals 0 'git remote add alice https://github.com/alice/dotfiles.git'
  assert_line_equals 1 'git fetch -o -m alice'
}

@test "hub fetch hands the hidden submodule options to git, values and all" {
  run hub fetch --submodule-prefix bob alice
  assert_failure
  run hub fetch --sub bob alice
  assert_failure
  run hub fetch --recurse-submodules-default yes alice
  assert_failure
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
  run hub fetch --recurse-submodules=no alice
  assert_success
  assert_equals "$(remotes)" 'alice origin '
}

@test "hub fetch --dry-run still adds the remote, and fetches nothing" {
  run hub fetch --dry-run alice
  assert_success
  assert_equals "$(git remote get-url alice)" https://github.com/alice/dotfiles.git
  assert_equals "$(git for-each-ref refs/remotes/alice)" ''
}

@test "hub fetch hands unclear option lines to git before adding anything" {
  run hub fetch alice --depth
  assert_status 129
  assert_output_contains 'requires a value'
  run hub fetch --dep 1 alice
  assert_failure
  run hub fetch -qj 2 alice
  assert_failure
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub fetch --help is git's manual" {
  run hub --noop fetch alice --help
  assert_success
  assert_output_equals 'git fetch alice --help'
  assert_gh_not_called
}

@test "hub fetch --help-all is git's usage, before any remote is added" {
  run hub fetch --help-all alice
  assert_git_help fetch
  assert_equals "$(remotes)" 'origin '
  assert_gh_not_called
}

@test "hub help fetch prints hub's manual, ending with git's" {
  run hub help fetch
  assert_success
  local summary="Summary: Fetch from GitHub users' copies of the project, adding their remotes."
  assert_line_equals 0 "$summary"
  assert_equals "${lines[-1]}" "git's own manual: git fetch --help"
}

@test "hub fetch takes the host, its protocol and the repository name from the project" {
  # Two gh hosts: the default host is github.com, the project's is ghe.example.com.
  mkdir -p "$GH_CONFIG_DIR"
  printf 'github.com:\n    user: mislav\nghe.example.com:\n    user: mona\n' \
    >"$GH_CONFIG_DIR/hosts.yml"
  serve_github ghe.example.com/mislav/tool ghe.example.com/alice/tool
  stub_gh 'config get git_protocol -h ghe.example.com' ssh
  stub_gh 'repo view ghe.example.com/alice/tool --json name' '{"name":"tool"}'
  cd "$HUB_TEST_TMP"
  clone_served ghe.example.com/mislav/tool
  run hub fetch alice
  assert_success
  assert_equals "$(git remote get-url alice)" git@ghe.example.com:alice/tool.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" \
    "$(server_ref ghe.example.com/alice/tool main)"
}

@test "hub fetch takes the repository from GH_REPO, and refuses an invalid one" {
  serve_github alice/tool
  stub_gh 'repo view github.com/alice/tool --json name' '{"name":"tool"}'
  GH_REPO=mislav/tool run hub fetch alice
  assert_success
  assert_equals "$(git remote get-url alice)" https://github.com/alice/tool.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/tool main)"
  GH_REPO=a/b/c/d run hub fetch bob
  assert_status 1
  assert_output_equals \
    'hub fetch: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
  assert_equals "$(remotes)" 'alice origin '
}

@test "hub fetch without a GitHub remote names the repository after the directory" {
  serve_github alice/my-project
  stub_gh 'repo view github.com/alice/my-project --json name' '{"name":"my-project"}'
  cd "$HUB_TEST_TMP"
  make_repo 'my project'
  run hub fetch alice
  assert_success
  assert_equals "$(git remote get-url alice)" https://github.com/alice/my-project.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/my-project main)"
}

@test "hub fetch exits with git's status and keeps the remote it added" {
  run hub fetch alice no-such-branch
  assert_status 128
  assert_output_contains "couldn't find remote ref no-such-branch"
  assert_equals "$(git remote get-url alice)" https://github.com/alice/dotfiles.git
}

@test "hub fetch outside a repository is git's" {
  cd "$HUB_TEST_TMP"
  run hub fetch alice
  assert_failure
  assert_output_contains 'not a git repository'
  assert_gh_not_called
}

@test "hub --noop fetch prints the commands and changes nothing" {
  run hub --noop fetch alice
  assert_success
  assert_line_equals 0 'git remote add alice https://github.com/alice/dotfiles.git'
  assert_line_equals 1 'git fetch alice'
  assert_equals "${#lines[@]}" 2
  assert_equals "$(remotes)" 'origin '
}
