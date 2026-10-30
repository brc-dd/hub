#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test runs in a subshell, so its exports stay local on purpose
load ../test_helper

# feature_repo [REMOTE=URL ...] : a repo on branch "feature" (origin is mislav/dotfiles unless given).
feature_repo() {
  (($#)) || set -- origin=https://github.com/mislav/dotfiles.git
  make_repo dotfiles "$@"
  git checkout -q -b feature
}

# stub_clipboard : a pbcopy that writes to $HUB_TEST_TMP/clipboard (hub tries pbcopy first).
stub_clipboard() {
  mkdir -p "$HUB_TEST_TMP/bin"
  printf '#!/bin/sh\ncat >"%s/clipboard"\n' "$HUB_TEST_TMP" >"$HUB_TEST_TMP/bin/pbcopy"
  chmod +x "$HUB_TEST_TMP/bin/pbcopy"
  export PATH=$HUB_TEST_TMP/bin:$PATH
}

# stub_git_push : a git that records each push in $HUB_TEST_TMP/pushes instead of pushing
# (hub runs the first git in PATH); every other git command runs the real git.
stub_git_push() {
  local real
  real=$(command -v git)
  mkdir -p "$HUB_TEST_TMP/bin"
  cat >"$HUB_TEST_TMP/bin/git" <<STUB
#!/bin/sh
if [ "\$1" = push ]; then echo "git \$*" >>"$HUB_TEST_TMP/pushes"; exit 0; fi
exec "$real" "\$@"
STUB
  chmod +x "$HUB_TEST_TMP/bin/git"
  export PATH=$HUB_TEST_TMP/bin:$PATH
}

# stub_parent HOST/OWNER/REPO PARENT : GitHub reports PARENT (OWNER/REPO, '' for none) as the
# parent of that repository (gh repo view --json parent).
stub_parent() { stub_gh "repo view $1 --json parent *" "$2"; }

# stub_account OWNER TYPE [HOST] : GitHub reports OWNER's account type (User or Organization).
stub_account() { stub_gh "api --hostname ${3:-github.com} users/$1 -q .type" "$2"; }

# stub_fork HOST/OWNER/REPO PARENT [TYPE] : that repository is a fork of PARENT, and its owner a User (or TYPE).
stub_fork() {
  local owner=${1#*/}
  stub_parent "$1" "$2"
  stub_account "${owner%%/*}" "${3:-User}" "${1%%/*}"
}

@test "without a message, gh asks for the title and body" {
  feature_repo
  run hub --noop pull-request
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles"
  assert_gh_not_called
}

@test "-m and -F give the title (the first paragraph) and the body, so gh does not prompt" {
  feature_repo
  run hub --noop pull-request -m "Fix the bug"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body '' --repo github.com/mislav/dotfiles"
  run hub --noop pull-request -m $'Fix the\nbug\n\nIt was broken.' -m "Now it is not."
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body \$'It was broken.\\n\\nNow it is not.' --repo github.com/mislav/dotfiles"
  printf 'Fix the bug\n\nIt was broken.\n' >"$HUB_TEST_TMP/msg.txt"
  run hub --noop pull-request -F "$HUB_TEST_TMP/msg.txt"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body It\\ was\\ broken. --repo github.com/mislav/dotfiles"
  run hub --noop pull-request -F - <<<$'From stdin\n\nBody.'
  assert_success
  assert_output_equals "gh pr create --title From\\ stdin --body Body. --repo github.com/mislav/dotfiles"
}

@test "an unreadable file, an empty title, -m with -F and a missing value abort" {
  feature_repo
  run hub --noop pull-request -F no-such-file
  assert_failure
  assert_output_equals "Aborted: cannot read no-such-file"
  run hub --noop pull-request -m ""
  assert_failure
  assert_output_equals "Aborted: the pull request title is empty."
  run hub --noop pull-request -m Fix -F - <<<"Other"
  assert_failure
  assert_output_equals "Aborted: -m and -F cannot be used together."
  run hub --noop pull-request -b
  assert_failure
  assert_output_equals "Aborted: -b needs a value."
  assert_gh_not_called
}

@test "-e opens gh's editor, filled with any message; --no-edit uses the first commit" {
  feature_repo
  run hub --noop pull-request -e -m "Fix the bug"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body '' --repo github.com/mislav/dotfiles --editor"
  run hub --noop pull-request --edit -m ""
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --editor"
  run hub --noop pull-request --no-edit
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --fill-first"
}

@test "hub's base, head, draft, reviewer, assignee, milestone and label options become gh's" {
  feature_repo
  run hub --noop pull-request -b develop -h mislav:feature -d -r alice,bob -r org/team -a carol -M v1.0 -l bug,ui --no-maintainer-edits
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base develop --head mislav:feature --draft --no-maintainer-edit --reviewer alice,bob --reviewer org/team --assignee carol --milestone v1.0 --label bug,ui"
}

@test "hub's options take long names, attached values and clusters, as gh's do" {
  feature_repo
  local args
  for args in "-m Fix -b develop -h feature -d -r alice -l bug" \
    "--message Fix --base develop --head feature --draft --reviewer alice --labels bug" \
    "--message=Fix --base=develop --head=feature --draft --reviewer=alice --labels=bug" \
    "-mFix -bdevelop -hfeature -d -ralice -lbug" \
    "-m=Fix -b=develop -h=feature -d -r=alice -l=bug" \
    "-dmFix -Bdevelop -H=feature -r alice -l bug"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request $args
    assert_success
    assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --base develop --head feature --draft --reviewer alice --label bug"
  done
  run hub --noop pull-request -F="$HUB_TEST_TMP/no-such-file"
  assert_failure
  assert_output_equals "Aborted: cannot read $HUB_TEST_TMP/no-such-file"
  run hub --noop pull-request --issue=12 -b=main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=feature -f base=main --jq .html_url"
}

@test "gh's -B and -H are hub's -b and -h, and hub's letters keep hub's meaning in a cluster of gh's" {
  feature_repo origin=https://github.com/mislav/dotfiles.git alice=https://github.com/alice/dotfiles.git
  stub_fork github.com/alice/dotfiles mislav/dotfiles
  run hub --noop pull-request -B develop -wH alice:other -m title
  assert_success
  assert_output_equals "gh pr create --title title --body '' --repo github.com/mislav/dotfiles --base develop --head alice:other -w"
  run hub --noop pull-request -wpHalice:other -wmtitle
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --title title --body \'\' --repo github.com/mislav/dotfiles --head alice:other -w -w'
}

@test "options hub doesn't know go to gh with their values, which are never read as hub's" {
  feature_repo
  run hub --noop pull-request --fill -T template.md -w --assignee @me --project=Roadmap --body-file body.md
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --fill -T template.md -w --assignee @me --project Roadmap --body-file body.md"
  run hub --noop pull-request --title -p --body -i -dt -f -T=-h --label -m
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --draft --title -p --body -i -t -f -T -h --label -m"
  run hub --noop pull-request -m Fix --body https://github.com/mislav/dotfiles/issues/12
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --body https://github.com/mislav/dotfiles/issues/12"
  assert_gh_not_called
}

@test "two different heads abort before anything runs" {
  feature_repo
  run hub --noop pull-request -p -h feature -wH alice:other
  assert_failure
  assert_output_equals "Aborted: two different heads: feature and alice:other."
  run hub --noop pull-request -H a --head=b
  assert_failure
  assert_output_equals "Aborted: two different heads: a and b."
  run hub --noop pull-request -h other -wH other
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --head other -w"
  assert_gh_not_called
}

@test "the repository hub resolves is always named for gh, whatever gh's defaults" {
  make_repo repo origin=https://github.com/mislav/repo.git upstream=https://github.com/github/repo.git
  git config remote.origin.gh-resolved base # gh repo set-default mislav/repo; hub's choice is upstream
  export GH_HOST=enterprise.example
  run hub --noop pull-request -m Test
  assert_success
  assert_output_equals "gh pr create --title Test --body '' --repo github.com/github/repo"
  export GH_REPO=cli/cli
  run hub --noop pull-request -m Test
  assert_success
  assert_output_equals "gh pr create --title Test --body '' --repo enterprise.example/cli/cli"
  unset GH_HOST GH_REPO
  git config --global --add hub.host ghe.example.com
  cd "$HUB_TEST_TMP"
  make_repo ghe origin=https://ghe.example.com/mislav/repo.git
  run hub --noop pull-request
  assert_success
  assert_output_equals "gh pr create --repo ghe.example.com/mislav/repo"
  assert_gh_not_called
}

@test "-b OWNER:BRANCH and OWNER/REPO:BRANCH put the base in that repository, on the current host" {
  feature_repo
  export GH_HOST=enterprise.example
  run hub --noop pull-request -m Fix -b alice:develop
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/alice/dotfiles --base develop"
  run hub --noop pull-request -m Fix --base=alice/fork:develop
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/alice/fork --base develop"
  git config --global --add hub.host ghe.example.com
  git remote set-url origin https://ghe.example.com/mislav/dotfiles.git
  run hub --noop pull-request -b alice:develop
  assert_success
  assert_output_equals "gh pr create --repo ghe.example.com/alice/dotfiles --base develop"
  run hub --noop pull-request -b alice:
  assert_failure
  assert_output_equals "Aborted: not a base: alice: (use [OWNER[/REPO]:]BRANCH)"
  run hub --noop pull-request -b alice:develop -R cli/cli
  assert_failure
  assert_output_equals "Aborted: name the base repository once: with -R, -b OWNER[/REPO]:BRANCH or an issue URL."
  assert_gh_not_called
}

@test "-R or --repo, in any spelling, replaces the repository hub would name" {
  feature_repo
  local pair
  for pair in "-R cli/cli=-R cli/cli" "-Rcli/cli=-R cli/cli" "-R=cli/cli=-R cli/cli" "-wR cli/cli=-w -R cli/cli" \
    "--repo=cli/cli=--repo cli/cli" "-R github.com/cli/cli=-R github.com/cli/cli" \
    "--repo ghe.example.com:8443/cli/cli.github.io=--repo ghe.example.com:8443/cli/cli.github.io"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request -m Fix -b develop ${pair%%=-*}
    assert_success
    assert_output_equals "gh pr create --title Fix --body '' --base develop -${pair#*=-}"
  done
}

@test "an empty or malformed -R/--repo aborts before anything runs" {
  feature_repo
  local value
  for value in '' bad bad/ /bad cli/cli/x/y https://github.com/cli/cli "cli/c li" -p; do
    run hub --noop pull-request -p --repo "$value" -m Title
    assert_failure
    assert_output_equals "Aborted: not a repository: '$value' (use --repo [HOST/]OWNER/REPO)"
  done
  for value in -Rbad -R=bad -wR=bad --repo=; do
    run hub --noop pull-request -p "$value" -m Title
    assert_failure
    assert_output_contains "Aborted: not a repository: "
  done
  run hub --noop pull-request -p -m Title -R
  assert_failure
  assert_output_equals "Aborted: -R needs a value."
  assert_gh_not_called
}

@test "without a GitHub remote, pull-request needs -R to know the repository" {
  make_repo repo origin=https://gitlab.com/mislav/repo.git
  run hub --noop pull-request -m Fix
  assert_failure
  assert_output_equals "Aborted: could not find a GitHub remote in this repository (looked for upstream, github, origin)"
  run hub --noop pull-request -m Fix -R mislav/repo
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' -R mislav/repo"
  assert_gh_not_called
}

@test "-p pushes the current branch where git pushes it, and names it as the head" {
  feature_repo origin=https://github.com/mislav/dotfiles.git fork=https://github.com/alice/dotfiles.git upstream=https://github.com/github/dotfiles.git
  stub_fork github.com/alice/dotfiles github/dotfiles
  stub_fork github.com/mislav/dotfiles github/dotfiles
  run hub --noop pull-request -p -m Fix
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh pr create --title Fix --body \'\' --repo github.com/github/dotfiles --head mislav:feature'
  git config remote.pushDefault fork
  run hub --noop pull-request -p
  assert_success
  assert_output_equals $'git push --set-upstream fork HEAD:refs/heads/feature\ngh pr create --repo github.com/github/dotfiles --head alice:feature'
  git config branch.feature.pushRemote upstream
  run hub --noop pull-request --push
  assert_success
  assert_output_equals $'git push --set-upstream upstream HEAD:refs/heads/feature\ngh pr create --repo github.com/github/dotfiles --head feature'
  # The branch name git pushes to (push.default=upstream).
  git config --unset branch.feature.pushRemote
  git config --unset remote.pushDefault
  git config branch.feature.remote origin
  git config branch.feature.merge refs/heads/topic
  git config push.default upstream
  run hub --noop pull-request -p
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/topic\ngh pr create --repo github.com/github/dotfiles --head mislav:topic'
}

@test "-p -h BRANCH pushes HEAD to BRANCH on the push remote, even from a detached HEAD" {
  feature_repo origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  stub_fork github.com/mislav/dotfiles github/dotfiles
  run hub --noop pull-request -p -h other -m title
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --title title --body \'\' --repo github.com/github/dotfiles --head mislav:other'
  git checkout -q --detach
  run hub --noop pull-request -p -h other
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/github/dotfiles --head mislav:other'
  run hub --noop pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: not currently on any branch; name the head with -h [OWNER:]BRANCH."
}

@test "-p -h OWNER:BRANCH pushes to OWNER's remote, the push remote first, then one of the base's name" {
  feature_repo origin=https://github.com/mislav/dotfiles.git backup=git@github.com:mislav/dotfiles.git alice=https://github.com/alice/dotfiles.git
  stub_fork github.com/alice/dotfiles mislav/dotfiles
  stub_account Alice User
  run hub --noop pull-request -p -h alice:other -m title
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --title title --body \'\' --repo github.com/mislav/dotfiles --head alice:other'
  run hub --noop pull-request -p -h Alice:other
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head Alice:other'
  run hub --noop pull-request -p -h mislav:other
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head mislav:other'
  # What a remote pushes to counts, not what it fetches from.
  git remote set-url --push alice https://github.com/bob/dotfiles.git
  run hub --noop pull-request -p -h alice:other
  assert_failure
  assert_output_equals "Aborted: no remote here pushes to a repository of alice's that is mislav/dotfiles, a fork of it or a sibling fork."
  git remote set-url --push origin https://github.com/alice/dotfiles.git
  run hub --noop pull-request -p -h alice:other
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head alice:other'
}

@test "-p -h OWNER:BRANCH checks OWNER's remotes before it chooses one" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/alice/repo.git renamed=https://github.com/alice/renamed.git
  stub_parent github.com/alice/repo ''
  stub_fork github.com/alice/renamed org/repo
  run hub --noop pull-request -p -h alice:topic -m Title
  assert_success
  assert_output_equals $'git push renamed HEAD:refs/heads/topic\ngh pr create --title Title --body \'\' --repo github.com/org/repo --head alice:topic'
  assert_gh_called 'repo view github.com/alice/repo --json parent *'
  stub_parent github.com/alice/renamed ''
  run hub --noop pull-request -p -h alice:topic
  assert_failure
  assert_output_equals "Aborted: no remote here pushes to a repository of alice's that is org/repo, a fork of it or a sibling fork."
  stub_gh 'repo view github.com/alice/repo --json parent *' '' 1
  run hub --noop pull-request -p -h alice:topic
  assert_failure
  assert_output_equals "Aborted: could not look up github.com/alice/repo."
}

@test "-p -h OWNER:BRANCH with -R or -b OWNER/REPO:BRANCH pushes to OWNER's fork of that repository" {
  feature_repo origin=https://github.com/mislav/dotfiles.git bob=https://github.com/bob/dotfiles.git bob-b=https://github.com/bob/b.git
  stub_fork github.com/bob/b other/b
  stub_fork github.com/bob/dotfiles mislav/dotfiles
  run hub --noop pull-request -R github.com/other/b -p -h bob:feature -m Title
  assert_success
  assert_output_equals $'git push bob-b HEAD:refs/heads/feature\ngh pr create --title Title --body \'\' --head bob:feature -R github.com/other/b'
  run hub --noop pull-request -b other/b:main -p -h bob:feature
  assert_success
  assert_output_equals $'git push bob-b HEAD:refs/heads/feature\ngh pr create --repo github.com/other/b --base main --head bob:feature'
}

@test "the head is in the repository the push remote pushes to, not the one it fetches from" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/alice/repo.git
  git remote set-url --push origin https://github.com/bob/repo.git
  stub_fork github.com/bob/repo org/repo
  stub_fork github.com/carol/repo org/repo
  run hub --noop pull-request -p -m Title
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh pr create --title Title --body \'\' --repo github.com/org/repo --head bob:feature'
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --repo github.com/org/repo --head bob:feature"
  # The push URL as git rewrites it (pushInsteadOf).
  git config --unset-all remote.origin.pushurl
  git config url.https://github.com/carol/.pushInsteadOf https://github.com/alice/
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --repo github.com/org/repo --head carol:feature"
  # A push URL in the base itself needs no lookup.
  git config --unset url.https://github.com/carol/.pushInsteadOf
  git remote set-url --push origin git@github.com:Org/Repo.git
  : >"$HUB_TEST_LOG"
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --repo github.com/org/repo --head feature"
  assert_gh_not_called
}

@test "a fork of the base, under any name, or a sibling fork is in the base's network" {
  feature_repo upstream=https://github.com/bob/repo.git origin=https://github.com/alice/repo-fork.git
  stub_fork github.com/alice/repo-fork bob/repo
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --repo github.com/bob/repo --head alice:feature"
  [[ $(gh_calls) != *'repo view github.com/bob/repo '* ]] # a fork of the base needs no lookup of the base
  stub_fork github.com/alice/repo-fork org/repo
  stub_parent github.com/bob/repo org/repo
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --repo github.com/bob/repo --head alice:feature"
  assert_gh_called 'repo view github.com/bob/repo --json parent *'
}

@test "a push repository outside the base's network aborts before anything runs" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/alice/repo.git
  stub_parent github.com/alice/repo bob/repo
  stub_parent github.com/org/repo carol/repo
  local refused="Aborted: remote origin pushes to alice/repo, which is not org/repo, a fork of it or a sibling fork." args
  for args in "-p -m Title" "-p -h topic" "-f" "--dry-run" "-i 12 -b main"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request $args
    assert_failure
    assert_output_equals "$refused"
  done
  stub_parent github.com/alice/repo ''
  run hub --noop pull-request -p
  assert_failure
  assert_output_equals "$refused"
  stub_gh 'repo view github.com/alice/repo --json parent *' '' 1
  run hub --noop pull-request -p
  assert_failure
  assert_output_equals "Aborted: could not look up github.com/alice/repo."
  [[ $(gh_calls) != *users/* ]]
}

@test "push URLs that name no single repository on the base's host abort wherever hub needs the head" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/alice/repo.git
  # refused : -p and -f abort before anything runs.
  refused() {
    local args
    for args in "-p -m Title" "-f"; do
      # shellcheck disable=SC2086  # split on purpose
      run hub --noop pull-request $args
      assert_failure
      assert_output_equals "Aborted: remote origin must push to one repository on github.com (git remote get-url --push --all origin)."
    done
  }
  git remote set-url --add --push origin https://github.com/alice/repo.git
  git remote set-url --add --push origin https://bob:s3cret@github.com/bob/repo.git
  refused # two repositories (and no credentials shown)
  git config --unset-all remote.origin.pushurl
  git config url./srv/mirror/.pushInsteadOf https://github.com/alice/
  refused # a mirror, as git rewrites the push URL
  git config --unset url./srv/mirror/.pushInsteadOf
  git remote set-url --add --push origin https://github.com/alice/repo.git
  git remote set-url --add --push origin "$HUB_TEST_TMP/backup.git"
  refused # a local backup beside the GitHub repository
  git config --unset-all remote.origin.pushurl
  git remote set-url --push origin https://gitlab.com/alice/repo.git
  refused # another host
  # Where hub neither pushes nor names the head, the push URL is gh's business.
  run hub --noop pull-request -m Title
  assert_success
  assert_output_equals "gh pr create --title Title --body '' --repo github.com/org/repo"
  run hub --noop pull-request --dry-run -h alice:feature
  assert_success
  assert_output_equals "gh pr create --repo github.com/org/repo --head alice:feature --dry-run"
  git config branch.feature.pushRemote mine
  run hub --noop pull-request -p
  assert_failure
  assert_output_equals "Aborted: remote mine must push to one repository on github.com (git remote get-url --push --all mine)."
  assert_gh_not_called
}

@test "the base's host decides, compared without case or port, and is the one gh is asked about" {
  git config --global --add hub.host ghe.example.com
  feature_repo origin=https://ghe.example.com/org/dotfiles.git fork=ssh://git@GHE.example.com:2222/mislav/dotfiles.git other=https://github.com/mislav/dotfiles.git
  git config remote.pushDefault fork
  stub_fork ghe.example.com:8443/mislav/dotfiles org/dotfiles
  run hub --noop pull-request -R ghe.example.com:8443/org/dotfiles -p -m Title
  assert_success
  assert_output_equals $'git push --set-upstream fork HEAD:refs/heads/feature\ngh pr create --title Title --body \'\' --head mislav:feature -R ghe.example.com:8443/org/dotfiles'
  assert_gh_called 'api --hostname ghe.example.com:8443 users/mislav -q .type'
  git config remote.pushDefault other
  run hub --noop pull-request -p -m Title
  assert_failure
  assert_output_equals "Aborted: remote other must push to one repository on ghe.example.com (git remote get-url --push --all other)."
  export GH_HOST=ghe.example.com # -R without a host is on gh's default host, as gh reads it
  run hub --noop pull-request -R org/dotfiles -p -m Title
  assert_failure
  assert_output_equals "Aborted: remote other must push to one repository on ghe.example.com (git remote get-url --push --all other)."
}

@test "a head owned by an organization aborts before anything runs, except with -i" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/acme/repo.git
  stub_fork github.com/acme/repo org/repo Organization
  local refused="Aborted: gh pr create cannot take a head owned by an organization (acme:feature); use gh api repos/org/repo/pulls." args
  for args in "-p -m Title" "-p -h feature" "-p -h acme:feature" "-f" "--dry-run"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request $args
    assert_failure
    assert_output_equals "$refused"
  done
  run hub --noop pull-request -p -i 12 -b main
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh api --hostname github.com repos/org/repo/pulls -F issue=12 -F head=acme:feature -f base=main --jq .html_url'
  stub_gh 'api --hostname github.com users/acme *' '' 1
  run hub --noop pull-request -f
  assert_failure
  assert_output_equals "Aborted: could not look up acme on github.com."
}

@test "-f names the head as it is on GitHub, so gh neither pushes nor forks" {
  feature_repo
  stub_fork github.com/mislav/dotfiles github/dotfiles
  run hub --noop pull-request -f -m Fix
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --head feature"
  run hub --noop pull-request -f -b github:main
  assert_success
  assert_output_equals "gh pr create --repo github.com/github/dotfiles --base main --head mislav:feature"
  run hub --noop pull-request -f -R github/dotfiles
  assert_success
  assert_output_equals "gh pr create --head mislav:feature -R github/dotfiles"
  run hub --noop pull-request -f -h other
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --head other"
  run hub --noop pull-request -pf
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh pr create --repo github.com/mislav/dotfiles --head feature'
}

@test "--dry-run never pushes: hub prints the push, and gh creates nothing to open" {
  feature_repo
  stub_git_push
  stub_gh 'pr create *' 'Would have created a pull request'
  export BROWSER='echo browse'
  run hub pull-request -o -p --dry-run -m Fix
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\nWould have created a pull request'
  assert_gh_called 'pr create --title Fix --body  --repo github.com/mislav/dotfiles --head feature --dry-run'
  run hub pull-request -p --dry-run=wat -m Fix
  assert_failure
  assert_output_equals "Aborted: not a boolean: --dry-run=wat"
  [[ ! -e $HUB_TEST_TMP/pushes ]]
  run hub pull-request -p --dry-run=false -m Fix
  assert_success
  [[ $(cat "$HUB_TEST_TMP/pushes") == "git push --set-upstream origin HEAD:refs/heads/feature" ]]
}

@test "--dry-run=VALUE takes Go's spellings of true and false only" {
  make_repo repo origin=https://github.com/mislav/repo.git
  local value
  for value in True 1 t T TRUE true; do
    run hub --noop pull-request "--dry-run=$value" -m Test
    assert_success
    assert_output_equals "gh pr create --title Test --body '' --repo github.com/mislav/repo --head main --dry-run=$value"
  done
  for value in 0 f F FALSE false False; do
    run hub --noop pull-request "--dry-run=$value" -m Test
    assert_success
    assert_output_equals "gh pr create --title Test --body '' --repo github.com/mislav/repo --dry-run=$value"
  done
  for value in wat '' yes; do
    run hub --noop pull-request -p "--dry-run=$value" -m Test
    assert_failure
    assert_output_equals "Aborted: not a boolean: --dry-run=$value"
  done
  assert_gh_not_called
}

@test "--dry-run names the head for gh, unless -h or -H does, and needs one on a detached HEAD" {
  make_repo repo origin=https://github.com/mislav/repo.git
  stub_fork github.com/mislav/repo other/repo
  run hub --noop pull-request --dry-run=true -b other:main -m Test --
  assert_success
  assert_output_equals "gh pr create --title Test --body '' --repo github.com/other/repo --base main --head mislav:main --dry-run=true --"
  run hub --noop pull-request -wHtopic --dry-run
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/repo --head topic -w --dry-run"
  git checkout -q --detach
  run hub --noop pull-request --dry-run -m Test
  assert_failure
  assert_output_equals "Aborted: not currently on any branch; name the head with -h [OWNER:]BRANCH."
  run hub --noop pull-request --dry-run -h mislav:topic
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/repo --head mislav:topic --dry-run"
}

@test "-o prints the new pull request's URL and opens it; -c copies it" {
  feature_repo
  stub_clipboard
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/7'
  export BROWSER='echo browse'
  run hub pull-request -o -c -m Fix
  assert_success
  assert_output_equals $'https://github.com/mislav/dotfiles/pull/7\nbrowse https://github.com/mislav/dotfiles/pull/7'
  [[ $(cat "$HUB_TEST_TMP/clipboard") == "https://github.com/mislav/dotfiles/pull/7" ]]
  assert_gh_called 'pr create --title Fix --body  --repo github.com/mislav/dotfiles'
  run hub --noop pull-request -o -c -m Fix
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles"
  stub_gh 'pr create *' '' 1
  run hub pull-request -o -m Fix
  assert_failure
  [[ $output != *browse* ]]
  stub_gh 'api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 *' 'https://github.com/mislav/dotfiles/pull/12'
  run hub pull-request -i 12 -b main -o
  assert_success
  assert_output_equals $'https://github.com/mislav/dotfiles/pull/12\nbrowse https://github.com/mislav/dotfiles/pull/12'
}

@test "-i N converts the issue in hub's repository, on its host, through the REST API" {
  feature_repo
  export GH_HOST=enterprise.example
  run hub --noop pull-request -i 12 -b develop
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=feature -f base=develop --jq .html_url"
  set_remote_head origin trunk
  run hub --noop pull-request --issue '#12'
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=feature -f base=trunk --jq .html_url"
  assert_gh_not_called
}

@test "an issue URL converts that issue in its own repository, onto its default branch" {
  feature_repo
  set_remote_head origin develop
  stub_parent github.com/mislav/dotfiles github/dotfiles
  stub_gh 'repo view github.com/github/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request https://github.com/Mislav/Dotfiles/issues/12
  assert_success
  assert_output_equals "gh api --hostname github.com repos/Mislav/Dotfiles/pulls -F issue=12 -F head=feature -f base=develop --jq .html_url"
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/dotfiles/pulls -F issue=3 -F head=mislav:feature -f base=trunk --jq .html_url"
  [[ $(gh_calls) != *users/* ]] # the REST API takes any owner's head
  stub_gh 'repo view github.com/github/dotfiles --json defaultBranchRef *' '' 1
  run hub --noop pull-request -p -i https://github.com/github/dotfiles/issues/3
  assert_failure
  assert_output_equals "Aborted: could not look up the default branch of github/dotfiles; give the base with -b BRANCH."
}

@test "an Enterprise issue URL goes to its own host, whatever gh's default host" {
  git config --global --add hub.host ghe.example.com
  feature_repo origin=https://ghe.example.com/mislav/dotfiles.git
  export GH_HOST=enterprise.example
  stub_parent ghe.example.com/mislav/dotfiles github/dotfiles
  stub_gh 'repo view ghe.example.com/github/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request -i https://ghe.example.com/github/dotfiles/issues/3
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com repos/github/dotfiles/pulls -F issue=3 -F head=mislav:feature -f base=trunk --jq .html_url"
}

@test "-i takes -p, -h, -d and --no-maintainer-edits" {
  feature_repo
  run hub --noop pull-request -p -d --no-maintainer-edits -i 12 -b main
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD:refs/heads/feature\ngh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=feature -f base=main -F draft=true -F maintainer_can_modify=false --jq .html_url'
  run hub --noop pull-request -i 12 -b main -h someone:topic
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=someone:topic -f base=main --jq .html_url"
  assert_gh_not_called
}

@test "-i rejects what doesn't apply to an existing issue" {
  feature_repo
  local args
  for args in "-m Fix" "-e" "-r alice" "-l bug" "--fill" "-R cli/cli"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request -i 12 $args
    assert_failure
    assert_output_equals "Aborted: -i keeps the issue's title and body, and takes only -b, -h, -p, -f, -d, --no-maintainer-edits, -o and -c."
  done
  run hub --noop pull-request -i twelve
  assert_failure
  assert_output_equals "Aborted: not an issue number or URL: twelve"
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3 -b alice:main
  assert_failure
  assert_output_equals "Aborted: name the base repository once: with -R, -b OWNER[/REPO]:BRANCH or an issue URL."
  assert_gh_not_called
}

@test "--help and a bare -h print the manual" {
  run hub pull-request --help
  assert_success
  assert_output_contains "Usage: hub pull-request"
  run hub pull-request -h
  assert_success
  assert_output_contains "Usage: hub pull-request"
  run hub help pull-request
  assert_success
  assert_output_contains "-i, --issue ISSUE"
}

@test "pull-request outside a repository aborts" {
  run hub --noop pull-request -m Fix
  assert_failure
  assert_output_contains "fatal: not a git repository"
  assert_gh_not_called
}
