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
  cat >"$HUB_TEST_TMP/bin/git" <<EOF
#!/bin/sh
if [ "\$1" = push ]; then echo "git \$*" >>"$HUB_TEST_TMP/pushes"; exit 0; fi
exec "$real" "\$@"
EOF
  chmod +x "$HUB_TEST_TMP/bin/git"
  export PATH=$HUB_TEST_TMP/bin:$PATH
}

@test "pull-request with no message lets gh prompt" {
  feature_repo
  run hub --noop pull-request
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles"
  assert_gh_not_called
}

@test "-m gives the title and an empty body, so gh does not prompt" {
  feature_repo
  run hub --noop pull-request -m "Fix the bug"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body '' --repo github.com/mislav/dotfiles"
}

@test "-m splits the first paragraph into the title and the rest into the body" {
  feature_repo
  run hub --noop pull-request -m $'Fix the\nbug\n\nIt was broken.\nNow it is not.\n'
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body \$'It was broken.\\nNow it is not.' --repo github.com/mislav/dotfiles"
}

@test "repeated -m are joined as paragraphs" {
  feature_repo
  run hub --noop pull-request -m "Fix the bug" -m "It was broken." -m "Now it is not."
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body \$'It was broken.\\n\\nNow it is not.' --repo github.com/mislav/dotfiles"
}

@test "-F reads the title and body from a file" {
  feature_repo
  printf 'Fix the bug\n\nIt was broken.\n' >"$HUB_TEST_TMP/msg.txt"
  run hub --noop pull-request -F "$HUB_TEST_TMP/msg.txt"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body It\\ was\\ broken. --repo github.com/mislav/dotfiles"
  run hub --noop pull-request -F <(printf 'From a pipe\n')
  assert_success
  assert_output_equals "gh pr create --title From\\ a\\ pipe --body '' --repo github.com/mislav/dotfiles"
}

@test "-F - reads the title and body from stdin" {
  feature_repo
  run hub --noop pull-request -F - <<<$'Fix the bug\n\nIt was broken.'
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body It\\ was\\ broken. --repo github.com/mislav/dotfiles"
}

@test "unreadable files, empty titles and -m with -F abort" {
  feature_repo
  run hub --noop pull-request -F no-such-file
  assert_failure
  assert_output_contains "Aborted: cannot read no-such-file"
  run hub --noop pull-request -m ""
  assert_failure
  assert_output_contains "Aborted: the pull request title is empty."
  run hub --noop pull-request -m Fix -F - <<<"Other"
  assert_failure
  assert_output_contains "Aborted: -m and -F cannot be used together."
  run hub --noop pull-request -b
  assert_failure
  assert_output_contains "Aborted: -b needs a value."
}

@test "-e opens gh's editor, pre-filled with any message" {
  feature_repo
  run hub --noop pull-request -e -m "Fix the bug"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body '' --editor --repo github.com/mislav/dotfiles"
  run hub --noop pull-request --edit
  assert_success
  assert_output_equals "gh pr create --editor --repo github.com/mislav/dotfiles"
}

@test "--no-edit uses the first commit's message" {
  feature_repo
  run hub --noop pull-request --no-edit
  assert_success
  assert_output_equals "gh pr create --fill-first --repo github.com/mislav/dotfiles"
}

@test "hub's base, head, draft, reviewer, assignee, milestone and label options become gh's" {
  feature_repo
  run hub --noop pull-request -b develop -h mislav:feature -d -r alice,bob -r org/team -a carol -M v1.0 -l bug,ui --no-maintainer-edits
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base develop --head mislav:feature --draft --reviewer alice,bob --reviewer org/team --assignee carol --milestone v1.0 --label bug,ui --no-maintainer-edit"
}

@test "long options, --opt=value and bundled short options are understood" {
  feature_repo
  run hub --noop pull-request --message="Fix it" --base=develop --head=feature --reviewer=alice --assign=carol --milestone=v1.0 --labels=bug --draft
  assert_success
  assert_output_equals "gh pr create --title Fix\\ it --body '' --repo github.com/mislav/dotfiles --base develop --head feature --draft --reviewer alice --assignee carol --milestone v1.0 --label bug"
  run hub --noop pull-request -dmFix -bdevelop
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --base develop --draft"
}

@test "options hub doesn't know are passed to gh unchanged" {
  feature_repo
  run hub --noop pull-request --fill -T template.md -R cli/cli --dry-run -w
  assert_success
  assert_output_equals "gh pr create --head mislav:feature --fill -T template.md -R cli/cli --dry-run -w"
  run hub --noop pull-request -m Fix --assignee @me --project=Roadmap
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --assignee @me --project=Roadmap"
}

@test "gh's -B and -H are hub's -b and -h" {
  feature_repo
  run hub --noop pull-request -B develop -H mislav:feature
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base develop --head mislav:feature"
  run hub --noop pull-request -Bdevelop -Hfeature
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --base develop --head feature"
}

@test "gh's -H inside a cluster of gh's options is hub's -h, so -p pushes to that head" {
  feature_repo origin=https://github.com/mislav/dotfiles.git alice=https://github.com/alice/dotfiles.git
  run hub --noop pull-request -p -wH alice:other -m title
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --title title --body \'\' --repo github.com/mislav/dotfiles --head alice:other -w'
  run hub --noop pull-request -p -wHalice:other -m title
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --title title --body \'\' --repo github.com/mislav/dotfiles --head alice:other -w'
  run hub --noop pull-request -p -wH=alice:other
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head alice:other -w'
  run hub --noop pull-request -dwH other -p
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head other --draft -w'
  run hub --noop pull-request -f -wH other
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --head other -w"
  run hub --noop pull-request -m title -wH
  assert_failure
  assert_output_equals "Aborted: -H needs a value."
}

@test "two different heads abort before anything runs" {
  feature_repo
  run hub --noop pull-request -p -h feature -wH alice:other
  assert_failure
  assert_output_equals "Aborted: two different heads given (feature and alice:other); give the head once, with -h, -H or --head."
  run hub --noop pull-request -wHalice:other --head=feature
  assert_failure
  assert_output_equals "Aborted: two different heads given (alice:other and feature); give the head once, with -h, -H or --head."
  run hub --noop pull-request -h a -H b
  assert_failure
  assert_output_equals "Aborted: two different heads given (a and b); give the head once, with -h, -H or --head."
  run hub --noop pull-request -h other -wH other
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --head other -w"
}

@test "a gh option's value is never read as one of hub's options" {
  feature_repo
  run hub --noop pull-request --title -p --body example
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --title -p --body example"
  run hub --noop pull-request --title=-p --project Roadmap -T -i
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --title=-p --project Roadmap -T -i"
}

@test "values of gh's options inside option clusters are left alone too" {
  feature_repo
  run hub --noop pull-request -dt -p -wl -f -wtTitle -p
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --repo github.com/mislav/dotfiles --head feature --draft -t -p -wl -f -wtTitle'
}

@test "-b OWNER:BRANCH and OWNER/REPO:BRANCH put the base in another repository" {
  feature_repo
  run hub --noop pull-request -m Fix -b alice:develop
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/alice/dotfiles --base develop"
  run hub --noop pull-request -m Fix --base=alice/fork:develop
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/alice/fork --base develop"
  run hub --noop pull-request -m Fix -b develop
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --base develop"
}

@test "-b OWNER:BRANCH on GitHub Enterprise names the host" {
  git config --global --add hub.host ghe.example.com
  feature_repo origin=https://ghe.example.com/mislav/dotfiles.git
  run hub --noop pull-request -b alice:develop
  assert_success
  assert_output_equals "gh pr create --repo ghe.example.com/alice/dotfiles --base develop"
}

@test "-b OWNER:BRANCH names the current repository's host, whatever gh's default host" {
  make_repo repo origin=https://github.com/mislav/repo.git
  export GH_HOST=enterprise.example
  run hub --noop pull-request -b other:main -m title
  assert_success
  assert_output_equals "gh pr create --title title --body '' --repo github.com/other/repo --base main"
  git config --global --add hub.host ghe.example.com
  cd "$HUB_TEST_TMP"
  make_repo ghe origin=https://ghe.example.com/mislav/repo.git
  export GH_HOST=github.com
  run hub --noop pull-request -b other/fork:main -m title
  assert_success
  assert_output_equals "gh pr create --title title --body '' --repo ghe.example.com/other/fork --base main"
  assert_gh_not_called
}

@test "-b OWNER:BRANCH together with -R, or a malformed base, aborts before anything runs" {
  feature_repo
  run hub --noop pull-request -b alice:develop -R cli/cli
  assert_failure
  assert_output_equals "Aborted: -b OWNER:BRANCH and -R/--repo both name the base repository; use one."
  run hub --noop pull-request --repo=cli/cli -p -b alice:develop
  assert_failure
  assert_output_equals "Aborted: -b OWNER:BRANCH and -R/--repo both name the base repository; use one."
  run hub --noop pull-request -wR cli/cli -b alice:develop
  assert_failure
  assert_output_equals "Aborted: -b OWNER:BRANCH and -R/--repo both name the base repository; use one."
  run hub --noop pull-request -wRcli/cli -b alice:develop
  assert_failure
  assert_output_equals "Aborted: -b OWNER:BRANCH and -R/--repo both name the base repository; use one."
  run hub --noop pull-request -b alice:
  assert_failure
  assert_output_equals "Aborted: not a base: alice: (use BRANCH, OWNER:BRANCH or OWNER/REPO:BRANCH)"
  run hub --noop pull-request -R cli/cli -b develop
  assert_success
  assert_output_equals "gh pr create --base develop -R cli/cli"
}

@test "the repository hub resolves is always named for gh, whatever gh's defaults" {
  make_repo repo origin=https://github.com/mislav/repo.git upstream=https://github.com/github/repo.git
  # gh repo set-default mislav/repo records this; hub's own choice is upstream.
  git config remote.origin.gh-resolved base
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

@test "-R or --repo, in any spelling, replaces the repository hub would name" {
  feature_repo
  local spelling
  for spelling in "-R cli/cli" "-Rcli/cli" "-R=cli/cli" "--repo cli/cli" "--repo=cli/cli" "-wR cli/cli" "-wRcli/cli"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop pull-request -m Fix $spelling
    assert_success
    assert_output_equals "gh pr create --title Fix --body '' $spelling"
  done
}

@test "without a GitHub remote, pull-request needs -R to know the repository" {
  make_repo repo origin=https://gitlab.com/mislav/repo.git
  run hub --noop pull-request -m Fix
  assert_failure
  assert_output_equals "Aborted: could not find a GitHub remote in this repository (looked for upstream, github, origin); name the repository with -R [HOST/]OWNER/REPO."
  run hub --noop pull-request -m Fix -R mislav/repo
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' -R mislav/repo"
  assert_gh_not_called
}

@test "-p pushes the current branch to origin before creating" {
  feature_repo
  run hub --noop pull-request -p -m Fix
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Fix --body \'\' --repo github.com/mislav/dotfiles --head feature'
}

@test "-p pushes to the branch's push remote when one is configured" {
  feature_repo
  git remote add fork https://github.com/alice/dotfiles.git
  git config remote.pushDefault fork
  run hub --noop pull-request -p
  assert_success
  assert_output_equals $'git push --set-upstream fork HEAD\ngh pr create --repo github.com/mislav/dotfiles --head alice:feature'
  git config branch.feature.pushRemote mine
  run hub --noop pull-request --push
  assert_success
  assert_line_equals 0 "git push --set-upstream mine HEAD"
}

@test "-p pushes to the branch's tracking remote" {
  feature_repo
  git config branch.feature.remote upstream
  run hub --noop pull-request -p
  assert_success
  assert_line_equals 0 "git push --set-upstream upstream HEAD"
}

@test "-p on a detached HEAD aborts before anything runs" {
  feature_repo
  git checkout -q --detach
  run hub --noop pull-request -p -m Fix
  assert_failure
  assert_output_equals "Aborted: not currently on any branch."
}

@test "-p with -h OWNER:BRANCH pushes HEAD to BRANCH on OWNER's remote" {
  feature_repo origin=https://github.com/mislav/dotfiles.git alice=https://github.com/alice/dotfiles.git
  run hub --noop pull-request -p -h alice:other -m title
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --title title --body \'\' --repo github.com/mislav/dotfiles --head alice:other'
  run hub --noop pull-request -p -h Alice:other
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head Alice:other'
}

@test "-p with -h OWNER:BRANCH prefers the push remote among OWNER's remotes" {
  feature_repo origin=https://github.com/mislav/dotfiles.git backup=git@github.com:mislav/dotfiles.git
  run hub --noop pull-request -p -h mislav:other
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head mislav:other'
}

@test "-p with -h OWNER:BRANCH aborts before anything runs when OWNER has no remote here" {
  git config --global --add hub.host ghe.example.com
  feature_repo origin=https://github.com/mislav/dotfiles.git alice=https://ghe.example.com/alice/dotfiles.git
  run hub --noop pull-request -p -h alice:other -m title
  assert_failure
  assert_output_equals "Aborted: no remote for alice/dotfiles to push other to; add one with git remote add, or push it yourself and drop -p."
  run hub --noop pull-request -p -h alice/fork:other
  assert_failure
  assert_output_equals "Aborted: -p cannot push to alice/fork:other; give the head as BRANCH or OWNER:BRANCH."
}

@test "-p with -h OWNER:BRANCH aborts before anything runs when OWNER's remote pushes elsewhere" {
  feature_repo origin=https://github.com/mislav/dotfiles.git alice=https://github.com/alice/dotfiles.git
  git remote set-url --push alice https://github.com/bob/dotfiles.git
  run hub --noop pull-request -p -h alice:other -m title
  assert_failure
  assert_output_equals "Aborted: remote alice is for github.com/alice/dotfiles, but it pushes to https://github.com/bob/dotfiles.git; fix its push URL (git remote set-url --push), or push it yourself and drop -p."
  # Two push URLs, one of them elsewhere (and never print the credentials in it).
  git remote set-url --push alice https://github.com/alice/dotfiles.git
  git remote set-url --add --push alice https://bob:s3cret@github.com/bob/dotfiles.git
  run hub --noop pull-request -p -h alice:other --dry-run
  assert_failure
  assert_output_equals "Aborted: remote alice is for github.com/alice/dotfiles, but it pushes to https://github.com/bob/dotfiles.git; fix its push URL (git remote set-url --push), or push it yourself and drop -p."
  # The push URL as git rewrites it (pushInsteadOf).
  git config --unset-all remote.alice.pushurl
  git config url./srv/mirror/.pushInsteadOf https://github.com/alice/
  run hub --noop pull-request -p -h alice:other
  assert_failure
  assert_output_equals "Aborted: remote alice is for github.com/alice/dotfiles, but it pushes to /srv/mirror/dotfiles.git; fix its push URL (git remote set-url --push), or push it yourself and drop -p."
  assert_gh_not_called
}

@test "-p with -h OWNER:BRANCH pushes when every push URL is OWNER's repository" {
  feature_repo origin=https://github.com/mislav/dotfiles.git alice=https://github.com/alice/dotfiles.git
  git remote set-url --push alice https://github.com/Alice/Dotfiles
  git remote set-url --add --push alice git@github.com:alice/dotfiles.git
  run hub --noop pull-request -p -h alice:other
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head alice:other'
  git config --unset-all remote.alice.pushurl
  git config url.git@github.com:.pushInsteadOf https://github.com/
  run hub --noop pull-request -p -h alice:other
  assert_success
  assert_output_equals $'git push alice HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head alice:other'
}

@test "-p with -h BRANCH pushes HEAD to BRANCH on the push remote" {
  feature_repo
  run hub --noop pull-request -p -h other -m title
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --title title --body \'\' --repo github.com/mislav/dotfiles --head other'
  git remote add mine https://github.com/mislav/dotfiles.git
  git config branch.feature.pushRemote mine
  run hub --noop pull-request -p -h other
  assert_success
  assert_output_equals $'git push mine HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head other'
  git checkout -q --detach
  run hub --noop pull-request -p -h other
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/mislav/dotfiles --head other'
}

@test "-p with -h BRANCH in a fork clone names the fork's owner in the head" {
  feature_repo origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  run hub --noop pull-request -p -h other
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh pr create --repo github.com/github/dotfiles --head mislav:other'
  run hub --noop pull-request -p -h other -i 12 -b main
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\ngh api --hostname github.com repos/github/dotfiles/pulls -F issue=12 -F head=mislav:other -f base=main --jq .html_url'
}

@test "the head names the owner of the repository the push remote pushes to, not fetches from" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/alice/repo.git
  git remote set-url --push origin https://github.com/bob/repo.git
  run hub --noop pull-request -p -h feature -m Title
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/feature\ngh pr create --title Title --body \'\' --repo github.com/org/repo --head bob:feature'
  run hub --noop pull-request -p -m Title
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Title --body \'\' --repo github.com/org/repo --head bob:feature'
  run hub --noop pull-request -p -f
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --repo github.com/org/repo --head bob:feature'
  run hub --noop pull-request -p -i 12 -b main
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh api --hostname github.com repos/org/repo/pulls -F issue=12 -F head=bob:feature -f base=main --jq .html_url'
  run hub --noop pull-request --dry-run -m Title
  assert_success
  assert_output_equals "gh pr create --title Title --body '' --repo github.com/org/repo --head bob:feature --dry-run"
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --repo github.com/org/repo --head bob:feature"
  # The push URL as git rewrites it (pushInsteadOf), and one in the base repository itself.
  git config --unset-all remote.origin.pushurl
  git config url.https://github.com/carol/.pushInsteadOf https://github.com/alice/
  run hub --noop pull-request -p -h feature
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/feature\ngh pr create --repo github.com/org/repo --head carol:feature'
  git config --unset url.https://github.com/carol/.pushInsteadOf
  git remote set-url --push origin git@github.com:Org/Repo.git
  run hub --noop pull-request -p -h feature
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/feature\ngh pr create --repo github.com/org/repo --head feature'
  assert_gh_not_called
}

@test "push URLs that name two repositories abort before anything runs" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/alice/repo.git
  git remote set-url --push origin https://github.com/alice/repo.git
  git remote set-url --add --push origin https://bob:s3cret@github.com/bob/repo.git
  local both="Aborted: remote origin pushes to both https://github.com/alice/repo.git and https://github.com/bob/repo.git; fix its push URLs (git remote set-url --push), or"
  run hub --noop pull-request -p -m Title
  assert_failure
  assert_output_equals "$both push it yourself and drop -p."
  run hub --noop pull-request -p -h feature
  assert_failure
  assert_output_equals "$both push it yourself and name the head with -h OWNER:BRANCH, without -p."
  run hub --noop pull-request -p -i 12 -b main
  assert_failure
  assert_output_equals "$both push it yourself and name the head with -h OWNER:BRANCH, without -p."
  run hub --noop pull-request -f
  assert_failure
  assert_output_equals "$both name the head with -h OWNER:BRANCH."
  run hub --noop pull-request --dry-run
  assert_failure
  assert_output_equals "$both name the head with -h OWNER:BRANCH."
  run hub --noop pull-request -i 12 -b main
  assert_failure
  assert_output_equals "$both name the head with -h OWNER:BRANCH."
  run hub --noop pull-request -f -h bob:feature
  assert_success
  assert_output_equals "gh pr create --repo github.com/org/repo --head bob:feature"
  assert_gh_not_called
}

@test "a local or mirror push URL is accepted only where hub leaves the head to gh" {
  feature_repo upstream=https://github.com/org/repo.git origin=https://github.com/alice/repo.git
  git config url./srv/mirror/.pushInsteadOf https://github.com/alice/
  run hub --noop pull-request -p -m Title
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Title --body \'\' --repo github.com/org/repo'
  local mirror="Aborted: remote origin pushes to /srv/mirror/repo.git, which is not a GitHub repository; a local or mirror push URL is only accepted when hub does not have to work out the head from it, so" args
  # shellcheck disable=SC2086  # split on purpose
  for args in "-p -h feature" "-p -f" "-p --dry-run" "-p -i 12 -b main"; do
    run hub --noop pull-request $args
    assert_failure
    assert_output_equals "$mirror push it yourself and name the head with -h OWNER:BRANCH, without -p."
  done
  # shellcheck disable=SC2086  # split on purpose
  for args in "-f" "--dry-run" "-i 12 -b main"; do
    run hub --noop pull-request $args
    assert_failure
    assert_output_equals "$mirror name the head with -h OWNER:BRANCH."
  done
  run hub --noop pull-request --dry-run -h alice:feature
  assert_success
  assert_output_equals "gh pr create --repo github.com/org/repo --head alice:feature --dry-run"
  # A GitHub push URL beside a local one (a backup, say) is no better.
  git config --unset url./srv/mirror/.pushInsteadOf
  git remote set-url --add --push origin https://github.com/alice/repo.git
  git remote set-url --add --push origin "$HUB_TEST_TMP/backup.git"
  run hub --noop pull-request -p
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --repo github.com/org/repo'
  run hub --noop pull-request -f
  assert_failure
  assert_output_equals "Aborted: remote origin pushes to $HUB_TEST_TMP/backup.git, which is not a GitHub repository; a local or mirror push URL is only accepted when hub does not have to work out the head from it, so name the head with -h OWNER:BRANCH."
  assert_gh_not_called
}

@test "-p with -h OWNER:BRANCH takes the remote that pushes to OWNER's repository, whatever it fetches" {
  feature_repo origin=https://github.com/org/repo.git
  git remote set-url --push origin https://github.com/alice/repo.git
  run hub --noop pull-request -p -h alice:feature -m Title
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/feature\ngh pr create --title Title --body \'\' --repo github.com/org/repo --head alice:feature'
  run hub --noop pull-request -p -m Title
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Title --body \'\' --repo github.com/org/repo --head alice:feature'
}

@test "--dry-run with -p prints the push instead of pushing" {
  feature_repo
  stub_git_push # a local push URL would do, but hub names the head here and needs it on GitHub
  stub_gh 'pr create *' 'Would have created a pull request'
  export BROWSER='echo browse'
  run hub pull-request -p --dry-run -m Fix
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\nWould have created a pull request'
  assert_gh_called 'pr create --title Fix --body  --repo github.com/mislav/dotfiles --head feature --dry-run'
  run hub pull-request -o -p -h other --dry-run=true
  assert_success
  assert_output_equals $'git push origin HEAD:refs/heads/other\nWould have created a pull request'
  [[ ! -e $HUB_TEST_TMP/pushes ]]
  # The same push, for real this time: the check above would have seen it.
  run hub pull-request -p --dry-run=false -m Fix
  assert_success
  [[ $(cat "$HUB_TEST_TMP/pushes") == "git push --set-upstream origin HEAD" ]]
}

@test "--dry-run names the head, so that gh's dry run neither pushes nor forks" {
  make_repo repo origin=https://github.com/mislav/repo.git
  run hub --noop pull-request -p --dry-run -m Test
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Test --body \'\' --repo github.com/mislav/repo --head main --dry-run'
  run hub --noop pull-request --dry-run=true -b other:main -m Test --
  assert_success
  assert_output_equals "gh pr create --title Test --body '' --repo github.com/other/repo --base main --head mislav:main --dry-run=true --"
  run hub --noop pull-request -p --dry-run=false -m Test
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Test --body \'\' --repo github.com/mislav/repo --head main --dry-run=false'
  assert_gh_not_called
}

@test "--dry-run in a fork clone names the fork's owner in the head" {
  make_repo repo origin=https://github.com/mislav/repo.git upstream=https://github.com/github/repo.git
  run hub --noop pull-request -p --dry-run -m Test
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Test --body \'\' --repo github.com/github/repo --head mislav:main --dry-run'
}

@test "--dry-run keeps a head given with -h or gh's -H, and needs one on a detached HEAD" {
  make_repo repo origin=https://github.com/mislav/repo.git
  run hub --noop pull-request --dry-run -h topic
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/repo --head topic --dry-run"
  run hub --noop pull-request --dry-run -wH topic
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/repo --head topic --dry-run -w"
  run hub --noop pull-request -wHtopic --dry-run
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/repo --head topic -w --dry-run"
  git checkout -q --detach
  run hub --noop pull-request --dry-run -m Test
  assert_failure
  assert_output_equals "Aborted: not currently on any branch; with --dry-run, name the head with -h [OWNER:]BRANCH."
  run hub --noop pull-request --dry-run -H mislav:topic
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/repo --head mislav:topic --dry-run"
}

@test "-f names the pushed branch as the head, so gh neither pushes nor forks" {
  feature_repo
  run hub --noop pull-request -f -m Fix
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --head feature"
}

@test "-f in a fork clone names the fork's owner" {
  feature_repo origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --repo github.com/github/dotfiles --head mislav:feature"
}

@test "-f against a base in another repository names the head's owner" {
  feature_repo
  run hub --noop pull-request -f -b github:main
  assert_success
  assert_output_equals "gh pr create --repo github.com/github/dotfiles --base main --head mislav:feature"
  run hub --noop pull-request -f -R github/dotfiles
  assert_success
  assert_output_equals "gh pr create --head mislav:feature -R github/dotfiles"
  run hub --noop pull-request -f -R=github/dotfiles
  assert_success
  assert_output_equals "gh pr create --head mislav:feature -R=github/dotfiles"
}

@test "-f keeps an explicit -h, and -pf pushes first" {
  feature_repo
  run hub --noop pull-request -f -h other
  assert_success
  assert_output_equals "gh pr create --repo github.com/mislav/dotfiles --head other"
  run hub --noop pull-request -pf
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --repo github.com/mislav/dotfiles --head feature'
}

@test "-o prints the new pull request's URL and opens it" {
  feature_repo
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/7'
  export BROWSER='echo browse'
  run hub pull-request -o -m Fix
  assert_success
  assert_output_equals $'https://github.com/mislav/dotfiles/pull/7\nbrowse https://github.com/mislav/dotfiles/pull/7'
  assert_gh_called 'pr create --title Fix --body  --repo github.com/mislav/dotfiles'
}

@test "-c copies the new pull request's URL" {
  feature_repo
  stub_clipboard
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/7'
  run hub pull-request -c -m Fix -d
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/pull/7"
  [[ $(cat "$HUB_TEST_TMP/clipboard") == "https://github.com/mislav/dotfiles/pull/7" ]]
  assert_gh_called 'pr create --title Fix --body  --repo github.com/mislav/dotfiles --draft'
}

@test "-o and -c under --noop print only the gh command" {
  feature_repo
  run hub --noop pull-request -o -c -m Fix
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles"
  assert_gh_not_called
}

@test "-o opens nothing when gh fails" {
  feature_repo
  stub_gh 'pr create *' '' 1
  export BROWSER='echo browse'
  run hub pull-request -o -m Fix
  assert_failure
  [[ $output != *browse* ]]
}

@test "-i turns an issue into a pull request through the REST API" {
  feature_repo
  run hub --noop pull-request -i 12 -b develop
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=develop --jq .html_url"
  assert_gh_not_called
}

@test "-i accepts #N and defaults the base to the default branch" {
  feature_repo
  set_remote_head origin trunk
  run hub --noop pull-request --issue '#12'
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=trunk --jq .html_url"
}

@test "an issue URL as the argument converts that issue in its own repository" {
  feature_repo
  run hub --noop pull-request https://github.com/mislav/dotfiles/issues/12 -b main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=main --jq .html_url"
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3 -b main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/dotfiles/pulls -F issue=3 -F head=mislav:feature -f base=main --jq .html_url"
}

@test "an issue in another repository takes that repository's default branch" {
  feature_repo
  stub_gh 'repo view github.com/github/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/dotfiles/pulls -F issue=3 -F head=mislav:feature -f base=trunk --jq .html_url"
  assert_gh_called 'repo view github.com/github/dotfiles --json defaultBranchRef -q .defaultBranchRef.name'
}

@test "an issue URL in the current repository takes the local default branch" {
  feature_repo
  set_remote_head origin develop
  run hub --noop pull-request -i https://github.com/Mislav/Dotfiles/issues/12
  assert_success
  assert_output_equals "gh api --hostname github.com repos/Mislav/Dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=develop --jq .html_url"
  assert_gh_not_called
}

@test "an issue in another repository aborts before anything runs if its default branch is unknown" {
  feature_repo
  stub_gh 'repo view *' '' 1
  run hub --noop pull-request -p -i https://github.com/github/dotfiles/issues/3
  assert_failure
  assert_output_equals "Aborted: could not look up the default branch of github/dotfiles; give the base with -b BRANCH."
}

@test "an issue in another repository on GitHub Enterprise is looked up there" {
  git config --global --add hub.host ghe.example.com
  feature_repo origin=https://ghe.example.com/mislav/dotfiles.git
  stub_gh 'repo view ghe.example.com/github/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request -i https://ghe.example.com/github/dotfiles/issues/3
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com repos/github/dotfiles/pulls -F issue=3 -F head=mislav:feature -f base=trunk --jq .html_url"
}

@test "-i with -b OWNER:BRANCH converts an issue of that repository" {
  feature_repo
  run hub --noop pull-request -i 12 -b github:main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=main --jq .html_url"
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3 -b github:main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/dotfiles/pulls -F issue=3 -F head=mislav:feature -f base=main --jq .html_url"
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3 -b alice:main
  assert_failure
  assert_output_equals "Aborted: -b names alice/dotfiles, but the issue is in github/dotfiles."
}

@test "-i takes the head owner from the push remote, or -h as given" {
  feature_repo origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  run hub --noop pull-request -i 12 -b main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=main --jq .html_url"
  run hub --noop pull-request -i 12 -b main -h someone:topic
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/dotfiles/pulls -F issue=12 -F head=someone:topic -f base=main --jq .html_url"
}

@test "-p -i pushes first; -d and --no-maintainer-edits become API fields" {
  feature_repo
  run hub --noop pull-request -p -d --no-maintainer-edits -i 12 -b main
  assert_success
  assert_line_equals 0 "git push --set-upstream origin HEAD"
  assert_line_equals 1 "gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=main -F draft=true -F maintainer_can_modify=false --jq .html_url"
  [[ ${#lines[@]} -eq 2 ]]
}

@test "-i on GitHub Enterprise passes --hostname" {
  git config --global --add hub.host ghe.example.com
  feature_repo origin=https://ghe.example.com/mislav/dotfiles.git
  run hub --noop pull-request -i 12 -b main
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com repos/mislav/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=main --jq .html_url"
}

@test "-i N converts the issue in hub's repository on its host, whatever gh's defaults" {
  make_repo repo origin=https://github.com/mislav/repo.git
  run hub --noop pull-request -i 12 -b main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/repo/pulls -F issue=12 -F head=mislav:main -f base=main --jq .html_url"
  export GH_HOST=enterprise.example
  run hub --noop pull-request -i 12 -b main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/repo/pulls -F issue=12 -F head=mislav:main -f base=main --jq .html_url"
  # gh repo set-default mislav/repo records this; hub's own choice is upstream.
  git remote add upstream https://github.com/github/repo.git
  git config remote.origin.gh-resolved base
  run hub --noop pull-request -i 12 -b main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/repo/pulls -F issue=12 -F head=mislav:main -f base=main --jq .html_url"
  assert_gh_not_called
}

@test "a github.com issue URL goes to github.com even when gh's default host is another" {
  make_repo repo origin=https://github.com/mislav/repo.git
  export GH_HOST=enterprise.example
  run hub --noop pull-request https://github.com/mislav/repo/issues/3 -b main
  assert_success
  assert_output_equals "gh api --hostname github.com repos/mislav/repo/pulls -F issue=3 -F head=mislav:main -f base=main --jq .html_url"
  stub_gh 'repo view github.com/github/repo --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop pull-request -i https://github.com/github/repo/issues/4
  assert_success
  assert_output_equals "gh api --hostname github.com repos/github/repo/pulls -F issue=4 -F head=mislav:main -f base=trunk --jq .html_url"
  assert_gh_called 'repo view github.com/github/repo --json defaultBranchRef -q .defaultBranchRef.name'
}

@test "an Enterprise issue URL goes to its own host, whatever gh's default host" {
  git config --global --add hub.host ghe.example.com
  make_repo repo origin=https://ghe.example.com/mislav/repo.git
  run hub --noop pull-request -i https://ghe.example.com/mislav/repo/issues/3 -b main
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com repos/mislav/repo/pulls -F issue=3 -F head=mislav:main -f base=main --jq .html_url"
  export GH_HOST=enterprise.example
  run hub --noop pull-request -i https://ghe.example.com/mislav/repo/issues/3 -b main
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com repos/mislav/repo/pulls -F issue=3 -F head=mislav:main -f base=main --jq .html_url"
  assert_gh_not_called
}

@test "-i with -o opens the converted pull request" {
  feature_repo
  stub_gh 'api --hostname github.com repos/mislav/dotfiles/pulls -F issue=12 *' 'https://github.com/mislav/dotfiles/pull/12'
  export BROWSER='echo browse'
  run hub pull-request -i 12 -b main -o
  assert_success
  assert_output_equals $'https://github.com/mislav/dotfiles/pull/12\nbrowse https://github.com/mislav/dotfiles/pull/12'
}

@test "-i rejects options that don't apply to an existing issue" {
  feature_repo
  run hub --noop pull-request -i 12 -m Fix
  assert_failure
  assert_output_contains "Aborted: -i uses the issue's title and body"
  run hub --noop pull-request -i 12 -r alice
  assert_failure
  assert_output_contains "Aborted: -i cannot add reviewers"
  run hub --noop pull-request -i 12 --fill
  assert_failure
  assert_output_contains "Aborted: -i does not take gh pr create options: --fill"
  run hub --noop pull-request -i twelve
  assert_failure
  assert_output_contains "Aborted: not an issue number or issue URL: twelve"
}

@test "an issue URL given as the value of a gh option is left alone" {
  feature_repo
  run hub --noop pull-request -m Fix --body https://github.com/mislav/dotfiles/issues/12
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles --body https://github.com/mislav/dotfiles/issues/12"
  run hub --noop pull-request -m Fix -wb https://github.com/mislav/dotfiles/issues/12
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --repo github.com/mislav/dotfiles -wb https://github.com/mislav/dotfiles/issues/12"
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
