#!/usr/bin/env bats
load ../test_helper

# serve_github OWNER/REPO makes https://github.com/OWNER/REPO.git a local bare repository, so the
# forks hub adds remotes for are really fetched and the effects (remotes, refs, FETCH_HEAD) are checked.
@test "fetch USER adds a remote for USER's fork and fetches it" {
  serve_github mislav/dotfiles alice/dotfiles
  clone_served mislav/dotfiles
  run hub fetch alice
  assert_success
  assert_equals "$(remote_url alice)" https://github.com/alice/dotfiles.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
  run hub --noop fetch bob
  assert_output_equals $'git remote add bob https://github.com/bob/dotfiles.git\ngit fetch bob'
}

@test "fetch a comma-separated list of users adds their remotes and fetches them with --multiple" {
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  clone_served mislav/dotfiles
  run hub fetch alice,bob
  assert_success
  assert_equals "$(remote_url alice)" https://github.com/alice/dotfiles.git
  assert_equals "$(remote_url bob)" https://github.com/bob/dotfiles.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
  assert_equals "$(git rev-parse refs/remotes/bob/main)" "$(server_ref bob/dotfiles main)"
  run hub --noop fetch carol,dave --prune
  assert_success
  assert_output_equals "git remote add carol https://github.com/carol/dotfiles.git
git remote add dave https://github.com/dave/dotfiles.git
git fetch --multiple carol dave --prune"
}

@test "fetch --multiple USER USER2 adds the missing remotes, then fetches with the arguments as given" {
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  clone_served mislav/dotfiles
  run hub --noop fetch --multiple alice origin bob alice --prune --depth 1
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/dotfiles.git
git remote add bob https://github.com/bob/dotfiles.git
git fetch --multiple alice origin bob alice --prune --depth 1"
  run hub fetch --multiple alice origin bob --prune
  assert_success
  assert_equals "$(git remote | tr '\n' ' ')" "alice bob origin "
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
  assert_equals "$(git rev-parse refs/remotes/bob/main)" "$(server_ref bob/dotfiles main)"
  run hub --noop fetch -m carol
  assert_success
  assert_output_equals $'git remote add carol https://github.com/carol/dotfiles.git\ngit fetch -m carol'
}

@test "fetch --multiple finds the names before, between and after the options, and keeps their order" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  local added=$'git remote add alice https://github.com/alice/dotfiles.git\ngit remote add bob https://github.com/bob/dotfiles.git'
  run hub --noop fetch --multiple --prune alice bob
  assert_success
  assert_output_equals "$added"$'\ngit fetch --multiple --prune alice bob'
  run hub --noop fetch --multiple alice --prune bob
  assert_success
  assert_output_equals "$added"$'\ngit fetch --multiple alice --prune bob'
  run hub --noop fetch --multiple alice bob --prune
  assert_success
  assert_output_equals "$added"$'\ngit fetch --multiple alice bob --prune'
  run hub --noop fetch --multiple --prune -- alice bob
  assert_success
  assert_output_equals "$added"$'\ngit fetch --multiple --prune -- alice bob'
  run hub --noop fetch --multiple --prune
  assert_output_equals "git fetch --multiple --prune"
  run hub --noop fetch --multiple
  assert_output_equals "git fetch --multiple"
}

@test "fetch --multiple counts anywhere on the command line, in option clusters too" {
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  clone_served mislav/dotfiles
  local alice='git remote add alice https://github.com/alice/dotfiles.git' bob='git remote add bob https://github.com/bob/dotfiles.git'
  run hub --noop fetch --prune --multiple alice bob
  assert_success
  assert_output_equals "$alice"$'\n'"$bob"$'\ngit fetch --prune --multiple alice bob'
  run hub --noop fetch --depth 1 --multiple alice
  assert_success
  assert_output_equals "$alice"$'\ngit fetch --depth 1 --multiple alice'
  run hub --noop fetch -q --upload-pack ./pack -m --prune alice bob
  assert_success
  assert_output_equals "$alice"$'\n'"$bob"$'\ngit fetch -q --upload-pack ./pack -m --prune alice bob'
  run hub --noop fetch -pm alice bob
  assert_success
  assert_output_equals "$alice"$'\n'"$bob"$'\ngit fetch -pm alice bob'
  run hub --noop fetch -mj 4 alice
  assert_success
  assert_output_equals "$alice"$'\ngit fetch -mj 4 alice'
  # after the first name as well, as git reads it: every operand is a remote
  run hub --noop fetch alice --multiple bob
  assert_success
  assert_output_equals "$alice"$'\n'"$bob"$'\ngit fetch alice --multiple bob'
  run hub fetch alice --multiple bob
  assert_success
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
  assert_equals "$(git rev-parse refs/remotes/bob/main)" "$(server_ref bob/dotfiles main)"
}

@test "the last of --multiple and --no-multiple counts, as in git" {
  serve_github mislav/dotfiles
  git -C "$(server_dir mislav/dotfiles)" branch feature main
  clone_served mislav/dotfiles
  # single mode after all: origin is the remote and feature a refspec, not a user to add a remote for
  run hub fetch --multiple origin --no-multiple feature
  assert_success
  assert_equals "$(git remote)" origin
  [[ $(<.git/FETCH_HEAD) == "$(server_ref mislav/dotfiles feature)"*"branch 'feature'"* ]]
  run hub --noop fetch --multiple --no-multiple origin feature
  assert_success
  assert_output_equals "git fetch --multiple --no-multiple origin feature"
  run hub --noop fetch -pm --depth 1 --no-multiple alice main
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch -pm --depth 1 --no-multiple alice main'
  run hub --noop fetch --no-multiple --prune -m alice bob
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/dotfiles.git
git remote add bob https://github.com/bob/dotfiles.git
git fetch --no-multiple --prune -m alice bob"
  assert_gh_called 'config get git_protocol -h github.com'
}

@test "fetch --multiple after --, or as an option's value, is not the option" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch -- --multiple alice bob
  assert_success
  assert_output_equals "git fetch -- --multiple alice bob"
  run hub --noop fetch --prune -- --multiple alice
  assert_success
  assert_output_equals "git fetch --prune -- --multiple alice"
  assert_gh_not_called
  # the value of --depth is --multiple; alice is then the one repository
  run hub --noop fetch --depth --multiple alice
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch --depth --multiple alice'
  run hub --noop fetch -jm alice # -j's value is m
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch -jm alice'
}

@test "fetch adds the missing remotes even with git fetch's --dry-run" {
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  clone_served mislav/dotfiles
  run hub --noop fetch alice --dry-run
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch alice --dry-run'
  run hub fetch --dry-run --multiple alice bob
  assert_success
  assert_equals "$(remote_url alice)" https://github.com/alice/dotfiles.git
  assert_equals "$(remote_url bob)" https://github.com/bob/dotfiles.git
  run git rev-parse --verify -q refs/remotes/alice/main
  assert_failure
}

@test "fetch --multiple never takes an option's value for a name" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch --multiple alice --depth 1 bob
  assert_success
  assert_output_equals "git remote add alice https://github.com/alice/dotfiles.git
git remote add bob https://github.com/bob/dotfiles.git
git fetch --multiple alice --depth 1 bob"
  # carol would be a name, and get a remote, if hub did not know that the option before it takes a value.
  local opt
  for opt in --depth --deepen --shallow-since --shallow-exclude --negotiation-tip --refmap --upload-pack --server-option -o \
    -j --jobs --filter --submodule-prefix --recurse-submodules-default -pj; do
    run hub --noop fetch --multiple "$opt" carol alice
    assert_success
    assert_output_equals "git remote add alice https://github.com/alice/dotfiles.git
git fetch --multiple $opt carol alice"
  done
  # Attached values (--depth=1, -j4) and --recurse-submodules, whose optional value is only ever attached, take none.
  run hub --noop fetch --multiple --depth=1 carol -j4 alice --recurse-submodules bob --recurse-submodules-default=yes dave
  assert_success
  assert_output_equals "git remote add carol https://github.com/carol/dotfiles.git
git remote add alice https://github.com/alice/dotfiles.git
git remote add bob https://github.com/bob/dotfiles.git
git remote add dave https://github.com/dave/dotfiles.git
git fetch --multiple --depth=1 carol -j4 alice --recurse-submodules bob --recurse-submodules-default=yes dave"
}

@test "fetch --multiple leaves remotes and remote groups as they are, and URLs and paths to git" {
  serve_github mislav/dotfiles github/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/github/dotfiles.git
  git config remotes.everyone "origin upstream"
  run hub --noop fetch --multiple origin everyone upstream --prune
  assert_success
  assert_output_equals "git fetch --multiple origin everyone upstream --prune"
  run hub fetch --multiple everyone
  assert_success
  assert_equals "$(git rev-parse refs/remotes/upstream/main)" "$(server_ref github/dotfiles main)"
  run hub --noop fetch --multiple alice https://github.com/bob/dotfiles.git --prune
  assert_success
  assert_output_equals "git fetch --multiple alice https://github.com/bob/dotfiles.git --prune"
  run hub --noop fetch --multiple alice --prune ../other.git
  assert_output_equals "git fetch --multiple alice --prune ../other.git"
  run hub --noop fetch --multiple alice not.a.login
  assert_output_equals "git fetch --multiple alice not.a.login"
  run hub --noop fetch --multiple alice ''
  assert_output_equals "git fetch --multiple alice ''"
  assert_gh_not_called
}

@test "existing remotes in the list are not added again, and a list of existing remotes asks gh nothing" {
  serve_github mislav/dotfiles alice/dotfiles github/dotfiles
  clone_served mislav/dotfiles
  run hub fetch origin,alice
  assert_success
  assert_equals "$(git remote | tr '\n' ' ')" "alice origin "
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
  git remote add upstream https://github.com/github/dotfiles.git
  : >"$HUB_TEST_LOG"
  run hub fetch origin,upstream
  assert_success
  assert_equals "$(git rev-parse refs/remotes/upstream/main)" "$(server_ref github/dotfiles main)"
  assert_gh_not_called
}

@test "a name given twice gets one remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch alice,alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/dotfiles.git\ngit fetch --multiple alice alice'
}

@test "a list with an empty member, or one that is neither a remote nor a GitHub user, is refused before anything changes" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  local list
  for list in 'alice,' ',alice' 'alice,,bob' 'alice,--prune' 'alice,-' 'alice,not.a.login' 'alice,../other.git'; do
    run hub fetch "$list"
    assert_failure
    assert_output_contains "hub fetch: "
    assert_output_contains "'$list'"
  done
  assert_equals "$(git remote)" origin
  assert_gh_not_called
}

@test "arguments after the list stay in place" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop fetch alice,bob --prune --depth 1
  assert_success
  assert_line_equals 2 "git fetch --multiple alice bob --prune --depth 1"
  run hub --noop fetch alice main:refs/remotes/alice/main --no-tags
  assert_success
  assert_line_equals 1 "git fetch alice main:refs/remotes/alice/main --no-tags"
}

@test "remote groups are not mistaken for users" {
  serve_github mislav/dotfiles github/dotfiles alice/dotfiles
  clone_served mislav/dotfiles
  git remote add upstream https://github.com/github/dotfiles.git
  git config remotes.everyone "origin upstream" # git fetches a group of one member only with --multiple
  run hub fetch everyone
  assert_success
  assert_equals "$(git remote | tr '\n' ' ')" "origin upstream "
  assert_equals "$(git rev-parse refs/remotes/upstream/main)" "$(server_ref github/dotfiles main)"
  run hub fetch everyone,alice
  assert_success
  assert_equals "$(git remote | tr '\n' ' ')" "alice origin upstream "
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
}

@test "an existing remote is fetched as it is, whatever its name" {
  serve_github o/r
  make_repo work
  git remote add alpha,beta https://github.com/o/r.git
  run hub fetch alpha,beta
  assert_success
  assert_equals "$(git remote)" "alpha,beta"
  assert_equals "$(git rev-parse 'refs/remotes/alpha,beta/main')" "$(server_ref o/r main)"
  git remote add origin.backup https://github.com/o/r.git
  run hub --noop fetch origin.backup,alice
  assert_success
  assert_output_equals $'git remote add alice https://github.com/alice/r.git\ngit fetch --multiple origin.backup alice'
}

@test "options, URLs, paths and existing remotes pass through" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  touch alice
  run hub --noop fetch origin
  assert_output_equals "git fetch origin"
  run hub --noop fetch origin main --prune
  assert_output_equals "git fetch origin main --prune"
  run hub --noop fetch --all
  assert_output_equals "git fetch --all"
  run hub --noop fetch --all bob
  assert_output_equals "git fetch --all bob"
  run hub --noop fetch https://github.com/bob/dotfiles.git main
  assert_output_equals "git fetch https://github.com/bob/dotfiles.git main"
  run hub --noop fetch git@github.com:bob/dotfiles.git
  assert_output_equals "git fetch git@github.com:bob/dotfiles.git"
  run hub --noop fetch ../other.git
  assert_output_equals "git fetch ../other.git"
  run hub --noop fetch alice # an existing path
  assert_output_equals "git fetch alice"
  run hub --noop fetch alice.bob # not a GitHub login
  assert_output_equals "git fetch alice.bob"
  run hub --noop fetch
  assert_output_equals "git fetch"
  assert_gh_not_called
}

@test "a NAME.git repository in the work tree is git's source, not a user's fork" {
  serve_github repo/project # what the shorthand would fetch instead
  make_repo project origin=https://github.com/mislav/project.git
  git init -q -b main "$HUB_TEST_TMP/local" && git -C "$HUB_TEST_TMP/local" commit -q --allow-empty -m "local source"
  git clone -q --bare "$HUB_TEST_TMP/local" repo.git
  run hub fetch repo
  assert_success
  assert_equals "$(git remote)" origin
  assert_equals "$(git log -1 --format=%s FETCH_HEAD)" "local source"
  assert_gh_not_called
}

@test "a remote defined in the legacy .git/remotes or .git/branches files is fetched as git does" {
  serve_github o/r
  make_repo work
  mkdir -p .git/remotes .git/branches
  printf 'URL: https://github.com/o/r.git\nPull: refs/heads/main:refs/remotes/legacy/main\n' >.git/remotes/legacy
  printf 'https://github.com/o/r.git#main\n' >.git/branches/older
  run hub fetch legacy
  assert_success
  assert_equals "$(git rev-parse refs/remotes/legacy/main)" "$(server_ref o/r main)"
  run hub fetch older
  assert_success
  [[ $(<.git/FETCH_HEAD) == "$(server_ref o/r main)"* ]]
  run hub fetch --multiple legacy older
  assert_success
  [[ -z $(git remote) ]]
  assert_gh_not_called
}

@test "fetch uses SSH when hub.protocol is ssh, without asking gh" {
  serve_github mislav/dotfiles alice/dotfiles bob/dotfiles
  clone_served mislav/dotfiles
  git config --global hub.protocol ssh
  run hub fetch alice,bob
  assert_success
  assert_equals "$(remote_url alice)" git@github.com:alice/dotfiles.git
  assert_equals "$(remote_url bob)" git@github.com:bob/dotfiles.git
  assert_equals "$(git rev-parse refs/remotes/bob/main)" "$(server_ref bob/dotfiles main)"
  assert_gh_not_called
}

@test "the protocol is looked up once for several users" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'config get git_protocol -h github.com' 'ssh'
  run hub --noop fetch alice,bob
  assert_success
  assert_line_equals 1 "git remote add bob git@github.com:bob/dotfiles.git"
  [[ $(grep -c 'config get git_protocol' "$HUB_TEST_LOG") -eq 1 ]]
}

@test "the fork is on the current project's host, under the project's name" {
  git config --global hub.host ghe.example.com
  serve_github ghe.example.com/alice/tool
  make_repo work-copy origin=https://ghe.example.com/me/fork-name.git upstream=git@ghe.example.com:tools/tool.git
  stub_gh 'config get git_protocol -h ghe.example.com' 'https'
  run hub fetch alice
  assert_success
  assert_equals "$(remote_url alice)" https://ghe.example.com/alice/tool.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref ghe.example.com/alice/tool main)"
  assert_gh_called 'config get git_protocol -h ghe.example.com'
}

@test "without a GitHub remote, the work tree's directory name is the repository name, without a .git suffix" {
  serve_github alice/tool
  make_repo tool
  run hub fetch alice
  assert_success
  assert_equals "$(remote_url alice)" https://github.com/alice/tool.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/tool main)"
  cd "$HUB_TEST_TMP"
  git init -q --bare tool.git && cd tool.git
  run hub fetch alice
  assert_success
  assert_equals "$(remote_url alice)" https://github.com/alice/tool.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/tool main)"
}

@test "fetch --help prints the manual; -h is git's" {
  run hub fetch --help
  assert_success
  assert_line_equals 0 "Summary: Fetch from GitHub users' forks, adding remotes for them first."
  assert_output_contains "Usage: hub fetch [<git-fetch options>] USER[,USER...]"
  run hub fetch alice,bob --help
  assert_success
  assert_output_contains "Usage: hub fetch [<git-fetch options>] USER[,USER...]"
  run hub --noop fetch -h
  assert_output_equals "git fetch -h"
  assert_gh_not_called
}

@test "a fork that does not exist fails in git and its remote stays" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  run hub fetch nobody
  assert_failure
  assert_equals "$(remote_url nobody)" https://github.com/nobody/dotfiles.git
}
