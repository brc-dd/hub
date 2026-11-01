#!/usr/bin/env bats
# hub browse: the repository's URL, the current branch's page, and where the URL goes.

load test_helper

@test "hub browse opens the project's front page on the default branch" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  run hub browse
  assert_success
  assert_output_equals ''
  assert_equals "$(opened)" https://github.com/mislav/dotfiles
  assert_gh_not_called
}

@test "hub browse -- SUBPAGE appends the subpage to the project's URL" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  run hub browse -- issues
  assert_success
  run hub browse -- settings/branches
  assert_success
  assert_equals "$(opened)" $'https://github.com/mislav/dotfiles/issues
https://github.com/mislav/dotfiles/settings/branches'
}

@test "hub browse works from a subdirectory of the work tree" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  mkdir -p lib/deep && cd lib/deep
  run hub browse -- pulls
  assert_success
  assert_equals "$(opened)" https://github.com/mislav/dotfiles/pulls
}

@test "hub browse prefers the upstream remote as the project" {
  make_repo work origin=https://github.com/mislav/proj.git upstream=git@github.com:octo/proj.git
  run hub browse -- issues
  assert_success
  assert_equals "$(opened)" https://github.com/octo/proj/issues
}

@test "hub browse -u prints the URL of OWNER/REPO SUBPAGE without opening it" {
  run hub browse -u cli/cli releases
  assert_success
  assert_output_equals https://github.com/cli/cli/releases
  assert_equals "$(opened)" ''
  assert_gh_not_called
}

@test "hub browse takes HOST/OWNER/REPO and repository URLs" {
  run hub browse -u ghe.example.com/Octo/Proj wiki
  assert_success
  assert_output_equals https://ghe.example.com/Octo/Proj/wiki
  run hub browse -u https://github.com/cli/cli.git
  assert_success
  assert_output_equals https://github.com/cli/cli
  run hub browse -u git@github.com:cli/cli.git pulls
  assert_success
  assert_output_equals https://github.com/cli/cli/pulls
}

@test "hub browse REPO is your login's repository on the default host" {
  run hub browse -u dotfiles
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
  assert_gh_called 'config get user -h github.com'
  export GH_HOST=ghe.example.com
  stub_gh 'config get user -h ghe.example.com' hubot
  run hub browse -u dotfiles.wiki
  assert_success
  assert_output_equals https://ghe.example.com/hubot/dotfiles.wiki
}

@test "hub browse REPO fails when your login is unknown" {
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user --jq .login' '' 1
  run hub browse -u dotfiles
  assert_status 1
  local hint='(run: gh auth login -h github.com)'
  assert_output_equals "hub browse: could not determine your GitHub login for github.com $hint"
}

@test "hub browse tree alone is the front page" {
  run hub browse -u cli/cli tree
  assert_success
  assert_output_equals https://github.com/cli/cli
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  run hub browse -u -- tree
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
  run hub browse -u cli/cli tree/main/lib
  assert_success
  assert_output_equals https://github.com/cli/cli/tree/main/lib
}

@test "hub browse on a pushed branch opens the branch's tree and commits" {
  pushed_feature
  run hub browse
  assert_success
  run hub browse -- tree
  assert_success
  run hub browse -- commits
  assert_success
  assert_equals "$(opened)" $'https://github.com/mislav/dotfiles/tree/feature
https://github.com/mislav/dotfiles/tree/feature
https://github.com/mislav/dotfiles/commits/feature'
  assert_gh_not_called
}

@test "hub browse on a pushed branch keeps other subpages on the project" {
  pushed_feature
  run hub browse -u -- issues
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles/issues
}

@test "hub browse on a branch with unpushed commits still opens the branch" {
  pushed_feature
  git commit -q --allow-empty -m 'not pushed'
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles/tree/feature
}

@test "hub browse on a branch that is not pushed opens the front page or commits" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c feature
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
  run hub browse -u -- commits
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles/commits
}

@test "hub browse on a start-point upstream does not follow the branch" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c fix --track origin/main
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
}

@test "hub browse escapes the branch name in the page" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c 'topic/a#b+c'
  git push -q -u origin 'refs/heads/topic/a#b+c'
  run hub browse -u
  assert_success
  assert_output_equals 'https://github.com/mislav/dotfiles/tree/topic/a%23b%2Bc'
}

@test "hub browse opens the branch in the fork it pushes to" {
  serve_github octo/proj mislav/proj
  clone_served octo/proj
  git remote add mislav https://github.com/mislav/proj.git
  git switch -q -c feature
  git push -q -u mislav refs/heads/feature
  run hub browse -u -- commits
  assert_success
  assert_output_equals https://github.com/mislav/proj/commits/feature
  run hub browse -u -- issues
  assert_success
  assert_output_equals https://github.com/octo/proj/issues
}

# a clone of octo/proj on a branch feature pushed without -u to a remote other (not your fork).
pushed_to_other() {
  serve_github octo/proj other/proj
  clone_served octo/proj
  git remote add other https://github.com/other/proj.git
  git switch -q -c feature
  git push -q other refs/heads/feature:refs/heads/feature
}

@test "hub browse follows branch.NAME.pushRemote" {
  pushed_to_other
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/octo/proj
  git config branch.feature.pushRemote other
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/other/proj/tree/feature
}

@test "hub browse follows remote.pushDefault" {
  pushed_to_other
  git config remote.pushDefault other
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/other/proj/tree/feature
  assert_gh_not_called
}

@test "hub browse follows the push URL when the remote pushes elsewhere" {
  serve_github octo/proj mislav/proj
  clone_served octo/proj
  git remote set-url --push origin https://github.com/mislav/proj.git
  git switch -q -c feature
  git push -q -u origin refs/heads/feature
  git fetch -q https://github.com/mislav/proj.git refs/heads/feature:refs/remotes/origin/feature
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/proj/tree/feature
}

@test "hub browse stays on the project when the push remote is not on GitHub" {
  serve_github mislav/dotfiles
  git init -q --bare "$HUB_TEST_TMP/backup.git"
  clone_served mislav/dotfiles
  git remote add backup "$HUB_TEST_TMP/backup.git"
  git switch -q -c feature
  git push -q -u backup refs/heads/feature
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
}

@test "hub browse follows main when the default branch is unknown" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git remote set-head origin -d
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles/tree/main
  assert_gh_not_called
}

@test "hub browse reads the default branch from the remote HEAD, not main" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c dev
  git push -q -u origin refs/heads/dev
  git remote set-head origin dev
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
  git switch -q main
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles/tree/main
  assert_gh_not_called
}

@test "hub browse reads the default branch from the project remote" {
  serve_github octo/proj mislav/proj
  clone_served mislav/proj
  git remote add upstream https://github.com/octo/proj.git
  git fetch -q upstream
  git remote set-head upstream main
  git remote set-head origin -d
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/octo/proj
  assert_gh_not_called
}

@test "hub browse treats a remote HEAD pointing at a missing branch as unknown" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c gone
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
  git switch -q main
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles/tree/main
  assert_gh_not_called
}

@test "hub browse -- commits on the default branch opens the project's commits" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  run hub browse -u -- commits
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles/commits
  run hub browse -u --
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
  assert_gh_not_called
}

@test "hub browse on an unborn branch opens the front page without git's errors" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  git switch -q -c feature
  git commit -q --allow-empty -m feature
  git push -q origin refs/heads/feature
  cd "$HUB_TEST_TMP"
  git init -q -b feature unborn
  cd unborn
  git remote add origin https://github.com/mislav/dotfiles.git
  git fetch -q origin
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
}

@test "hub browse on a detached HEAD opens the front page" {
  pushed_feature
  git switch -q --detach
  run hub browse -u
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
}

@test "hub browse with a repository operand does not follow the branch" {
  pushed_feature
  run hub browse -u mislav/dotfiles
  assert_success
  assert_output_equals https://github.com/mislav/dotfiles
}

@test "hub browse under GH_REPO opens that repository and does not follow the branch" {
  pushed_feature
  GH_REPO=cli/cli run hub browse -u
  assert_success
  assert_output_equals https://github.com/cli/cli
  cd "$HUB_TEST_TMP"
  GH_REPO=ghe.example.com/octo/proj run hub browse -u -- commits
  assert_success
  assert_output_equals https://ghe.example.com/octo/proj/commits
  GH_REPO=cli/cli.git run hub browse -u
  assert_output_equals https://github.com/cli/cli
  run hub browse -u ghe.example.com/octo/proj.git
  assert_output_equals https://ghe.example.com/octo/proj
}

@test "hub browse -c copies the URL instead of opening it" {
  run hub browse -c cli/cli issues
  assert_success
  assert_output_equals ''
  assert_equals "$(copied)" https://github.com/cli/cli/issues
  assert_equals "$(opened)" ''
}

@test "hub browse -u -c prints and copies the URL" {
  run hub browse -uc cli/cli
  assert_success
  assert_output_equals https://github.com/cli/cli
  assert_equals "$(copied)" https://github.com/cli/cli
  assert_equals "$(opened)" ''
}

@test "hub browse returns the browser's and the clipboard's status" {
  HUB_TEST_BROWSER_STATUS=3 run hub browse cli/cli
  assert_status 3
  assert_equals "$(opened)" https://github.com/cli/cli
  HUB_TEST_CLIPBOARD_STATUS=4 run hub browse -u -c cli/cli
  assert_status 4
  assert_output_equals https://github.com/cli/cli
}

@test "hub browse runs the command line in BROWSER when GH_BROWSER is unset" {
  unset GH_BROWSER
  export BROWSER="$HUB_TEST_ROOT/test/stubs/browser --new-window"
  run hub browse cli/cli
  assert_success
  assert_equals "$(opened)" https://github.com/cli/cli
}

@test "hub browse refuses a project without a GitHub remote" {
  make_repo work origin=https://gitlab.com/mislav/dotfiles.git
  run hub browse
  assert_status 1
  assert_output_equals 'hub browse: no GitHub remote found (looked for upstream, github, origin)'
  cd "$HUB_TEST_TMP"
  run hub browse -- issues
  assert_status 1
  assert_output_equals 'hub browse: no GitHub remote found (looked for upstream, github, origin)'
  GH_REPO=a/b/c/d run hub browse
  assert_status 1
  assert_output_equals \
    'hub browse: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
  assert_equals "$(opened)" ''
}

@test "hub browse refuses a repository it cannot read" {
  local hint='(use REPO, OWNER/REPO, HOST/OWNER/REPO or a URL)'
  run hub browse a/b/c/d
  assert_status 1
  assert_output_equals "hub browse: not a repository: a/b/c/d $hint"
  run hub browse https://gitlab.com/a/b
  assert_status 1
  assert_output_equals "hub browse: not a repository: https://gitlab.com/a/b $hint"
  run hub browse ..
  assert_status 1
  assert_output_equals "hub browse: not a repository: .. $hint"
  run hub browse -
  assert_status 1
  assert_output_equals "hub browse: not a repository: - $hint"
  run hub browse 'a/b?x=1'
  assert_status 1
  assert_output_equals "hub browse: not a repository: a/b?x=1 $hint"
  run hub browse cli/cli/issues
  assert_status 1
  assert_output_equals "hub browse: not a repository: cli/cli/issues $hint"
  assert_equals "$(opened)" ''
  assert_gh_not_called
}

@test "hub browse takes --url and --copy for -u and -c" {
  run hub browse --url cli/cli issues
  assert_success
  assert_output_equals https://github.com/cli/cli/issues
  assert_equals "$(opened)" ''
  run hub browse --copy cli/cli
  assert_success
  assert_output_equals ''
  assert_equals "$(copied)" https://github.com/cli/cli
  assert_equals "$(opened)" ''
}

@test "hub browse refuses unknown options and extra arguments" {
  run hub browse --urls cli/cli
  assert_status 1
  assert_line_equals 0 'hub browse: unknown option: --urls'
  assert_line_equals 1 'Usage: hub browse [-u] [-c] [[[HOST/]OWNER/]REPO | --] [SUBPAGE]'
  run hub browse -ux cli/cli
  assert_line_equals 0 'hub browse: unknown option: -x'
  run hub browse cli/cli issues extra
  assert_status 1
  assert_line_equals 0 'hub browse: unexpected argument: extra'
  run hub browse cli/cli -- issues
  assert_status 1
  assert_line_equals 0 'hub browse: unexpected argument: --'
  run hub browse -- issues extra
  assert_status 1
  assert_line_equals 0 'hub browse: unexpected argument: extra'
  assert_equals "$(opened)" ''
}

@test "hub browse --help and -h print its manual" {
  run hub browse --help
  assert_success
  assert_line_equals 0 'Summary: Open a GitHub repository in the web browser.'
  assert_line_equals 1 'Usage: hub browse [-u] [-c] [[[HOST/]OWNER/]REPO | --] [SUBPAGE]'
  run hub browse -h
  assert_success
  assert_line_equals 0 'Summary: Open a GitHub repository in the web browser.'
  assert_equals "$(opened)" ''
}
