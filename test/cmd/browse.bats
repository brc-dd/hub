#!/usr/bin/env bats
load ../test_helper

assert_status() { [[ $status -eq $1 ]] || {
  printf 'expected exit %s, got %s\noutput:\n%s\n' "$1" "$status" "$output"
  return 1
}; }

# failing_tools : a clipboard tool and a browser, first in PATH, that fail with their own statuses.
failing_tools() {
  mkdir -p "$HUB_TEST_TMP/failing"
  printf '#!/usr/bin/env bash\ncat >/dev/null\necho "clipboard failed" >&2\nexit 17\n' >"$HUB_TEST_TMP/failing/pbcopy"
  printf '#!/usr/bin/env bash\necho "browser failed: $1" >&2\nexit 19\n' >"$HUB_TEST_TMP/failing/browser"
  chmod +x "$HUB_TEST_TMP/failing/pbcopy" "$HUB_TEST_TMP/failing/browser"
  export PATH=$HUB_TEST_TMP/failing:$PATH GH_BROWSER=$HUB_TEST_TMP/failing/browser
}

@test "browse opens the current repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles"
  assert_gh_not_called
}

@test "browse prefers the upstream remote" {
  make_repo dotfiles origin=git@github.com:mislav/dotfiles.git upstream=https://github.com/dotcom/dotfiles.git
  set_remote_head upstream main
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles"
}

@test "browse on a branch other than the default opens its tree" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature/x # no upstream: git cannot say where it pushes, so the current repository
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature/x"
  assert_gh_not_called
}

@test "browse uses the default branch reported by the remote HEAD" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin trunk
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/main"
  git checkout -q -b trunk
  run hub --noop browse
  assert_output_equals "open https://github.com/mislav/dotfiles"
  assert_gh_not_called
}

@test "browse asks gh for the default branch only when the remote HEAD is unknown" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'main'
  git checkout -q -b feature
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  assert_equals "$(gh_calls)" "gh repo view github.com/mislav/dotfiles --json defaultBranchRef -q .defaultBranchRef.name"
  # a remote HEAD that points at a branch makes the lookup local
  set_remote_head origin main
  : >"$HUB_TEST_LOG"
  run hub --noop browse
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  assert_gh_not_called
  # pages that do not depend on the branch never look it up
  git update-ref -d refs/remotes/origin/main # origin/HEAD dangles again
  run hub --noop browse -- issues
  assert_output_equals "open https://github.com/mislav/dotfiles/issues"
  run hub --noop browse -- tree/main/lib
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/main/lib"
  assert_gh_not_called
  # when gh cannot answer, main is assumed
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef *' '' 1
  git checkout -q main
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles"
  assert_gh_called 'repo view github.com/mislav/dotfiles --json defaultBranchRef *'
}

@test "browse opens a branch that pushes to a fork in the fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote mislav
  git config branch.feature.merge refs/heads/feature
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  # remote.pushDefault sends every branch to the fork, however it was started
  git checkout -q -b topic --track origin/main
  git config remote.pushDefault mislav
  run hub --noop browse
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/topic"
  assert_gh_not_called
}

@test "browse opens a branch where the sole remote sends it, whatever that remote is called" {
  make_repo dotfiles mislav=git@github.com:mislav/dotfiles.git
  set_remote_head mislav main
  git checkout -q -b feature
  git config push.default current
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  git config remote.mislav.push refs/heads/feature:refs/heads/renamed
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/renamed"
  assert_gh_not_called
}

@test "browse opens a branch in the repository its remote pushes to, not the one it fetches from" {
  make_repo repo origin=https://github.com/org/repo.git
  git remote set-url --push origin https://github.com/alice/renamed.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  git branch -q --set-upstream-to=origin/feature
  run hub browse -u
  assert_success
  assert_output_equals "https://github.com/alice/renamed/tree/feature"
  run hub browse -u -- commits
  assert_output_equals "https://github.com/alice/renamed/commits/feature"
  run hub browse -u -- issues # pages that do not follow the branch stay in the current repository
  assert_output_equals "https://github.com/org/repo/issues"
  assert_gh_not_called
}

@test "browse keeps the name of a fork that is not called like the repository" {
  make_repo repo origin=https://github.com/org/repo.git fork=https://github.com/org/renamed.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/fork/feature HEAD
  git branch -q --set-upstream-to=fork/feature
  run hub browse -u
  assert_success
  assert_output_equals "https://github.com/org/renamed/tree/feature"
  # the push destination's host counts too
  git config --global hub.host ghe.example.com
  git remote set-url fork https://ghe.example.com/org/renamed.git
  run hub browse -u
  assert_output_equals "https://ghe.example.com/org/renamed/tree/feature"
  assert_gh_not_called
}

@test "browse opens the branch under the name it has on the remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b local-name
  git config remote.origin.push refs/heads/local-name:refs/heads/published
  run hub browse -u
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/tree/published"
  run hub browse -u -- commits
  assert_output_equals "https://github.com/mislav/dotfiles/commits/published"
}

@test "browse on a branch that pushes outside GitHub opens the current repository without the branch" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git backup=../backup.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote backup
  git config branch.feature.merge refs/heads/feature
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles"
  run hub --noop browse -- commits
  assert_output_equals "open https://github.com/mislav/dotfiles/commits"
  run hub --noop browse -- tree
  assert_output_equals "open https://github.com/mislav/dotfiles"
  run hub --noop browse -- pulls
  assert_output_equals "open https://github.com/mislav/dotfiles/pulls"
  assert_gh_not_called
}

@test "browse -- commits and -- tree follow a branch other than the default" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feat
  run hub --noop browse -- commits
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/commits/feat"
  run hub --noop browse -- tree
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feat"
  git checkout -q -b 'fix#12'
  run hub browse -u -- commits
  assert_output_equals "https://github.com/mislav/dotfiles/commits/fix%2312"
  assert_gh_not_called
}

@test "browse -- commits and -- tree on the default branch open the history and the front page" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub --noop browse -- commits
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/commits"
  run hub --noop browse -- tree
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles"
}

@test "browse -- commits and -- tree open a branch that pushes to a fork in the fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote mislav
  git config branch.feature.merge refs/heads/feature
  run hub --noop browse -- commits
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/commits/feature"
  run hub --noop browse -- tree
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  run hub --noop browse -- issues
  assert_output_equals "open https://github.com/dotcom/dotfiles/issues"
}

@test "browse REPO tree, and tree with GH_REPO, open the front page" {
  run hub --noop browse cli/cli tree
  assert_success
  assert_output_equals "open https://github.com/cli/cli"
  run hub --noop browse cli/cli commits
  assert_output_equals "open https://github.com/cli/cli/commits"
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git checkout -q -b feature
  GH_REPO=cli/cli run hub --noop browse -- tree
  assert_output_equals "open https://github.com/cli/cli"
  GH_REPO=cli/cli run hub --noop browse -- commits
  assert_output_equals "open https://github.com/cli/cli/commits"
  assert_gh_not_called
}

@test "browse escapes branch names" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b 'fix#12+more'
  run hub browse -u
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/tree/fix%2312%2Bmore"
}

@test "browse -- SUBPAGE opens a page of the current repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  run hub --noop browse -- issues
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/issues"
  run hub --noop browse -- tree/main/lib
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/main/lib"
  run hub --noop browse --
  assert_output_equals "open https://github.com/mislav/dotfiles/tree/feature"
  assert_gh_not_called
}

@test "browse OWNER/REPO SUBPAGE works outside a repository" {
  run hub --noop browse cli/cli releases
  assert_success
  assert_output_equals "open https://github.com/cli/cli/releases"
  run hub --noop browse cli/cli
  assert_output_equals "open https://github.com/cli/cli"
  run hub --noop browse https://github.com/cli/cli.git issues
  assert_output_equals "open https://github.com/cli/cli/issues"
  assert_gh_not_called
}

@test "browse REPO means your own repository" {
  run hub --noop browse dotfiles wiki
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
  assert_gh_called 'config get user -h github.com'
}

@test "browse -u prints the URL instead of opening it" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub browse -u -- pulls
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/pulls"
  run hub browse --url
  assert_output_equals "https://github.com/mislav/dotfiles"
}

@test "browse -c copies the URL instead of opening it" {
  run hub --noop browse -c cli/cli actions
  assert_success
  assert_output_equals "copy to clipboard: https://github.com/cli/cli/actions"
  run hub --noop browse --copy cli/cli
  assert_output_equals "copy to clipboard: https://github.com/cli/cli"
}

@test "browse -u and -c combine, separately or clustered" {
  run hub --noop browse -u -c cli/cli
  assert_success
  assert_output_equals $'https://github.com/cli/cli\ncopy to clipboard: https://github.com/cli/cli'
  run hub --noop browse -uc cli/cli
  assert_success
  assert_output_equals $'https://github.com/cli/cli\ncopy to clipboard: https://github.com/cli/cli'
  run hub --noop browse -cu cli/cli actions
  assert_output_equals $'https://github.com/cli/cli/actions\ncopy to clipboard: https://github.com/cli/cli/actions'
  run hub browse -ux cli/cli
  assert_failure
  assert_output_contains "unknown option: -x"
  run hub browse --url=yes cli/cli
  assert_failure
  assert_output_contains "unknown option: --url=yes"
}

@test "browse opens URLs with BROWSER" {
  export BROWSER="printf 'BROWSER %s\n'"
  run hub browse cli/cli
  assert_success
  assert_output_equals "BROWSER https://github.com/cli/cli"
}

@test "browse exits with the status of a browser or clipboard tool that fails" {
  make_repo repo origin=https://github.com/alice/repo.git
  set_remote_head origin main
  failing_tools
  run hub browse
  assert_status 19
  assert_output_equals "browser failed: https://github.com/alice/repo"
  run hub browse -c
  assert_status 17
  assert_output_equals "clipboard failed"
  run hub browse -uc # the URL is printed, then the copy fails
  assert_status 17
  assert_output_equals $'https://github.com/alice/repo\nclipboard failed'
  run hub browse -u # nothing to fail
  assert_success
  assert_output_equals "https://github.com/alice/repo"
}

@test "browse uses the enterprise host of the remote" {
  make_repo app origin=git@ghe.example.com:corp/app.git
  set_remote_head origin main
  run hub --noop browse
  assert_failure
  assert_output_contains "could not find a GitHub remote"
  export GH_HOST=ghe.example.com
  run hub --noop browse -- settings
  assert_success
  assert_output_equals "open https://ghe.example.com/corp/app/settings"
}

@test "browse OWNER/REPO uses GH_HOST, and HOST/OWNER/REPO names the host" {
  GH_HOST=ghe.example.com run hub --noop browse corp/app pulls
  assert_success
  assert_output_equals "open https://ghe.example.com/corp/app/pulls"
  stub_gh 'config get user -h ghe.example.com' 'mona'
  GH_HOST=ghe.example.com run hub --noop browse app
  assert_output_equals "open https://ghe.example.com/mona/app"
  run hub --noop browse ghe.example.com/corp/app issues
  assert_output_equals "open https://ghe.example.com/corp/app/issues"
}

@test "browse honors GH_REPO and does not guess a branch for it" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git checkout -q -b feature
  GH_REPO=cli/cli run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/cli/cli"
  assert_gh_not_called
}

@test "browse in a REPO.wiki repository opens the wiki" {
  make_repo dotfiles.wiki origin=git@github.com:mislav/dotfiles.wiki.git
  set_remote_head origin main
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
  run hub --noop browse -- commits
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki/_history"
  run hub --noop browse -- pages
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki/_pages"
  run hub --noop browse -- wiki
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
  run hub --noop browse -- tree
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
  assert_gh_not_called
}

@test "browse in a wiki ignores the branch you are on" {
  make_repo dotfiles.wiki origin=https://github.com/mislav/dotfiles.wiki.git
  git checkout -q -b feature
  run hub --noop browse
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
  run hub --noop browse -- commits
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki/_history"
  run hub --noop browse -- tree
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
  assert_gh_not_called # no default-branch lookup either
}

@test "browse OWNER/REPO.wiki and GH_REPO=OWNER/REPO.wiki open the wiki" {
  run hub --noop browse cli/cli.wiki
  assert_success
  assert_output_equals "open https://github.com/cli/cli/wiki"
  run hub --noop browse cli/cli.wiki commits
  assert_output_equals "open https://github.com/cli/cli/wiki/_history"
  run hub --noop browse ghe.example.com/corp/app.wiki pages
  assert_output_equals "open https://ghe.example.com/corp/app/wiki/_pages"
  GH_REPO=cli/cli.wiki run hub browse -u -- commits
  assert_output_equals "https://github.com/cli/cli/wiki/_history"
  assert_gh_not_called
  run hub --noop browse dotfiles.wiki
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki"
}

@test "browse outside a GitHub repository fails" {
  make_repo local-only
  run hub --noop browse
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
}

@test "browse rejects unknown options, extra arguments and names that are not repositories" {
  run hub browse --bogus
  assert_failure
  assert_output_equals $'hub browse: unknown option: --bogus\nUsage: hub browse [-u] [-c] [[OWNER/]REPO | --] [SUBPAGE]'
  run hub browse a/b c d
  assert_failure
  assert_output_contains "hub browse: too many arguments"
  run hub browse -- issues more
  assert_failure
  assert_output_contains "hub browse: too many arguments"
  run hub browse o/r/
  assert_failure
  assert_output_contains "hub browse: not a repository: o/r/"
  run hub browse 'two words'
  assert_failure
  assert_output_contains "hub browse: not a repository name: two words"
  assert_gh_not_called
}

@test "browse --help prints the manual" {
  run hub browse --help
  assert_success
  assert_output_contains "Usage: hub browse [-u] [-c]"
  assert_output_contains "hub asks gh for it"
  run hub browse -h
  assert_success
  assert_output_contains "Usage: hub browse [-u] [-c]"
}
