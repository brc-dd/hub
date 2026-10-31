#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test runs in a subshell, so its exports stay local on purpose
load ../test_helper

# feature_repo : a clone of the served github.com/mislav/dotfiles on a new branch "feature" with one
# commit ("Fix the bug" / "It was broken."), not pushed yet.
feature_repo() {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles dotfiles
  git checkout -q -b feature
  git commit -q --allow-empty -m "Fix the bug" -m "It was broken."
}

# pushed_repo : feature_repo with the branch pushed to origin, tracking origin/feature.
pushed_repo() {
  feature_repo
  git push -q -u origin feature
}

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

# branches [HOST/]OWNER/REPO : the served repository's branches, sorted, on one line.
branches() { server_branches "$1" | sort | tr '\n' ' '; }

@test "-p pushes the current branch where git pushes it, sets its upstream and names it as the head" {
  feature_repo
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/1'
  run hub pull-request -p -m "Fix the bug"
  assert_success
  assert_output_contains "https://github.com/mislav/dotfiles/pull/1"
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(git rev-parse HEAD)"
  assert_equals "$(git config branch.feature.remote)" origin
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix the bug --body '
  # with an upstream, no --set-upstream; the branch is pushed again
  git commit -q --allow-empty -m More
  run hub --noop pull-request -p -m Fix
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/feature\ngh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body \'\''
  run hub pull-request -p -m Fix
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(git rev-parse HEAD)"
}

@test "the head is the branch git pushes to: remote.*.push refspecs and push.default rename it" {
  feature_repo
  stub_gh 'pr create *' ''
  git config remote.origin.push refs/heads/feature:refs/heads/publish
  run hub pull-request -p -m Fix
  assert_success
  assert_equals "$(branches mislav/dotfiles)" "main publish "
  assert_equals "$(server_ref mislav/dotfiles refs/heads/publish)" "$(git rev-parse HEAD)"
  assert_equals "$(git config branch.feature.merge)" refs/heads/publish
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head publish --title Fix --body '
  # the same when the fetch refspec maps no tracking ref for publish
  git config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
  git commit -q --allow-empty -m More
  run hub pull-request -p -m Fix
  assert_success
  assert_equals "$(branches mislav/dotfiles)" "main publish "
  assert_equals "$(server_ref mislav/dotfiles refs/heads/publish)" "$(git rev-parse HEAD)"
  # push.default=upstream pushes to the upstream's name
  git config --unset remote.origin.push
  git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git config push.default upstream
  git config branch.feature.merge refs/heads/topic
  run hub --noop pull-request -p -m Fix
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/topic\ngh pr create --repo github.com/mislav/dotfiles --base main --head topic --title Fix --body \'\''
  # push.default=current pushes a branch without an upstream under its own name
  git branch --unset-upstream
  git config push.default current
  run hub --noop pull-request -p -m Fix
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body \'\''
}

@test "a tag named like the branch does not change the branch hub publishes" {
  feature_repo
  git tag feature
  stub_gh 'pr create *' ''
  run hub pull-request -p -m Fix
  assert_success
  assert_equals "$(branches mislav/dotfiles)" "feature main "
  assert_equals "$(server_ref mislav/dotfiles refs/heads/feature)" "$(git rev-parse HEAD)"
  assert_equals "$(git config branch.feature.merge)" refs/heads/feature
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body '
}

@test "a head pushed under another name keeps the local branch's merge base and commit message" {
  feature_repo
  git push -q origin HEAD:refs/heads/publish
  git branch -u origin/publish
  git config push.default upstream
  git update-ref refs/remotes/origin/develop main
  git config branch.feature.gh-merge-base develop
  git commit -q --allow-empty -m "Second commit"
  run hub --noop pull-request -p --no-edit
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/publish\ngh pr create --repo github.com/mislav/dotfiles --base develop --head publish --title Fix\\ the\\ bug --body It\\ was\\ broken.'
  # a local branch named like the head, with other commits, changes nothing
  git update-ref refs/heads/publish "$(git commit-tree -p main -m "WRONG local publish title" "main^{tree}")"
  git config branch.publish.gh-merge-base release
  run hub --noop pull-request -p --no-edit
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/publish\ngh pr create --repo github.com/mislav/dotfiles --base develop --head publish --title Fix\\ the\\ bug --body It\\ was\\ broken.'
  run hub --noop pull-request -p --no-edit -b main
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/publish\ngh pr create --repo github.com/mislav/dotfiles --base main --head publish --title Fix\\ the\\ bug --body It\\ was\\ broken.'
  assert_gh_not_called
}

@test "a cached remote HEAD pointing at a branch that no longer exists is not the base; gh is asked" {
  pushed_repo
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request -i 12
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=feature -f base=trunk --jq .html_url"
  run hub --noop pull-request -m Fix
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base trunk --head feature --title Fix --body ''"
  run hub --noop pull-request -m Fix -b main
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body ''"
}

@test "without -p, the branch must be pushed where git pushes it; -f skips the check" {
  feature_repo
  run hub --noop pull-request -m Fix
  assert_failure
  assert_output_equals "Aborted: feature seems not yet pushed to origin (use -p to push it, or -f to skip this check)."
  git push -q -u origin feature
  git commit -q --allow-empty -m More
  run hub --noop pull-request -m Fix
  assert_failure
  assert_output_equals "Aborted: 1 commit of feature is not yet pushed to origin/feature (use -p to push it, or -f to skip this check)."
  git commit -q --allow-empty -m "Even more"
  run hub --noop pull-request -m Fix
  assert_failure
  assert_output_equals "Aborted: 2 commits of feature are not yet pushed to origin/feature (use -p to push them, or -f to skip this check)."
  run hub --noop pull-request -f -m Fix
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body ''"
  run hub --noop pull-request -pf -m Fix
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/feature\ngh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body \'\''
  assert_gh_not_called
}

@test "when git push would refuse, hub says so before pushing anywhere" {
  feature_repo
  git config push.default nothing
  run hub pull-request -p -m Fix
  assert_failure
  assert_output_contains "Aborted: git push would refuse to push feature as configured"
  assert_output_contains "git push -u origin feature"
  git config push.default simple
  git branch -u origin/main # an upstream of another name: simple refuses
  run hub pull-request -p -m Fix
  assert_failure
  assert_output_contains "Aborted: git push would refuse to push feature as configured"
  assert_equals "$(branches mislav/dotfiles)" "main "
  assert_gh_not_called
}

@test "a branch that pushes to a fork is the head OWNER:BRANCH in the main project" {
  feature_repo
  serve_github alice/dotfiles
  git remote add fork https://github.com/alice/dotfiles.git
  git config remote.pushDefault fork
  stub_gh 'api --hostname github.com users/alice -q .type' 'User'
  stub_gh 'pr create *' ''
  run hub pull-request -p -m Fix
  assert_success
  assert_equals "$(server_ref alice/dotfiles refs/heads/feature)" "$(git rev-parse HEAD)"
  [[ -z $(server_ref mislav/dotfiles refs/heads/feature) ]]
  assert_equals "$(git config branch.feature.remote)" fork
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head alice:feature --title Fix --body '
  # what a remote pushes to counts, not what it fetches from
  git branch --unset-upstream
  git config --unset remote.pushDefault
  git remote set-url --push origin https://github.com/alice/dotfiles.git
  run hub --noop pull-request -p -m Fix
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh pr create --repo github.com/mislav/dotfiles --base main --head alice:feature --title Fix --body \'\''
  # gh pr create cannot take a head owned by an organization; the API that -i uses can
  stub_gh 'api --hostname github.com users/alice -q .type' 'Organization'
  git commit -q --allow-empty -m More
  run hub pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: gh pr create cannot take a head owned by an organization (alice:feature); convert an issue with -i, or use gh api repos/mislav/dotfiles/pulls."
  [[ $(server_ref alice/dotfiles refs/heads/feature) != "$(git rev-parse HEAD)" ]]
  run hub --noop pull-request -p -i 12
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=alice:feature -f head_repo=dotfiles -f base=main --jq .html_url'
  stub_gh 'api --hostname github.com users/alice -q .type' '' 1
  run hub --noop pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: could not look up alice on github.com."
}

@test "-h OWNER:BRANCH pushes HEAD to OWNER's remote and names the head there" {
  feature_repo
  serve_github alice/dotfiles bob/other
  git remote add alice https://github.com/alice/dotfiles.git
  git remote add bobs https://github.com/bob/other.git
  stub_gh 'api --hostname github.com users/alice -q .type' 'User'
  stub_gh 'api --hostname github.com users/bob -q .type' 'User'
  stub_gh 'pr create *' ''
  run hub pull-request -p -h alice:other -m Title
  assert_success
  assert_equals "$(server_ref alice/dotfiles refs/heads/other)" "$(git rev-parse HEAD)"
  assert_equals "$(branches mislav/dotfiles)" "main "
  assert_equals "$(git config branch.feature.merge)" refs/heads/other # HEAD had no upstream yet
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head alice:other --title Title --body '
  run hub --noop pull-request -p -h Alice:other -m Title
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --base main --head alice:other --title Title --body \'\''
  run hub --noop pull-request -p -h bob:other -m Title
  assert_success
  assert_output_equals $'git push bobs HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --base main --head bob:other --title Title --body \'\''
  run hub --noop pull-request -p -h mislav:other -m Title
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --base main --head other --title Title --body \'\''
  run hub --noop pull-request -p -h carol:other -m Title
  assert_failure
  assert_output_equals "Aborted: no remote here pushes to a repository of carol's on github.com; add one (git remote add carol) or push the branch yourself."
  stub_gh 'api --hostname github.com users/carol -q .type' 'User'
  run hub --noop pull-request -h carol:other -m Title # without -p, no remote is needed
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head carol:other --title Title --body ''"
}

@test "-h BRANCH names a branch on the remote the current branch pushes to, pushed from HEAD with -p" {
  feature_repo
  stub_gh 'pr create *' ''
  run hub pull-request -p -h other -m Title
  assert_success
  assert_equals "$(server_ref mislav/dotfiles refs/heads/other)" "$(git rev-parse HEAD)"
  assert_equals "$(branches mislav/dotfiles)" "main other "
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head other --title Title --body '
  run hub --noop pull-request -h other -m Title # named explicitly, the branch is not checked for pushes
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head other --title Title --body ''"
  git checkout -q --detach
  run hub --noop pull-request -p -h another -m Title
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/another\ngh pr create --repo github.com/mislav/dotfiles --base main --head another --title Title --body \'\''
  run hub --noop pull-request -p -m Title
  assert_failure
  assert_output_equals "Aborted: not currently on any branch; name the head with -h [OWNER:]BRANCH."
  run hub --noop pull-request -h 'bad name'
  assert_failure
  assert_output_equals "Aborted: not a branch name: bad name (given with -h)"
  run hub --noop pull-request -h alice/x:y
  assert_failure
  assert_output_equals "Aborted: not a head: alice/x:y (use [OWNER:]BRANCH)"
  run hub --noop pull-request -h other -b 'bad name'
  assert_failure
  assert_output_equals "Aborted: not a branch name: bad name (given with -b)"
}

@test "-b OWNER:BRANCH and OWNER/REPO:BRANCH put the base in that repository on the project's host" {
  pushed_repo
  stub_gh 'api --hostname github.com users/mislav -q .type' 'User'
  run hub --noop pull-request -m Fix -b alice:develop
  assert_success
  assert_output_equals "gh pr create --repo github.com/alice/dotfiles --base develop --head mislav:feature --title Fix --body ''"
  run hub --noop pull-request -m Fix --base=alice/fork:develop
  assert_success
  assert_output_equals "gh pr create --repo github.com/alice/fork --base develop --head mislav:feature --title Fix --body ''"
  run hub --noop pull-request -m Fix -b mislav:develop
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base develop --head feature --title Fix --body ''"
  run hub --noop pull-request -b alice:
  assert_failure
  assert_output_equals "Aborted: not a base: alice: (use [OWNER[/REPO]:]BRANCH)"
  # the current branch's gh-merge-base is the default base
  git config branch.feature.gh-merge-base develop
  run hub --noop pull-request -m Fix
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base develop --head feature --title Fix --body ''"
  run hub --noop pull-request -m Fix -b main
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body ''"
}

@test "GH_REPO names the base repository; its default branch comes from gh when no remote points at it" {
  pushed_repo
  stub_gh 'api --hostname github.com users/mislav -q .type' 'User'
  stub_gh 'repo view github.com/cli/cli --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  GH_REPO=cli/cli run hub --noop pull-request -m Fix
  assert_success
  assert_output_equals "gh pr create --repo github.com/cli/cli --base trunk --head mislav:feature --title Fix --body ''"
  GH_REPO=cli/cli run hub --noop pull-request -i 12
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/cli/cli/pulls -F issue=12 -f head=mislav:feature -f head_repo=dotfiles -f base=trunk --jq .html_url"
  stub_gh 'repo view github.com/cli/cli --json defaultBranchRef *' '' 1
  GH_REPO=cli/cli run hub --noop pull-request -m Fix
  assert_failure
  assert_output_equals "Aborted: could not look up the default branch of cli/cli; give the base with -b BRANCH."
  GH_REPO=cli/cli run hub --noop pull-request -m Fix -b trunk
  assert_success
  assert_output_equals "gh pr create --repo github.com/cli/cli --base trunk --head mislav:feature --title Fix --body ''"
  GH_REPO=ghe.example.com/cli/cli run hub --noop pull-request -m Fix -b trunk
  assert_failure
  assert_output_equals "Aborted: remote origin pushes to github.com, but the pull request is for ghe.example.com/cli/cli."
  GH_REPO=cli/cli run hub --noop pull-request --no-edit -b trunk
  assert_failure
  assert_output_equals "Aborted: --no-edit takes the message from the commits since trunk, but no remote here points at github.com/cli/cli to compare with."
}

@test "the head and the base cannot be the same branch" {
  pushed_repo
  git checkout -q main
  git commit -q --allow-empty -m "On main"
  run hub pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: the head and the base are the same branch, main of mislav/dotfiles; name another base with -b or another head with -h."
  run hub pull-request -p -h main -b main -m Fix
  assert_failure
  assert_equals "$(server_ref mislav/dotfiles refs/heads/main)" "$(git rev-parse origin/main)"
  run hub --noop pull-request -p -b develop -m Fix
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/main\ngh pr create --repo github.com/mislav/dotfiles --base develop --head main --title Fix --body \'\''
  assert_gh_not_called
}

@test "the project's host is named for gh and the API, whatever gh's default host is" {
  git config --global --add hub.host ghe.example.com
  serve_github ghe.example.com/mislav/dotfiles
  clone_served ghe.example.com/mislav/dotfiles dotfiles
  git checkout -q -b feature
  git commit -q --allow-empty -m Fix
  git push -q -u origin feature
  export GH_HOST=enterprise.example
  run hub --noop pull-request -m Fix
  assert_success
  assert_output_equals "gh pr create --repo ghe.example.com/mislav/dotfiles --base main --head feature --title Fix --body ''"
  run hub --noop pull-request -i 12
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=feature -f base=main --jq .html_url"
  assert_gh_not_called
  stub_gh 'repo view ghe.example.com/other/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request https://ghe.example.com/other/dotfiles/issues/3
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com -X POST repos/other/dotfiles/pulls -F issue=3 -f head=mislav:feature -f head_repo=dotfiles -f base=trunk --jq .html_url"
}

@test "an HTTPS host is taken literally and an SSH alias as ssh resolves it, before anything is pushed" {
  feature_repo
  cat >"$HUB_TEST_TMP/ssh_config" <<'EOF'
Host github.internal
  HostName github.com
Match originalhost scoped-alias user git
  HostName enterprise.example
Host scoped-alias
  HostName github.com
EOF
  export GIT_SSH_COMMAND="ssh -F $HUB_TEST_TMP/ssh_config" GH_REPO=github.com/mislav/dotfiles
  git remote set-url origin https://github.internal/mislav/dotfiles.git # ssh_config never rewrites HTTPS
  run hub pull-request -p -m Title
  assert_failure
  assert_output_equals "Aborted: remote origin does not push to a GitHub repository hub knows (git remote get-url --push origin; see hub.host)."
  git remote set-url origin git@scoped-alias:mislav/dotfiles.git # the Match rule sees the URL's user
  run hub pull-request -p -m Title
  assert_failure
  assert_output_equals "Aborted: remote origin does not push to a GitHub repository hub knows (git remote get-url --push origin; see hub.host)."
  assert_gh_not_called
  serve_github github.internal/mislav/dotfiles
  git remote set-url origin git@github.internal:mislav/dotfiles.git # an alias of github.com
  stub_gh 'pr create *' ''
  run hub pull-request -p -m Title
  assert_success
  assert_equals "$(server_ref github.internal/mislav/dotfiles refs/heads/feature)" "$(git rev-parse HEAD)"
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head feature --title Title --body '
}

@test "-p pushes nothing when hub or gh would refuse the arguments" {
  feature_repo
  run hub pull-request -p -i 12 -m Fix
  assert_failure
  assert_output_equals "Aborted: -i converts an issue, which keeps its title and body; it takes only -b, -h, -p, -f, -d, --no-maintainer-edits, -o and -c."
  run hub pull-request -p -e --no-edit
  assert_failure
  assert_output_equals "Aborted: -e and --no-edit cannot be used together."
  run hub pull-request -p -F no-such-file
  assert_failure
  assert_output_equals "Aborted: cannot read no-such-file"
  run hub pull-request -p --fill -m Fix
  assert_failure
  assert_line_equals 0 "hub pull-request: unknown option: --fill"
  run hub pull-request -p -m Fix -b 'bad name'
  assert_failure
  assert_output_equals "Aborted: not a branch name: bad name (given with -b)"
  run hub pull-request -p -e -m Fix </dev/null
  assert_failure
  assert_output_equals "Aborted: -e needs a terminal (gh opens its editor only in interactive mode); not pushing."
  run hub pull-request -p </dev/null
  assert_failure
  assert_output_equals "Aborted: give the title and body with -m or -F (gh asks for them only in interactive mode); not pushing."
  run hub pull-request -p -h main -m Fix
  assert_failure
  assert_output_equals "Aborted: the head and the base are the same branch, main of mislav/dotfiles; name another base with -b or another head with -h."
  assert_equals "$(branches mislav/dotfiles)" "main "
  [[ -z $(git config branch.feature.merge) ]]
  assert_gh_not_called
}

@test "-o and -c leave gh's prompts and output alone, then look the URL up" {
  pushed_repo
  mkdir -p "$HUB_TEST_TMP/fake"
  cat >"$HUB_TEST_TMP/fake/gh" <<'SH'
#!/usr/bin/env bash
# a gh pr create that prompts on hub's standard input and prints as gh does
[[ $1 == pr ]] || exec "$HUB_TEST_ROOT/test/stubs/gh" "$@"
printf 'gh %s\n' "$*" >>"$HUB_TEST_LOG"
if [[ $2 == create ]]; then
  IFS= read -r answer
  printf 'Title? %s\nhttps://github.com/mislav/dotfiles/pull/7\n' "$answer"
else
  printf 'https://github.com/mislav/dotfiles/pull/7\n'
fi
SH
  chmod +x "$HUB_TEST_TMP/fake/gh"
  fake_browser
  fake_clipboard
  PATH=$HUB_TEST_TMP/fake:$PATH run hub pull-request -o -c <<<"typed title"
  assert_success
  assert_output_equals $'Title? typed title\nhttps://github.com/mislav/dotfiles/pull/7'
  assert_equals "$(cat "$HUB_TEST_TMP/browsed")" https://github.com/mislav/dotfiles/pull/7
  assert_equals "$(cat "$HUB_TEST_TMP/clipboard")" https://github.com/mislav/dotfiles/pull/7
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head feature'
  assert_gh_called 'pr view feature --repo github.com/mislav/dotfiles --json url --jq .url'
  run hub --noop pull-request -o -m Fix
  assert_success
  assert_output_equals $'gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body \'\'\ngh pr view feature --repo github.com/mislav/dotfiles --json url --jq .url'
  # a head in a fork is looked up as OWNER:BRANCH (-f: a remote that pushes elsewhere shows nothing about the branch)
  git remote set-url --push origin https://github.com/alice/dotfiles.git
  stub_gh 'api --hostname github.com users/alice -q .type' 'User'
  run hub --noop pull-request -f -c -m Fix
  assert_success
  assert_line_equals 1 "gh pr view alice:feature --repo github.com/mislav/dotfiles --json url --jq .url"
}

@test "when gh fails after creating the pull request, its URL is still shown and the command fails" {
  pushed_repo
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/7\npull request update failed: reviewer not found' 1
  fake_browser
  run hub pull-request -m Fix -r nobody -o
  assert_failure
  assert_line_equals 0 "https://github.com/mislav/dotfiles/pull/7"
  [[ ! -e $HUB_TEST_TMP/browsed ]]
  stub_gh 'pr create *' '' 4
  run hub pull-request -m Fix -o
  [[ $status -eq 4 ]]
  assert_output_equals ""
}

@test "a failing browser or clipboard tool fails the command, after the URL is shown" {
  pushed_repo
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/7'
  stub_gh 'pr view feature --repo github.com/mislav/dotfiles --json url --jq .url' 'https://github.com/mislav/dotfiles/pull/7'
  fake_browser 19
  run hub pull-request -m Fix -o
  [[ $status -eq 19 ]]
  assert_output_equals "https://github.com/mislav/dotfiles/pull/7"
  assert_equals "$(cat "$HUB_TEST_TMP/browsed")" https://github.com/mislav/dotfiles/pull/7
  fake_clipboard 17
  run hub pull-request -m Fix -c
  [[ $status -eq 17 ]]
  fake_browser 0
  run hub pull-request -m Fix -o -c # the clipboard fails and the browser works: still a failure
  [[ $status -eq 17 ]]
  assert_equals "$(wc -l <"$HUB_TEST_TMP/browsed" | tr -d ' ')" 2
  stub_gh 'pr view *' '' 1
  run hub pull-request -m Fix -o
  assert_failure
  assert_line_equals -1 "Aborted: the pull request exists, but its URL could not be looked up (gh pr view feature --repo github.com/mislav/dotfiles)."
}

@test "-i N converts the issue through the API, with the head and base as strings" {
  pushed_repo
  run hub --noop pull-request -i 12
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=feature -f base=main --jq .html_url"
  run hub --noop pull-request --issue '#12' -b develop -d --no-maintainer-edits
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=feature -f base=develop -F draft=true -F maintainer_can_modify=false --jq .html_url"
  git checkout -q -b true # names gh api -F would read as a boolean or a file stay strings
  run hub --noop pull-request -f -i 12
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=true -f base=main --jq .html_url"
  run hub --noop pull-request -i 12 -h @file
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=@file -f base=main --jq .html_url"
  assert_gh_not_called
  stub_gh 'api --hostname github.com -X POST repos/mislav/dotfiles/pulls *' 'https://github.com/mislav/dotfiles/pull/12'
  fake_browser
  run hub pull-request -f -i 12 -o
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/pull/12"
  assert_equals "$(cat "$HUB_TEST_TMP/browsed")" https://github.com/mislav/dotfiles/pull/12
  stub_gh 'api --hostname github.com -X POST repos/mislav/dotfiles/pulls *' '' 1
  run hub pull-request -f -i 12 -o
  assert_failure
  assert_equals "$(wc -l <"$HUB_TEST_TMP/browsed" | tr -d ' ')" 1
}

@test "an issue URL converts that issue in its own repository, onto its default branch" {
  pushed_repo
  run hub --noop pull-request https://github.com/Mislav/Dotfiles/issues/12
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/Mislav/Dotfiles/pulls -F issue=12 -f head=feature -f base=main --jq .html_url"
  stub_gh 'repo view github.com/github/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/github/dotfiles/pulls -F issue=3 -f head=mislav:feature -f head_repo=dotfiles -f base=trunk --jq .html_url"
  [[ $(gh_calls) != *users/* ]] # the API takes any owner's head
  run hub --noop pull-request -b develop -- https://github.com/github/dotfiles/issues/3
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/github/dotfiles/pulls -F issue=3 -f head=mislav:feature -f head_repo=dotfiles -f base=develop --jq .html_url"
  stub_gh 'repo view github.com/github/dotfiles --json defaultBranchRef *' '' 1
  run hub --noop pull-request -p -i https://github.com/github/dotfiles/issues/3
  assert_failure
  assert_output_equals "Aborted: could not look up the default branch of github/dotfiles; give the base with -b BRANCH."
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3 -b alice:main
  assert_failure
  assert_output_equals "Aborted: the issue URL names the base repository; give -b as BRANCH alone."
  run hub --noop pull-request -i 12 https://github.com/github/dotfiles/issues/3
  assert_failure
  assert_output_equals "Aborted: name the issue once (-i 12 and https://github.com/github/dotfiles/issues/3)."
  run hub --noop pull-request -i twelve
  assert_failure
  assert_output_equals "Aborted: not an issue number or URL: twelve"
  run hub --noop pull-request https://github.com/github/dotfiles/pull/3
  assert_failure
  assert_line_equals 0 "hub pull-request: unexpected argument: https://github.com/github/dotfiles/pull/3"
}

@test "-i takes no message, editor, reviewer, assignee, milestone or label" {
  pushed_repo
  local args
  for args in "-m Fix" "-F -" "-e" "--no-edit" "-r alice" "-a bob" "-M v1" "-l bug"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request -i 12 $args </dev/null
    assert_failure
    assert_output_equals "Aborted: -i converts an issue, which keeps its title and body; it takes only -b, -h, -p, -f, -d, --no-maintainer-edits, -o and -c."
  done
  assert_gh_not_called
}

@test "-m and -F give the title (the first paragraph) and the body; -e opens the editor; --no-edit takes the first commit" {
  pushed_repo
  run hub --noop pull-request -m $'Fix the\nbug\n\nIt was broken.' -m "Now it is not."
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix\\ the\\ bug --body \$'It was broken.\\n\\nNow it is not.'"
  printf 'Fix the bug\n\nIt was broken.\n' >"$HUB_TEST_TMP/msg.txt"
  run hub --noop pull-request -F "$HUB_TEST_TMP/msg.txt"
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix\\ the\\ bug --body It\\ was\\ broken."
  run hub --noop pull-request -F - <<<$'From stdin\n\nBody.'
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title From\\ stdin --body Body."
  run hub --noop pull-request -e
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --editor"
  run hub --noop pull-request -e -m Fix
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body '' --editor"
  run hub --noop pull-request --edit -m ''
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --editor"
  run hub --noop pull-request --no-edit
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix\\ the\\ bug --body It\\ was\\ broken."
  git commit -q --allow-empty -m "Second commit"
  run hub --noop pull-request -f --no-edit # the first commit on the branch, not the last
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix\\ the\\ bug --body It\\ was\\ broken."
  git checkout -q main
  run hub --noop pull-request --no-edit -b develop
  assert_failure
  assert_output_equals "Aborted: --no-edit needs origin/develop locally; run git fetch origin first."
  git update-ref refs/remotes/origin/develop HEAD
  run hub --noop pull-request --no-edit -b develop
  assert_failure
  assert_output_equals "Aborted: no commits between origin/develop and HEAD to take the message from."
  assert_gh_not_called
}

@test "a missing or empty value, an unreadable file, an empty title and conflicting options abort" {
  pushed_repo
  run hub --noop pull-request -b
  assert_failure
  assert_output_equals "Aborted: -b needs a value."
  run hub --noop pull-request -b '' -m Fix
  assert_failure
  assert_output_equals "Aborted: -b needs a value."
  run hub --noop pull-request -m
  assert_failure
  assert_output_equals "Aborted: -m needs a value."
  run hub --noop pull-request -m ''
  assert_failure
  assert_output_equals "Aborted: the pull request title is empty."
  run hub --noop pull-request -F no-such-file
  assert_failure
  assert_output_equals "Aborted: cannot read no-such-file"
  run hub --noop pull-request -m Fix -F - <<<"Other"
  assert_failure
  assert_output_equals "Aborted: -m and -F cannot be used together."
  run hub --noop pull-request -e --no-edit
  assert_failure
  assert_output_equals "Aborted: -e and --no-edit cannot be used together."
  run hub --noop pull-request --no-edit -m Fix
  assert_failure
  assert_output_equals "Aborted: --no-edit takes the message from the first commit; -m and -F give one."
  assert_gh_not_called
}

@test "hub's options take long names, attached values and clusters" {
  pushed_repo
  local args expected="gh pr create --repo github.com/mislav/dotfiles --base develop --head feature --title Fix --body '' --draft --reviewer alice --label bug"
  for args in "-m Fix -b develop -h feature -d -r alice -l bug" \
    "--message Fix --base develop --head feature --draft --reviewer alice --labels bug" \
    "--message=Fix --base=develop --head=feature --draft --reviewer=alice --labels=bug" \
    "-mFix -bdevelop -hfeature -d -ralice -lbug" \
    "-dmFix -b develop -h feature -r alice -l bug"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request $args
    assert_success
    assert_output_equals "$expected"
  done
  run hub --noop pull-request -b develop -h mislav:feature -d -r alice,bob -r org/team -a carol -M v1.0 -l bug,ui --no-maintainer-edits -m Fix -m "More text."
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base develop --head feature --title Fix --body More\\ text. --draft --no-maintainer-edit --reviewer alice,bob --reviewer org/team --assignee carol --milestone v1.0 --label bug,ui"
  assert_gh_not_called
}

@test "options hub does not own are errors, before anything runs" {
  feature_repo
  local opt
  for opt in --fill -w --web --dry-run -R --repo=x -t --title --body -B -H -x --draft=false; do
    run hub pull-request -p "$opt" -m Fix
    assert_failure
    assert_line_equals 0 "hub pull-request: unknown option: $opt"
    assert_output_contains "Usage: hub pull-request"
  done
  run hub pull-request -pw -m Fix
  assert_failure
  assert_line_equals 0 "hub pull-request: unknown option: -w"
  assert_equals "$(branches mislav/dotfiles)" "main "
  assert_gh_not_called
}

@test "--help, a bare -h and help pull-request print the manual" {
  run hub pull-request --help
  assert_success
  assert_output_contains "Usage: hub pull-request"
  run hub pull-request -h
  assert_success
  assert_output_contains "Usage: hub pull-request"
  run hub help pull-request
  assert_success
  assert_output_contains "-i, --issue ISSUE"
  assert_gh_not_called
}

@test "pull-request outside a repository aborts" {
  run hub --noop pull-request -m Fix
  assert_failure
  assert_output_contains "fatal: not a git repository"
  assert_gh_not_called
}

@test "-h OWNER:BRANCH with -p finds OWNER's remote however its URL spells the names" {
  feature_repo
  serve_github alice/other Alice/DotFiles
  git remote add a https://github.com/alice/other.git    # alice's, but another repository
  git remote add z https://github.com/Alice/DotFiles.git # the one named like the base, spelled otherwise
  stub_gh 'api --hostname github.com users/Alice -q .type' 'User'
  stub_gh 'pr create *' ''
  run hub pull-request -p -h alice:feature -m Fix
  assert_success
  assert_equals "$(server_ref Alice/DotFiles refs/heads/feature)" "$(git rev-parse HEAD)"
  [[ -z $(server_ref alice/other refs/heads/feature) ]]
  assert_equals "$(git config branch.feature.remote)" z
  # the head is named as the remote's URL spells the owner, like a head found without -h
  assert_gh_called 'pr create --repo github.com/mislav/dotfiles --base main --head Alice:feature --title Fix --body '
  # -i names the head repository as the remote spells it too
  run hub --noop pull-request -p -h alice:feature -i 12
  assert_success
  assert_line_equals 1 "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=Alice:feature -f head_repo=DotFiles -f base=main --jq .html_url"
}

@test "remote.*.push refspecs that leave the branch alone make pull-request refuse, as git push would not push it" {
  feature_repo
  git config remote.origin.push refs/heads/main:refs/heads/main
  run git push --dry-run --porcelain origin
  assert_success
  assert_output_lacks refs/heads/feature # git would push main only
  run hub pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: git push would not push feature: remote.origin.push is configured, and none of its refspecs maps feature; push it yourself (git push origin feature), or name the head with -h [OWNER:]BRANCH."
  assert_equals "$(branches mislav/dotfiles)" "main "
  git config remote.origin.push refs/heads/feature:refs/tags/feature
  run hub pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: remote.origin.push maps feature to something that is not a branch; name the head with -h [OWNER:]BRANCH."
  git config --unset remote.origin.push
  git config branch.feature.pushRemote nowhere
  run hub pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: there is no remote nowhere to push feature to; add one, or name the head with -h [OWNER:]BRANCH."
  assert_equals "$(branches mislav/dotfiles)" "main "
  assert_gh_not_called
}

@test "a remote that pushes to another repository than it fetches from cannot show that the branch is pushed" {
  pushed_repo
  git remote set-url --push origin https://github.com/alice/dotfiles.git
  run hub pull-request -m Fix
  assert_failure
  assert_output_equals "Aborted: origin pushes to alice/dotfiles but fetches from another repository, so hub cannot tell whether feature is pushed there (use -p to push it, or -f to skip this check)."
  stub_gh 'api --hostname github.com users/alice -q .type' 'User'
  run hub --noop pull-request -f -m Fix
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head alice:feature --title Fix --body ''"
  # the same repository under another spelling is the same repository
  git remote set-url --push origin https://github.com/Mislav/DotFiles.git
  run hub --noop pull-request -m Fix
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base main --head feature --title Fix --body ''"
}

@test "-i names the head repository when it is another repository than the base" {
  feature_repo
  serve_github alice/renamed
  git remote add fork https://github.com/alice/renamed.git
  git config branch.feature.pushRemote fork
  run hub --noop pull-request -p -i 12
  assert_success
  assert_output_equals $'git push --set-upstream fork HEAD:refs/heads/feature\ngh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=alice:feature -f head_repo=renamed -f base=main --jq .html_url'
  stub_gh 'api --hostname github.com -X POST repos/mislav/dotfiles/pulls *' 'https://github.com/mislav/dotfiles/pull/12'
  run hub pull-request -p -i 12
  assert_success
  assert_line_equals -1 "https://github.com/mislav/dotfiles/pull/12" # after git's report of the push
  assert_equals "$(server_ref alice/renamed refs/heads/feature)" "$(git rev-parse HEAD)"
  assert_gh_called 'api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=alice:feature -f head_repo=renamed -f base=main --jq .html_url'
  # a renamed repository of the base's own owner, which is where the API insists on the name
  git remote set-url fork https://github.com/mislav/renamed.git
  run hub --noop pull-request -p -i 12
  assert_success
  assert_line_equals 1 "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=mislav:feature -f head_repo=renamed -f base=main --jq .html_url"
  # -h OWNER:BRANCH without -p: no remote here says which repository that is, so none is named
  run hub --noop pull-request -i 12 -h bob:feature
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=bob:feature -f base=main --jq .html_url"
}
