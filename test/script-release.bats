#!/usr/bin/env bats
load test_helper

# release_checkout : a scratch checkout of hub, on a clean main that is up to date with its origin, with
# a copy of script/release and a bump that only prints; cd into it. The tests run `script/release --dry-run`
# there, which checks the local state and prints the other commands instead of running them.
release_checkout() {
  git init -q -b main checkout && cd checkout || return 1
  mkdir script Formula
  cp "$HUB_TEST_ROOT/script/release" script/release
  printf '#!/usr/bin/env bash\nexit 0\n' >script/bump
  chmod +x script/bump
  printf '0.1.0\n' >VERSION
  printf 'class Hub < Formula\n  REPO = "brc-dd/hub".freeze\nend\n' >Formula/hub.rb
  git add -A && git commit -q -m "initial commit"
  git remote add origin https://github.com/brc-dd/hub.git
  git update-ref refs/remotes/origin/main HEAD
}

@test "the release goes to the one repository that origin's fetch URL and push URLs name" {
  release_checkout
  run script/release --dry-run 0.2.0
  assert_success
  assert_output_contains "==> Releasing to github.com/brc-dd/hub"
  assert_output_contains "[dry-run] gh repo view github.com/brc-dd/hub --json nameWithOwner -q .nameWithOwner"
  assert_output_contains "[dry-run] git push --atomic origin refs/heads/main:refs/heads/main refs/tags/v0.2.0:refs/tags/v0.2.0"
  assert_output_contains "[dry-run] gh release create v0.2.0 --repo github.com/brc-dd/hub --verify-tag --generate-notes --title hub\\ 0.2.0"
  # another spelling of the same repository as the push URL is the same repository
  git remote set-url --push origin https://github.com/BRC-DD/Hub
  run script/release --dry-run 0.2.0
  assert_success
  assert_output_contains "==> Releasing to github.com/brc-dd/hub"
  assert_gh_not_called
}

@test "origin that pushes to another repository than it fetches from is refused before anything is pushed" {
  release_checkout
  git remote set-url --push origin https://github.com/alice/hub.git
  run script/release --dry-run 0.2.0
  assert_failure
  assert_output_equals "script/release: origin fetches from github.com/brc-dd/hub but pushes to github.com/alice/hub; the release must go to one repository (git remote get-url --push --all origin)"
  # one of several push URLs is enough to refuse
  git remote set-url --push origin https://github.com/brc-dd/hub.git
  git remote set-url --add --push origin https://github.com/brc-dd/other.git
  run script/release --dry-run 0.2.0
  assert_failure
  assert_output_contains "origin fetches from github.com/brc-dd/hub but pushes to github.com/brc-dd/other"
  [[ -z $(git tag) ]]
  assert_gh_not_called
}

@test "origin must be a GitHub repository URL" {
  release_checkout
  git remote set-url origin ../elsewhere.git
  run script/release --dry-run 0.2.0
  assert_failure
  assert_output_equals "script/release: origin is not a GitHub repository URL: ../elsewhere.git"
  git remote remove origin
  run script/release --dry-run 0.2.0
  assert_failure
  assert_output_equals "script/release: no origin remote"
}

@test "a stable release comes from a checkout of the formula's repository; a pre-release from a fork leaves the formula alone" {
  release_checkout
  git remote set-url origin https://github.com/alice/fork.git
  run script/release --dry-run 0.2.0
  assert_failure
  assert_line_equals -1 "script/release: origin is github.com/alice/fork, but Formula/hub.rb is for github.com/brc-dd/hub: the release would go to one repository and the formula point at the other. Release from a checkout of brc-dd/hub, or change REPO in the formula."
  assert_output_lacks "Checking" # before make check, the bump and any push
  assert_output_lacks "git push"
  [[ -z $(git tag) ]]
  run script/release --dry-run 0.2.0-rc.1
  assert_success
  assert_output_contains "note: origin is github.com/alice/fork, not github.com/brc-dd/hub, which Formula/hub.rb is for; a pre-release leaves the formula alone"
  assert_output_contains "[dry-run] gh release create v0.2.0-rc.1 --repo github.com/alice/fork --verify-tag --generate-notes --title hub\\ 0.2.0-rc.1 --prerelease"
  assert_output_contains "==> Leaving Formula/hub.rb alone: v0.2.0-rc.1 is a pre-release"
  # the formula's spelling of the repository is compared without regard to case
  git remote set-url origin https://github.com/BRC-DD/Hub.git
  run script/release --dry-run 0.2.0
  assert_success
  assert_output_lacks "but Formula/hub.rb is for"
  # a formula that names no repository stops the release
  : >Formula/hub.rb
  git commit -q -am "formula without REPO"
  run script/release --dry-run 0.2.0
  assert_failure
  assert_line_equals -1 "script/release: Formula/hub.rb does not set REPO"
  assert_output_lacks "git push"
  assert_gh_not_called
}
