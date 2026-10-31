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

@test "compare opens the current branch's compare page" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD # pushed to origin, no upstream set
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
  assert_gh_not_called
}

@test "compare finds a branch pushed to its upstream or its push remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  git branch -q --set-upstream-to=origin/feature # git push -u origin feature
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
  # started from origin/main (its upstream), then pushed without -u
  git checkout -q -b topic --track origin/main
  git update-ref refs/remotes/origin/topic HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/topic"
  assert_gh_not_called
}

@test "compare refuses a branch that is not pushed to a GitHub remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git backup=../backup.git
  set_remote_head origin main
  git checkout -q -b feature
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  run hub --noop compare -b develop
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  # an upstream the branch was started from is not where it was pushed
  git checkout -q -b topic --track origin/main
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'topic' is not pushed to any GitHub remote; push it first or name a range"
  # pushed, but to a remote that is not on GitHub
  git config branch.topic.pushRemote backup
  git update-ref refs/remotes/backup/topic HEAD
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'topic' is not pushed to any GitHub remote; push it first or name a range"
  run hub --noop compare main...topic
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/main...topic"
  assert_gh_not_called
}

@test "compare on the default branch explains what to do" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: main is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
  # the default branch is asked of gh when the remote HEAD is unknown
  git update-ref -d refs/remotes/origin/main
  git update-ref refs/remotes/origin/trunk HEAD
  git checkout -q -b trunk --track origin/trunk
  stub_gh 'repo view github.com/mislav/dotfiles --json defaultBranchRef -q .defaultBranchRef.name' 'trunk'
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: trunk is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
  assert_gh_called 'repo view github.com/mislav/dotfiles --json defaultBranchRef -q .defaultBranchRef.name'
}

@test "compare on a detached HEAD explains what to do" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git checkout -q --detach
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: not currently on any branch; name a branch or a BASE...HEAD range to compare."
  run hub --noop compare main...topic # a range needs no branch
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/main...topic"
}

@test "compare turns a two-dot range into GitHub's three-dot form" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare v1.0..v1.1
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/v1.0...v1.1"
  run hub --noop compare v1.0...v1.1
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/v1.0...v1.1"
  run hub --noop compare refactor
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/refactor"
  run hub --noop compare -- v1.0..v1.1
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/v1.0...v1.1"
  assert_gh_not_called
}

@test "compare -b BASE compares the current branch or HEAD against BASE" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare -b develop
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/develop...feature"
  run hub --noop compare --base develop topic
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/develop...topic"
  git checkout -q main
  run hub --noop compare --base=release
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/release...main"
}

@test "compare takes -b's value attached or separately, and clusters its flags" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub compare -u -bdevelop
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/compare/develop...feature"
  run hub compare -ub develop
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/compare/develop...feature"
  run hub compare -ubdevelop
  assert_output_equals "https://github.com/mislav/dotfiles/compare/develop...feature"
  run hub --noop compare -cu
  assert_output_equals $'https://github.com/mislav/dotfiles/compare/feature\ncopy to clipboard: https://github.com/mislav/dotfiles/compare/feature'
  run hub compare --url=1
  assert_failure
  assert_output_contains "unknown option: --url=1"
  run hub compare -ux
  assert_failure
  assert_output_contains "unknown option: -x"
  assert_gh_not_called
}

@test "compare -b refuses a range" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare -b develop a..b
  assert_failure
  assert_output_contains "use either -b BASE or a range"
}

@test "compare -b refuses a BASE that is the head" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare -b feature
  assert_failure
  assert_output_equals "Aborted: 'feature' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare --base topic topic
  assert_failure
  assert_output_equals "Aborted: 'topic' is both the base and the head; name a different BASE or HEAD"
  git checkout -q main
  run hub --noop compare --base=main
  assert_failure
  assert_output_equals "Aborted: 'main' is both the base and the head; name a different BASE or HEAD"
}

@test "compare refuses a range from a ref to itself" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare feature...feature
  assert_failure
  assert_output_equals "Aborted: 'feature' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare v1..v1
  assert_failure
  assert_output_equals "Aborted: 'v1' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare jingweno main...main
  assert_failure
  assert_output_equals "Aborted: 'main' is both the base and the head; name a different BASE or HEAD"
  run hub --noop compare main...feature
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/main...feature"
}

@test "compare OWNER RANGE uses OWNER's copy of the repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare jingweno v1..v2
  assert_success
  assert_output_equals "open https://github.com/jingweno/dotfiles/compare/v1...v2"
  run hub --noop compare jingweno/dotfiles v1..v2
  assert_failure
  assert_output_contains "hub compare: not an owner: jingweno/dotfiles"
}

@test "compare writes FORKOWNER:BRANCH when the branch pushes to a fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote mislav
  git config branch.feature.merge refs/heads/feature
  git update-ref refs/remotes/mislav/feature HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/mislav:feature"
  run hub --noop compare -b develop
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/develop...mislav:feature"
  run hub --noop compare -b feature # the same name in another repository is a different branch
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/feature...mislav:feature"
  run hub --noop compare -b mislav:feature
  assert_failure
  assert_output_equals "Aborted: 'mislav:feature' is both the base and the head; name a different BASE or HEAD"
}

@test "compare cannot read a remote-tracking branch as proof when its remote pushes to another repository" {
  make_repo repo origin=https://github.com/org/repo.git
  git remote set-url --push origin https://github.com/alice/renamed.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD # fetched from org/repo: it says nothing about alice/renamed
  git branch -q --set-upstream-to=origin/feature
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: origin fetches from one repository and pushes to another, so its remote-tracking branches cannot show whether 'feature' is pushed; name the head yourself: hub compare [BASE...]OWNER:feature"
  run hub compare -u alice:renamed:feature
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:renamed:feature"
  run hub compare -u -b main alice:renamed:feature
  assert_output_equals "https://github.com/org/repo/compare/main...alice:renamed:feature"
  # the same repository as push URL, however it is spelled: the branch is the repository's own
  git remote set-url --push origin https://github.com/ORG/Repo.git
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/feature"
  assert_gh_not_called
}

@test "compare reads the remote-tracking branch the remote's fetch refspecs map the branch to" {
  make_repo project origin=https://github.com/alice/project.git
  set_remote_head origin main
  git checkout -q -b feature
  git config push.default current
  # a mapping that fetches another branch into refs/remotes/origin/feature: that ref says nothing about feature
  git config --unset-all remote.origin.fetch
  git config --add remote.origin.fetch '+refs/heads/release:refs/remotes/origin/feature'
  git update-ref refs/remotes/origin/feature HEAD
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: remote.origin.fetch maps no remote-tracking branch to 'feature' of origin, so nothing here shows whether 'feature' is pushed there; name the head yourself: hub compare [BASE...]OWNER:feature"
  # branches fetched into another namespace are read there, and nowhere else
  git config --unset-all remote.origin.fetch
  git config --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/mirror/*'
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  git update-ref refs/remotes/origin/mirror/feature HEAD
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/alice/project/compare/feature"
  # a negative refspec keeps the branch from being fetched: no ref here can be current for it
  git config --add remote.origin.fetch '^refs/heads/feature'
  run hub compare -u
  assert_failure
  assert_output_contains "remote.origin.fetch maps no remote-tracking branch to 'feature' of origin"
  assert_gh_not_called
}

@test "compare writes FORKOWNER:FORKREPO:BRANCH for a fork of another name, even under the same owner" {
  make_repo repo origin=https://github.com/org/repo.git fork=https://github.com/org/renamed.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/fork/feature HEAD
  git branch -q --set-upstream-to=fork/feature
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/org:renamed:feature"
  git remote set-url fork https://github.com/Alice/Renamed.git # names compare case-insensitively
  git update-ref refs/remotes/fork/main HEAD
  git checkout -q -b fix --track fork/main
  git config remote.pushDefault fork
  git update-ref refs/remotes/fork/fix HEAD
  run hub compare -u
  assert_output_equals "https://github.com/org/repo/compare/Alice:Renamed:fix"
  git remote set-url fork https://github.com/Alice/REPO.git
  run hub compare -u
  assert_output_equals "https://github.com/org/repo/compare/Alice:fix"
  assert_gh_not_called
}

@test "compare on a fork's default branch compares it with the repository it was forked from" {
  make_repo repo origin=https://github.com/alice/repo.git upstream=https://github.com/org/repo.git
  set_remote_head origin main
  set_remote_head upstream main
  git branch -q --set-upstream-to=origin/main
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:main"
  run hub compare -u -b develop
  assert_output_equals "https://github.com/org/repo/compare/develop...alice:main"
  # a fork whose default branch has another name
  git checkout -q -b trunk
  git update-ref refs/remotes/origin/trunk HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git branch -q --set-upstream-to=origin/trunk
  run hub compare -u
  assert_output_equals "https://github.com/org/repo/compare/alice:trunk"
  # the compared repository's own copy of main is its default branch
  git checkout -q main
  git config branch.main.remote upstream
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: main is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
  GH_REPO=alice/repo run hub compare -u # unless the compare page is another repository's
  assert_success
  assert_output_equals "https://github.com/alice/repo/compare/org:main"
  assert_gh_not_called
}

@test "compare follows remote.pushDefault to the fork a branch was pushed to" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dotfiles.git
  set_remote_head origin main
  git config remote.pushDefault mislav
  git checkout -q -b feature --track origin/main
  run hub --noop compare
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  git update-ref refs/remotes/mislav/feature HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/dotcom/dotfiles/compare/mislav:feature"
  assert_gh_not_called
}

@test "compare uses the name the branch has on the remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b local-name
  git config remote.origin.push refs/heads/local-name:refs/heads/published
  git update-ref refs/remotes/origin/published HEAD
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/compare/published"
}

@test "compare keeps the plain branch name when it pushes to the same repository" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  set_remote_head origin main
  git checkout -q -b feature
  git config branch.feature.remote origin
  git config branch.feature.merge refs/heads/feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/compare/feature"
}

@test "compare names the head after the main remote when only the main remote has the branch" {
  make_repo repo origin=https://github.com/alice/repo.git upstream=https://github.com/org/repo.git
  set_remote_head upstream main
  git checkout -q -b feature
  git config branch.feature.pushRemote origin # pushed to alice's fork, but there is no origin/feature
  git update-ref refs/remotes/upstream/feature HEAD
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/feature"
  assert_gh_not_called
}

@test "compare writes FORKOWNER:BRANCH when the fork it is configured to push to has the branch" {
  make_repo repo origin=https://github.com/alice/repo.git upstream=https://github.com/org/repo.git
  set_remote_head upstream main
  git checkout -q -b feature
  git config branch.feature.pushRemote origin # git push alone would refuse (no upstream); it went with git push origin feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:feature"
  git update-ref refs/remotes/upstream/feature HEAD # the push target's ref comes first
  run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:feature"
  assert_gh_not_called
}

@test "compare refuses a branch that neither its fork nor the main remote has" {
  make_repo repo origin=https://github.com/alice/repo.git upstream=https://github.com/org/repo.git
  set_remote_head upstream main
  git checkout -q -b feature
  git config branch.feature.pushRemote origin
  git update-ref refs/remotes/origin/other HEAD
  git update-ref refs/remotes/upstream/other HEAD
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
}

@test "compare only counts a branch pushed to a remote on the compare page's host" {
  git config --global hub.host enterprise.example
  make_repo repo upstream=https://enterprise.example/org/repo.git origin=https://github.com/alice/repo.git
  set_remote_head upstream main
  git checkout -q -b feature
  git config branch.feature.pushRemote origin
  git update-ref refs/remotes/origin/feature HEAD # pushed to github.com, not to enterprise.example
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: the branch 'feature' is not pushed to any GitHub remote; push it first or name a range"
  GH_REPO=github.com/org/repo run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:feature"
  git update-ref refs/remotes/upstream/feature HEAD # the main remote's ref is next
  run hub compare -u
  assert_success
  assert_output_equals "https://enterprise.example/org/repo/compare/feature"
  # the same host, in other case and with a port
  git remote set-url origin https://Enterprise.Example:8443/alice/repo.git
  run hub compare -u
  assert_success
  assert_output_equals "https://enterprise.example/org/repo/compare/alice:feature"
  # main pushed to a fork on another host: on the compare page's host it is the repository's own main
  git remote set-url origin https://github.com/alice/repo.git
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q main
  git branch -q --set-upstream-to=origin/main
  run hub compare -u
  assert_failure
  assert_output_equals "Aborted: main is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
  assert_gh_not_called
}

@test "compare with GH_REPO names the head after the main remote's copy that has the branch" {
  make_repo repo origin=https://github.com/alice/repo.git
  set_remote_head origin main
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  GH_REPO=org/repo run hub compare -u
  assert_success
  assert_output_equals "https://github.com/org/repo/compare/alice:feature"
  GH_REPO=github.com/Alice/repo run hub compare -u
  assert_success
  assert_output_equals "https://github.com/Alice/repo/compare/feature"
  # hosts are compared without their ports
  git config --global hub.host ghe.example.com
  git remote set-url origin https://ghe.example.com/alice/repo.git
  GH_REPO=ghe.example.com:8443/org/repo run hub compare -u
  assert_success
  assert_output_equals "https://ghe.example.com:8443/org/repo/compare/alice:feature"
}

@test "compare escapes characters that are special in URLs" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub compare -u 'my#b+x'
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/compare/my%23b%2Bx"
}

@test "compare -u prints and -c copies the URL" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop compare -u v1..v2
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/compare/v1...v2"
  run hub --noop compare -c v1..v2
  assert_output_equals "copy to clipboard: https://github.com/mislav/dotfiles/compare/v1...v2"
  run hub --noop compare --url --copy v1..v2
  assert_output_equals $'https://github.com/mislav/dotfiles/compare/v1...v2\ncopy to clipboard: https://github.com/mislav/dotfiles/compare/v1...v2'
}

@test "compare exits with the status of a browser or clipboard tool that fails" {
  make_repo repo origin=https://github.com/alice/repo.git
  failing_tools
  run hub compare main...topic
  assert_status 19
  assert_output_equals "browser failed: https://github.com/alice/repo/compare/main...topic"
  run hub compare -c main...topic
  assert_status 17
  assert_output_equals "clipboard failed"
  run hub compare -uc main...topic # the URL is printed, then the copy fails
  assert_status 17
  assert_output_equals $'https://github.com/alice/repo/compare/main...topic\nclipboard failed'
  run hub compare -u main...topic
  assert_success
  assert_output_equals "https://github.com/alice/repo/compare/main...topic"
}

@test "compare uses the remote's enterprise host" {
  make_repo app origin=https://ghe.example.com/corp/app.git
  export GH_HOST=ghe.example.com
  run hub --noop compare main...topic
  assert_success
  assert_output_equals "open https://ghe.example.com/corp/app/compare/main...topic"
}

@test "compare in a REPO.wiki repository opens the wiki's compare page" {
  make_repo dotfiles.wiki origin=git@github.com:mislav/dotfiles.wiki.git
  set_remote_head origin main
  run hub --noop compare 1a2b3c..4d5e6f
  assert_success
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki/_compare/1a2b3c...4d5e6f"
  git checkout -q -b feature
  git update-ref refs/remotes/origin/feature HEAD
  run hub --noop compare -b main
  assert_output_equals "open https://github.com/mislav/dotfiles/wiki/_compare/main...feature"
  GH_REPO=cli/cli.wiki run hub compare -u v1...v2
  assert_output_equals "https://github.com/cli/cli/wiki/_compare/v1...v2"
  assert_gh_not_called
}

@test "compare without a GitHub remote fails" {
  make_repo local-only
  run hub --noop compare a..b
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
}

@test "compare rejects unknown options and extra arguments" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub compare --bogus
  assert_failure
  assert_output_equals $'hub compare: unknown option: --bogus\nUsage: hub compare [-u] [-c] [-b BASE] [OWNER] [[BASE...]HEAD]'
  run hub compare a b c
  assert_failure
  assert_output_contains "hub compare: too many arguments"
  run hub compare -b
  assert_failure
  assert_output_contains "hub compare: -b needs a BASE"
  run hub compare --base
  assert_failure
  assert_output_contains "hub compare: --base needs a BASE"
  assert_gh_not_called
}

@test "compare --help prints the manual" {
  run hub compare --help
  assert_success
  assert_output_contains "Usage: hub compare [-u] [-c] [-b BASE]"
  assert_output_contains "FORKOWNER:FORKREPO:BRANCH"
}
