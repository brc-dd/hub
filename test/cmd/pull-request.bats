#!/usr/bin/env bats
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

@test "pull-request with no message lets gh prompt" {
  feature_repo
  run hub --noop pull-request
  assert_success
  assert_output_equals "gh pr create"
  assert_gh_not_called
}

@test "-m gives the title and an empty body, so gh does not prompt" {
  feature_repo
  run hub --noop pull-request -m "Fix the bug"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body ''"
}

@test "-m splits the first paragraph into the title and the rest into the body" {
  feature_repo
  run hub --noop pull-request -m $'Fix the\nbug\n\nIt was broken.\nNow it is not.\n'
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body \$'It was broken.\\nNow it is not.'"
}

@test "repeated -m are joined as paragraphs" {
  feature_repo
  run hub --noop pull-request -m "Fix the bug" -m "It was broken." -m "Now it is not."
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body \$'It was broken.\\n\\nNow it is not.'"
}

@test "-F reads the title and body from a file" {
  feature_repo
  printf 'Fix the bug\n\nIt was broken.\n' >"$HUB_TEST_TMP/msg.txt"
  run hub --noop pull-request -F "$HUB_TEST_TMP/msg.txt"
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body It\\ was\\ broken."
  run hub --noop pull-request -F <(printf 'From a pipe\n')
  assert_success
  assert_output_equals "gh pr create --title From\\ a\\ pipe --body ''"
}

@test "-F - reads the title and body from stdin" {
  feature_repo
  run hub --noop pull-request -F - <<<$'Fix the bug\n\nIt was broken.'
  assert_success
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body It\\ was\\ broken."
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
  assert_output_equals "gh pr create --title Fix\\ the\\ bug --body '' --editor"
  run hub --noop pull-request --edit
  assert_success
  assert_output_equals "gh pr create --editor"
}

@test "--no-edit uses the first commit's message" {
  feature_repo
  run hub --noop pull-request --no-edit
  assert_success
  assert_output_equals "gh pr create --fill-first"
}

@test "hub's base, head, draft, reviewer, assignee, milestone and label options become gh's" {
  feature_repo
  run hub --noop pull-request -b develop -h mislav:feature -d -r alice,bob -r org/team -a carol -M v1.0 -l bug,ui --no-maintainer-edits
  assert_success
  assert_output_equals "gh pr create --base develop --head mislav:feature --draft --reviewer alice,bob --reviewer org/team --assignee carol --milestone v1.0 --label bug,ui --no-maintainer-edit"
}

@test "long options, --opt=value and bundled short options are understood" {
  feature_repo
  run hub --noop pull-request --message="Fix it" --base=develop --head=feature --reviewer=alice --assign=carol --milestone=v1.0 --labels=bug --draft
  assert_success
  assert_output_equals "gh pr create --title Fix\\ it --body '' --base develop --head feature --draft --reviewer alice --assignee carol --milestone v1.0 --label bug"
  run hub --noop pull-request -dmFix -bdevelop
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --base develop --draft"
}

@test "options hub doesn't know are passed to gh unchanged" {
  feature_repo
  run hub --noop pull-request --fill -T template.md -R cli/cli --dry-run -w
  assert_success
  assert_output_equals "gh pr create --fill -T template.md -R cli/cli --dry-run -w"
  run hub --noop pull-request -m Fix -B release --assignee @me --project=Roadmap
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' -B release --assignee @me --project=Roadmap"
}

@test "-p pushes the current branch to origin before creating" {
  feature_repo
  run hub --noop pull-request -p -m Fix
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --title Fix --body \'\''
}

@test "-p pushes to the branch's push remote when one is configured" {
  feature_repo
  git remote add fork https://github.com/mislav/dotfiles-fork.git
  git config remote.pushDefault fork
  run hub --noop pull-request -p
  assert_success
  assert_output_equals $'git push --set-upstream fork HEAD\ngh pr create'
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

@test "-f names the pushed branch as the head, so gh neither pushes nor forks" {
  feature_repo
  run hub --noop pull-request -f -m Fix
  assert_success
  assert_output_equals "gh pr create --title Fix --body '' --head feature"
}

@test "-f in a fork clone names the fork's owner" {
  feature_repo origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  run hub --noop pull-request -f
  assert_success
  assert_output_equals "gh pr create --head mislav:feature"
}

@test "-f keeps an explicit -h, and -pf pushes first" {
  feature_repo
  run hub --noop pull-request -f -h other
  assert_success
  assert_output_equals "gh pr create --head other"
  run hub --noop pull-request -pf
  assert_success
  assert_output_equals $'git push --set-upstream origin HEAD\ngh pr create --head feature'
}

@test "-o prints the new pull request's URL and opens it" {
  feature_repo
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/7'
  export BROWSER='echo browse'
  run hub pull-request -o -m Fix
  assert_success
  assert_output_equals $'https://github.com/mislav/dotfiles/pull/7\nbrowse https://github.com/mislav/dotfiles/pull/7'
  assert_gh_called 'pr create --title Fix --body '
}

@test "-c copies the new pull request's URL" {
  feature_repo
  stub_clipboard
  stub_gh 'pr create *' 'https://github.com/mislav/dotfiles/pull/7'
  run hub pull-request -c -m Fix -d
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/pull/7"
  [[ $(cat "$HUB_TEST_TMP/clipboard") == "https://github.com/mislav/dotfiles/pull/7" ]]
  assert_gh_called 'pr create --title Fix --body  --draft'
}

@test "-o and -c under --noop print only the gh command" {
  feature_repo
  run hub --noop pull-request -o -c -m Fix
  assert_success
  assert_output_equals "gh pr create --title Fix --body ''"
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
  assert_output_equals "gh api repos/\\{owner\\}/\\{repo\\}/pulls -F issue=12 -F head=mislav:feature -f base=develop --jq .html_url"
  assert_gh_not_called
}

@test "-i accepts #N and defaults the base to the default branch" {
  feature_repo
  set_remote_head origin trunk
  run hub --noop pull-request --issue '#12'
  assert_success
  assert_output_equals "gh api repos/\\{owner\\}/\\{repo\\}/pulls -F issue=12 -F head=mislav:feature -f base=trunk --jq .html_url"
}

@test "an issue URL as the argument converts that issue in its own repository" {
  feature_repo
  run hub --noop pull-request https://github.com/mislav/dotfiles/issues/12 -b main
  assert_success
  assert_output_equals "gh api repos/mislav/dotfiles/pulls -F issue=12 -F head=mislav:feature -f base=main --jq .html_url"
  run hub --noop pull-request -i https://github.com/github/dotfiles/issues/3 -b main
  assert_success
  assert_output_equals "gh api repos/github/dotfiles/pulls -F issue=3 -F head=mislav:feature -f base=main --jq .html_url"
}

@test "-i takes the head owner from the push remote, or -h as given" {
  feature_repo origin=https://github.com/mislav/dotfiles.git upstream=https://github.com/github/dotfiles.git
  run hub --noop pull-request -i 12 -b main
  assert_success
  assert_output_equals "gh api repos/\\{owner\\}/\\{repo\\}/pulls -F issue=12 -F head=mislav:feature -f base=main --jq .html_url"
  run hub --noop pull-request -i 12 -b main -h someone:topic
  assert_success
  assert_output_equals "gh api repos/\\{owner\\}/\\{repo\\}/pulls -F issue=12 -F head=someone:topic -f base=main --jq .html_url"
}

@test "-p -i pushes first; -d and --no-maintainer-edits become API fields" {
  feature_repo
  run hub --noop pull-request -p -d --no-maintainer-edits -i 12 -b main
  assert_success
  assert_line_equals 0 "git push --set-upstream origin HEAD"
  assert_line_equals 1 "gh api repos/\\{owner\\}/\\{repo\\}/pulls -F issue=12 -F head=mislav:feature -f base=main -F draft=true -F maintainer_can_modify=false --jq .html_url"
  [[ ${#lines[@]} -eq 2 ]]
}

@test "-i on GitHub Enterprise passes --hostname" {
  git config --global --add hub.host ghe.example.com
  feature_repo origin=https://ghe.example.com/mislav/dotfiles.git
  run hub --noop pull-request -i 12 -b main
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com repos/\\{owner\\}/\\{repo\\}/pulls -F issue=12 -F head=mislav:feature -f base=main --jq .html_url"
}

@test "-i with -o opens the converted pull request" {
  feature_repo
  stub_gh 'api repos/{owner}/{repo}/pulls -F issue=12 *' 'https://github.com/mislav/dotfiles/pull/12'
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
  assert_output_equals "gh pr create --title Fix --body '' --body https://github.com/mislav/dotfiles/issues/12"
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
