#!/usr/bin/env bats
load ../test_helper

SHA=a319d88b3f4b58a1b8d4a5ef2d1b8e5a6f7c8d9e

# served_commit OWNER/REPO NAME [REF] : from a scratch clone, push a commit adding NAME.txt to the served
# repository's REF (default main, force-pushed), and print its id.
served_commit() {
  local spec=$1 name=$2 ref=${3:-refs/heads/main} dir
  dir=$(mktemp -d "$HUB_TEST_TMP/seed.XXXXXX")
  git clone -q "https://github.com/$spec.git" "$dir"
  echo "$name" >"$dir/$name.txt"
  git -C "$dir" add -A
  git -C "$dir" -c user.name="Jingwen Owen Ou" -c user.email=jingweno@example.test commit -q -m "$name"
  git -C "$dir" push -q -f origin "HEAD:$ref"
  git -C "$dir" rev-parse HEAD
}

@test "cherry-pick of a commit URL fetches that commit from its repository, then cherry-picks it" {
  serve_github mislav/dotfiles jingweno/dotfiles
  local sha
  sha=$(served_commit jingweno/dotfiles fix-build)
  clone_served mislav/dotfiles
  run hub --noop cherry-pick "https://github.com/jingweno/dotfiles/commit/$sha"
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $sha
git cherry-pick $sha"
  run hub cherry-pick "https://github.com/jingweno/dotfiles/commit/$sha"
  assert_success
  [[ $(git log -1 --format='%an|%s') == "Jingwen Owen Ou|fix-build" && -f fix-build.txt ]]
  [[ $(git rev-list --count HEAD) == 2 && $(git symbolic-ref --short HEAD) == main ]]
  [[ $(gh_calls) != *api* ]]
}

@test "a short SHA in a commit URL is looked up with gh, since the fetch needs the full id" {
  serve_github mislav/dotfiles jingweno/dotfiles
  local sha
  sha=$(served_commit jingweno/dotfiles fix-build)
  clone_served mislav/dotfiles
  stub_gh "api --hostname github.com repos/jingweno/dotfiles/commits/${sha:0:7} --jq .sha" "$sha"
  run hub cherry-pick "https://github.com/jingweno/dotfiles/commit/${sha:0:7}"
  assert_success
  [[ $(git log -1 --format=%s) == fix-build && -f fix-build.txt ]]
  assert_gh_called "api --hostname github.com repos/jingweno/dotfiles/commits/${sha:0:7} --jq .sha"
}

@test "cherry-pick fetches through a remote that points at the commit's repository" {
  serve_github mislav/dotfiles jingweno/dotfiles
  local sha
  sha=$(served_commit jingweno/dotfiles fix-build)
  clone_served mislav/dotfiles
  git remote add jingweno git@github.com:jingweno/dotfiles.git
  run hub --noop cherry-pick "https://github.com/JingWeno/dotfiles/commit/$sha"
  assert_success
  assert_line_equals 0 "git fetch --no-tags jingweno $sha"
  run hub cherry-pick "https://github.com/jingweno/dotfiles/commit/$sha"
  assert_success
  [[ $(git log -1 --format=%s) == fix-build ]]
  assert_gh_not_called
}

@test "cherry-pick of a pull request's commit fetches the pull request's head and picks the commit from it" {
  serve_github mislav/dotfiles
  local sha
  sha=$(served_commit mislav/dotfiles fix-build refs/pull/12/head)
  clone_served mislav/dotfiles
  run hub --noop cherry-pick -x https://github.com/mislav/dotfiles/pull/12/commits/a319d88
  assert_success
  assert_output_equals "git fetch --no-tags origin refs/pull/12/head
git cherry-pick -x a319d88"
  run hub cherry-pick "https://github.com/mislav/dotfiles/pull/12/commits/${sha:0:7}"
  assert_success
  [[ $(git log -1 --format=%s) == fix-build && -f fix-build.txt ]]
  [[ $(git rev-parse FETCH_HEAD) == "$sha" ]]
  assert_gh_not_called
}

@test "a pull request's commit is found by its id in the pull request's history, never by a local name with the same prefix" {
  serve_github mislav/dotfiles
  local sha
  sha=$(served_commit mislav/dotfiles intended refs/pull/12/head)
  clone_served mislav/dotfiles
  git checkout -q -b "${sha:0:7}"
  echo other >decoy.txt && git add decoy.txt && git commit -q -m decoy
  git checkout -q main
  run hub cherry-pick "https://github.com/mislav/dotfiles/pull/12/commits/${sha:0:7}"
  assert_success
  [[ $(git log -1 --format=%s) == intended && -f intended.txt && ! -e decoy.txt ]]
  git reset -q --hard origin/main
  run hub cherry-pick "https://github.com/mislav/dotfiles/pull/12/commits/$sha"
  assert_success
  [[ $(git log -1 --format=%s) == intended && ! -e decoy.txt ]]
  assert_gh_not_called
}

@test "a pull request's commit that its head no longer contains is fetched by its full id" {
  serve_github mislav/dotfiles
  git -C "$(server_dir mislav/dotfiles)" config uploadpack.allowAnySHA1InWant true # as GitHub serves retained commits
  local old
  old=$(served_commit mislav/dotfiles old-work refs/pull/12/head)
  served_commit mislav/dotfiles new-work refs/pull/12/head >/dev/null
  clone_served mislav/dotfiles
  run git cat-file -e "$old"
  assert_failure
  run hub cherry-pick "https://github.com/mislav/dotfiles/pull/12/commits/$old"
  assert_success
  [[ $(git log -1 --format=%s) == old-work && -f old-work.txt ]]
  assert_gh_not_called
  # a short id of such a commit is expanded through gh
  cd "$HUB_TEST_TMP" && clone_served mislav/dotfiles work2
  stub_gh "api --hostname github.com repos/mislav/dotfiles/commits/${old:0:7} --jq .sha" "$old"
  run hub cherry-pick "https://github.com/mislav/dotfiles/pull/12/commits/${old:0:7}"
  assert_success
  [[ $(git log -1 --format=%s) == old-work ]]
  # and when gh does not know it either
  stub_gh 'api --hostname github.com repos/mislav/dotfiles/commits/deadbee --jq .sha' '' 1
  run hub cherry-pick https://github.com/mislav/dotfiles/pull/12/commits/deadbee
  assert_failure
  assert_output_contains "Aborted: could not find commit https://github.com/mislav/dotfiles/pull/12/commits/deadbee"
  [[ $(git log -1 --format=%s) == old-work ]]
}

@test "cherry-pick USER@SHA fetches from USER's fork of the current project" {
  serve_github mislav/dotfiles jingweno/dotfiles
  local sha
  sha=$(served_commit jingweno/dotfiles fix-build)
  clone_served mislav/dotfiles
  run hub --noop cherry-pick "jingweno@$sha"
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $sha
git cherry-pick $sha"
  stub_gh "api --hostname github.com repos/jingweno/dotfiles/commits/${sha:0:7} --jq .sha" "$sha"
  run hub cherry-pick "jingweno@${sha:0:7}"
  assert_success
  [[ $(git log -1 --format=%s) == fix-build && -f fix-build.txt ]]
}

@test "cherry-pick USER@SHA uses a remote for that fork when there is one" {
  serve_github mislav/dotfiles jingweno/dotfiles
  local sha
  sha=$(served_commit jingweno/dotfiles fix-build)
  clone_served mislav/dotfiles
  git remote add jingweno https://github.com/jingweno/dotfiles.git
  run hub --noop cherry-pick "jingweno@$sha"
  assert_success
  assert_output_equals "git fetch --no-tags jingweno $sha
git cherry-pick $sha"
  run hub cherry-pick "jingweno@$sha"
  assert_success
  [[ $(git log -1 --format=%s) == fix-build ]]
  assert_gh_not_called
}

@test "a USER@SHA that names a local branch or tag is git's" {
  make_repo dotfiles # no GitHub remote: the shorthand could not even be resolved
  git checkout -q -b topic
  echo yes >identifiable.txt && git add identifiable.txt && git commit -q -m "topic work"
  git branch alice@deadbee
  git tag bob@cafe123
  git checkout -q main
  run hub cherry-pick --allow-empty alice@deadbee
  assert_success
  [[ $(git log -1 --format=%s) == "topic work" && -f identifiable.txt ]]
  git reset -q --hard HEAD~1
  run hub cherry-pick bob@cafe123
  assert_success
  [[ $(git log -1 --format=%s) == "topic work" ]]
  assert_gh_not_called
  run hub cherry-pick carol@deadbee
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
}

@test "cherry-pick keeps the options given around the commit, and picks several operands" {
  serve_github mislav/dotfiles jingweno/dotfiles
  local one two
  one=$(served_commit jingweno/dotfiles first)
  two=$(served_commit jingweno/dotfiles second refs/heads/other) # a tip too: only tips can be fetched by id without server configuration
  clone_served mislav/dotfiles
  run hub --noop cherry-pick -x -m 1 https://github.com/mislav/dotfiles/pull/12/commits/a319d88 --allow-empty
  assert_success
  assert_line_equals 1 "git cherry-pick -x -m 1 a319d88 --allow-empty"
  run hub cherry-pick -x "https://github.com/jingweno/dotfiles/commit/$one" "jingweno@$two"
  assert_success
  [[ $(git rev-list --count HEAD) == 3 && -f first.txt && -f second.txt ]]
  [[ $(git log -1 --format=%b) == *"(cherry picked from commit $two)"* ]]
}

@test "the value of an option is never taken for a commit, and nothing after -- is" {
  make_repo dotfiles
  run hub --noop cherry-pick -X alice@deadbee
  assert_success
  assert_output_equals "git cherry-pick -X alice@deadbee"
  run hub --noop cherry-pick --strategy-option alice@deadbee -m alice@deadbee
  assert_output_equals "git cherry-pick --strategy-option alice@deadbee -m alice@deadbee"
  run hub --noop cherry-pick -- "https://github.com/mislav/dotfiles/commit/$SHA"
  assert_output_equals "git cherry-pick -- https://github.com/mislav/dotfiles/commit/$SHA"
  run hub --noop cherry-pick -x -- alice@deadbee
  assert_output_equals "git cherry-pick -x -- alice@deadbee"
  assert_gh_not_called
}

@test "cherry-pick always tells gh the commit's host" {
  git config --global hub.host ghe.example.com
  make_repo app origin=git@ghe.example.com:team/app.git
  # Only the call with the host has an answer: any other one fails, and so would hub.
  stub_gh 'api --hostname ghe.example.com repos/team/app/commits/a319d88 --jq .sha' "$SHA"
  run hub --noop cherry-pick https://ghe.example.com/team/app/commit/a319d88
  assert_success
  assert_output_equals "git fetch --no-tags origin $SHA
git cherry-pick $SHA"
  export GH_HOST=ghe.example.com
  run hub --noop cherry-pick https://ghe.example.com/team/app/commit/a319d88
  assert_success
  assert_line_equals 0 "git fetch --no-tags origin $SHA"
  stub_gh 'api --hostname ghe.example.com repos/alice/app/commits/a319d88 --jq .sha' "$SHA"
  stub_gh 'config get git_protocol -h ghe.example.com' 'https'
  run hub --noop cherry-pick alice@a319d88
  assert_success
  assert_line_equals 0 "git fetch --no-tags https://ghe.example.com/alice/app.git $SHA"
}

@test "cherry-pick looks up a github.com commit on github.com, whatever host gh defaults to" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  export GH_HOST=enterprise.example
  stub_gh 'api --hostname github.com repos/jingweno/dotfiles/commits/a319d88 --jq .sha' "$SHA"
  run hub --noop cherry-pick https://github.com/jingweno/dotfiles/commit/a319d88
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA
git cherry-pick $SHA"
  run hub --noop cherry-pick jingweno@a319d88
  assert_success
  assert_output_equals "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA
git cherry-pick $SHA"
  unset GH_HOST
  mkdir -p "$GH_CONFIG_DIR"
  printf 'enterprise.example:\n    user: me\n' >"$GH_CONFIG_DIR/hosts.yml"
  run hub --noop cherry-pick https://github.com/jingweno/dotfiles/commit/a319d88
  assert_success
  assert_line_equals 0 "git fetch --no-tags https://github.com/jingweno/dotfiles.git $SHA"
}

@test "cherry-pick without a commit URL or USER@SHA is plain git cherry-pick" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop cherry-pick a319d88
  assert_success
  assert_output_equals "git cherry-pick a319d88"
  run hub --noop cherry-pick -x main~2 topic
  assert_output_equals "git cherry-pick -x main~2 topic"
  run hub --noop cherry-pick 'HEAD@{1}'
  assert_output_equals "git cherry-pick $(printf %q 'HEAD@{1}')"
  run hub --noop cherry-pick --continue
  assert_output_equals "git cherry-pick --continue"
  run hub --noop cherry-pick -h
  assert_output_equals "git cherry-pick -h"
  run hub --noop cherry-pick
  assert_output_equals "git cherry-pick"
  run hub --noop cherry-pick https://github.com/mislav/dotfiles/pull/12
  assert_output_equals "git cherry-pick https://github.com/mislav/dotfiles/pull/12"
  run hub --noop cherry-pick https://github.com/mislav/dotfiles/commit/main
  assert_output_equals "git cherry-pick https://github.com/mislav/dotfiles/commit/main"
  run hub --noop cherry-pick https://gitlab.com/mislav/dotfiles/commit/a319d88
  assert_output_equals "git cherry-pick https://gitlab.com/mislav/dotfiles/commit/a319d88"
  assert_gh_not_called
}

@test "cherry-pick really runs git cherry-pick" {
  make_repo dotfiles
  git checkout -q -b topic
  git commit -q --allow-empty -m "topic work"
  git checkout -q main
  run hub cherry-pick --allow-empty topic
  assert_success
  [[ $(git log -1 --format=%s) == "topic work" ]]
  assert_gh_not_called
}

@test "cherry-pick aborts when the commit can't be found" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'api --hostname github.com repos/jingweno/dotfiles/commits/a319d88 --jq .sha' '' 1
  run hub --noop cherry-pick https://github.com/jingweno/dotfiles/commit/a319d88
  assert_failure
  assert_output_equals "Aborted: could not find commit https://github.com/jingweno/dotfiles/commit/a319d88"
}

@test "cherry-pick --help prints the manual" {
  run hub cherry-pick --help
  assert_success
  assert_line_equals 0 "Summary: Cherry-pick a commit from GitHub by its URL, or from a fork as USER@SHA."
  assert_output_contains "Usage: hub cherry-pick [<git-cherry-pick options>] (COMMIT-URL | USER@SHA | <commit>)..."
}
