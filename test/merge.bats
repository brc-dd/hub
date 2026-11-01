#!/usr/bin/env bats
# hub merge: a pull request's head fetched from its repository and merged into the current branch.

load test_helper

url=https://github.com/octo/app/pull/12

# setup_pull : octo/app served with pull request 12 (jingweno's fix-build) on top of main, cloned
# into app; sets pull (its head) and base (main's tip) and stubs gh's lookup.
setup_pull() {
  serve_github octo/app
  clone_served octo/app contrib
  git switch -q -c fix-build
  printf 'built\n' >build.txt
  git add build.txt
  git commit -q -m 'Fix the build'
  git push -q origin HEAD:refs/pull/12/head
  cd "$HUB_TEST_TMP" || return 1
  pull=$(server_ref octo/app refs/pull/12/head)
  clone_served octo/app
  base=$(tip main)
  stub_gh "pr view $url* --json number,title,headRepositoryOwner,headRefName --jq *" \
    'Merge pull request #12 from jingweno/fix-build\nFix the build'
}

# assert_untouched : HEAD is still main at base, nothing was fetched and gh was not asked.
assert_untouched() {
  assert_equals "$(git rev-parse HEAD)" "$base"
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
  assert_gh_not_called
}

@test "hub merge merges the pull request's head with GitHub's message and a merge commit" {
  setup_pull
  run hub merge "$url"
  assert_success
  assert_equals "$(git rev-parse HEAD^1)" "$base"
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
  assert_equals "$(git log -1 --format=%B)" \
    $'Merge pull request #12 from jingweno/fix-build\n\nFix the build'
  assert_equals "$(git status --porcelain)" ''
  assert_equals "$(server_ref octo/app main)" "$base"
  assert_gh_called "pr view $url --json number,title,headRepositoryOwner,headRefName --jq *"
}

@test "hub merge reads a zero-padded pull request number as gh does, in decimal" {
  local padded=${url%/*}/012
  setup_pull
  stub_gh "pr view $padded --json*" $'Merge pull request #12 from jingweno/fix-build\nFix the build'
  run hub --noop merge "$padded"
  assert_success
  assert_line_equals 0 'git fetch --quiet --no-tags --refmap= -- origin refs/pull/12/head'
  run hub merge "$padded"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
  assert_equals "$(git log -1 --format=%s)" 'Merge pull request #12 from jingweno/fix-build'
}

@test "hub merge fetches through a remote whose name starts with a dash" {
  setup_pull
  git remote remove origin
  git remote add -- -x https://github.com/octo/app.git
  run hub merge "$url"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
  run cat .git/FETCH_HEAD
  assert_output_contains "'refs/pull/12/head' of https://github.com/octo/app"
}

@test "hub merge accepts a page of the whole pull request" {
  setup_pull
  run hub merge "$url/files"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
}

@test "hub merge fetches through the remote that points at the repository" {
  setup_pull
  git remote add upstream git@github.com:octo/app.git
  run hub merge "$url"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
  run cat .git/FETCH_HEAD
  assert_output_contains "'refs/pull/12/head' of github.com:octo/app"
}

@test "hub merge fetches from the repository's URL in gh's protocol without such a remote" {
  setup_pull
  git remote set-url origin https://github.com/mislav/app.git
  stub_gh 'config get git_protocol -h github.com' ssh
  run hub merge "$url"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
  run cat .git/FETCH_HEAD
  assert_output_contains "'refs/pull/12/head' of github.com:octo/app"
}

@test "hub merge leaves branches a configured refs/pull refspec maps to alone" {
  setup_pull
  git config --add remote.origin.fetch '+refs/pull/*/head:refs/heads/pull-*'
  git branch pull-12 main
  run hub merge "$url"
  assert_success
  assert_equals "$(tip pull-12)" "$base"
}

@test "hub merge brings no tags in" {
  setup_pull
  git -C "$(server_dir octo/app)" tag v1.0 "$pull"
  git config remote.origin.tagOpt --tags
  run hub merge "$url"
  assert_success
  assert_equals "$(git tag)" ''
}

@test "hub merge takes the user's fast-forward choice instead of --no-ff" {
  local opt
  setup_pull
  for opt in --ff --ff-only; do
    git reset -q --hard "$base"
    run hub merge "$opt" "$url"
    assert_success
    assert_equals "$(git rev-parse HEAD)" "$pull"
  done
  git reset -q --hard "$base"
  run hub merge "$url" --no-ff
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
}

@test "hub merge squashes without a merge commit or hub's message when --squash comes last" {
  setup_pull
  run hub merge --no-squash --squash "$url"
  assert_success
  assert_equals "$(git rev-parse HEAD)" "$base"
  assert_equals "$(git diff --cached --name-only)" build.txt
  git reset -q --hard "$base"
  run hub merge --squash "$url" --no-squash
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
  assert_equals "$(git log -1 --format=%s)" 'Merge pull request #12 from jingweno/fix-build'
}

@test "hub merge takes the user's message from -m, --message and -F" {
  local -a opts
  local spec
  setup_pull
  printf 'From a file\n' >"$HUB_TEST_TMP/msg.txt"
  for spec in '-m|Own' '-mOwn' '--message|Own' '--message=Own' "-F|$HUB_TEST_TMP/msg.txt" \
    "-F$HUB_TEST_TMP/msg.txt" "--file|$HUB_TEST_TMP/msg.txt" "--file=$HUB_TEST_TMP/msg.txt"; do
    IFS='|' read -r -a opts <<<"$spec"
    git reset -q --hard "$base"
    run hub merge "${opts[@]}" "$url"
    assert_success
    assert_equals "$(git rev-parse HEAD^2)" "$pull"
    case $spec in
      -F* | --file*) assert_equals "$(git log -1 --format=%B)" 'From a file' ;;
      *) assert_equals "$(git log -1 --format=%B)" Own ;;
    esac
  done
}

@test "hub merge leaves the message to git under --no-message" {
  setup_pull
  run hub merge --no-message "$url"
  assert_success
  assert_equals "$(git log -1 --format=%B)" "Merge commit '$pull'"
}

@test "hub merge reads a message that looks like a pull request URL as the message" {
  setup_pull
  git branch topic main
  commit_on topic 'a topic'
  run hub merge --no-ff -m "$url" refs/heads/topic
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$(tip topic)"
  assert_equals "$(git log -1 --format=%B)" "$url"
  assert_gh_not_called
}

@test "hub merge reads an option's separate value as the value, however it looks" {
  local word
  setup_pull
  for word in --squash --ff --abort; do
    git reset -q --hard "$base"
    run hub merge -m "$word" "$url"
    assert_success
    assert_equals "$(git rev-parse HEAD^2)" "$pull"
    assert_equals "$(git log -1 --format=%B)" "$word"
  done
}

@test "hub merge reads -S's attached key as one word" {
  setup_pull
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >>"$HUB_TEST_TMP/gpg.log"' 'cat >/dev/null' \
    'echo "[GNUPG:] SIG_CREATED " >&2' \
    'printf -- "-----BEGIN PGP SIGNATURE-----\nx\n-----END PGP SIGNATURE-----\n"' \
    >"$HUB_TEST_TMP/gpg"
  chmod +x "$HUB_TEST_TMP/gpg"
  git config gpg.program "$HUB_TEST_TMP/gpg"
  run hub merge -Sme@example.com "$url"
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$pull"
  assert_equals "$(git log -1 --format=%s)" 'Merge pull request #12 from jingweno/fix-build'
  run cat "$HUB_TEST_TMP/gpg.log"
  assert_output_contains '-bsau me@example.com'
}

@test "hub merge hands a cluster ending in -m to git, which reads the URL as the message" {
  setup_pull
  git branch topic main
  commit_on topic 'a topic'
  run hub merge --no-ff -qm "$url" refs/heads/topic
  assert_success
  assert_equals "$(git rev-parse HEAD^2)" "$(tip topic)"
  assert_equals "$(git log -1 --format=%B)" "$url"
  assert_gh_not_called
}

@test "hub merge leaves a final option without its value to git" {
  setup_pull
  run hub merge "$url" -m
  assert_status 129
  assert_output_contains 'requires a value'
  assert_untouched
}

@test "hub merge merges a pull request alone" {
  local -a line
  local spec alone='(a pull request is merged alone)'
  setup_pull
  git branch topic main
  for spec in "$url topic|topic" "topic $url|topic" "$url topic -- other|topic" \
    "$url -- other|other" "$url $url|$url"; do
    read -r -a line <<<"${spec%|*}"
    run hub merge "${line[@]}"
    assert_status 1
    assert_line_equals 0 "hub merge: unexpected argument: ${spec#*|} $alone"
    assert_line_equals 1 'Usage: hub merge [GIT-MERGE-OPTIONS...] PULL-REQUEST-URL'
    assert_untouched
  done
  run hub merge "$url" ''
  assert_status 1
  assert_line_equals 0 "hub merge: unexpected argument: '' $alone"
  assert_untouched
}

@test "hub merge is plain git merge without a pull request URL before --" {
  local word
  local -a line
  setup_pull
  git branch topic main
  commit_on topic 'a topic'
  run hub merge -q --no-edit refs/heads/topic
  assert_success
  assert_equals "$(git rev-parse HEAD)" "$(tip topic)"
  git reset -q --hard "$base"
  for word in "-- $url" "--end-of-options $url" "$url/commits/$pull" "$url.patch" \
    "$url/files/$pull" "$url/changes/$pull" "$url/files/$base..$pull" \
    https://gitlab.com/octo/app/pull/12; do
    read -r -a line <<<"$word"
    run hub merge "${line[@]}"
    assert_failure
    assert_output_contains 'not something we can merge'
    assert_untouched
  done
}

@test "hub merge hands --abort, --quit, --continue and -h, alone or in a cluster, to git" {
  local word
  setup_pull
  for word in --abort --quit --continue; do
    run hub merge "$word" "$url"
    assert_status 129
    assert_output_contains "fatal: $word expects no arguments"
    assert_untouched
  done
  for word in -h -qh; do
    run hub merge "$word" "$url"
    assert_git_help merge
    assert_output_contains 'usage: git merge'
    assert_untouched
  done
}

@test "hub merge hands an abbreviated option it would have to read to git" {
  local word
  setup_pull
  for word in --squ --no-mess=Own --ff-o --abo; do
    run hub merge "$word" "$url"
    assert_failure
    assert_untouched
  done
}

@test "hub merge --help is git's manual" {
  setup_pull
  run hub --noop merge --help "$url"
  assert_success
  assert_output_equals "git merge --help $url"
}

@test "hub merge --help-all is git's usage, before the lookup and the fetch" {
  setup_pull
  run hub merge --help-all "$url"
  assert_git_help merge
  assert_gh_not_called
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub merge stops when gh cannot look the pull request up, and fetches nothing" {
  setup_pull
  stub_gh 'pr view *' '' 1
  PATH=$(failing_gh 'GraphQL: Could not resolve to a PullRequest'):$PATH run hub merge "$url"
  assert_status 1
  assert_output_equals 'GraphQL: Could not resolve to a PullRequest'
  assert_equals "$(git rev-parse HEAD)" "$base"
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub merge relays gh's exit status" {
  setup_pull
  stub_gh 'pr view *' '' 4
  run hub merge "$url"
  assert_status 4
  assert_equals "$(git rev-parse HEAD)" "$base"
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub merge refuses without gh before fetching" {
  setup_pull
  PATH=$(no_gh_path) run hub merge "$url"
  assert_status 1
  assert_output_equals 'hub merge: this command needs the GitHub CLI, gh (https://cli.github.com)'
  assert_untouched
}

@test "hub merge stops when the fetched head cannot be read from FETCH_HEAD" {
  local dir=$HUB_TEST_TMP/git-core real
  setup_pull
  # git puts its exec path first on PATH for hub's alias: the failing git goes there.
  real=$(readlink "$GIT_EXEC_PATH/git")
  mkdir "$dir" && ln -s "$GIT_EXEC_PATH"/* "$dir/" && rm "$dir/git"
  printf '%s\n' '#!/bin/sh' '[ "$*" != "rev-parse --verify --quiet FETCH_HEAD" ] || exit 1' \
    "exec '$real' \"\$@\"" >"$dir/git"
  chmod +x "$dir/git"
  GIT_EXEC_PATH=$dir run hub merge "$url"
  assert_failure
  assert_output_equals 'hub merge: could not read refs/pull/12/head from FETCH_HEAD'
  assert_equals "$(git rev-parse HEAD)" "$base"
}

@test "hub merge relays a failed fetch and merges nothing" {
  setup_pull
  stub_gh "pr view ${url%/*}/13 --json*" $'Merge pull request #13 from a/b\nT'
  run hub merge https://github.com/octo/app/pull/13
  assert_failure
  assert_output_contains "couldn't find remote ref refs/pull/13/head"
  assert_equals "$(git rev-parse HEAD)" "$base"
}

@test "hub merge leaves a conflicted merge to the user, with the pull request as MERGE_HEAD" {
  setup_pull
  printf 'local\n' >build.txt
  git add build.txt
  git commit -q -m 'Conflict'
  run hub merge "$url"
  assert_status 1
  assert_output_contains 'CONFLICT'
  assert_equals "$(git rev-parse MERGE_HEAD)" "$pull"
}

@test "hub merge refuses outside a work tree before asking gh" {
  setup_pull
  cd "$HUB_TEST_TMP"
  run hub merge "$url"
  assert_failure
  assert_output_contains 'not a git repository'
  assert_gh_not_called
}

@test "hub merge under --noop prints the fetch and the merge" {
  local line
  setup_pull
  run hub --noop merge "$url"
  assert_success
  assert_line_equals 0 'git fetch --quiet --no-tags --refmap= -- origin refs/pull/12/head'
  printf -v line '%q ' git merge --no-ff -m 'Merge pull request #12 from jingweno/fix-build' \
    -m 'Fix the build' FETCH_HEAD
  assert_line_equals 1 "${line% }"
  assert_equals "$(git rev-parse --verify --quiet FETCH_HEAD)" ''
}

@test "hub help merge points at git's manual" {
  run hub help merge
  assert_success
  assert_line_equals -1 "git's own manual: git merge --help"
}
