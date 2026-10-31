#!/usr/bin/env bats
load ../test_helper

# shim_gh : a gh on PATH that prints its arguments and its standard input (give it one).
shim_gh() {
  mkdir -p "$HUB_TEST_TMP/shim"
  cat >"$HUB_TEST_TMP/shim/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s | stdin=%s\n' "$*" "$(cat)"
SH
  chmod +x "$HUB_TEST_TMP/shim/gh"
  SHIM_PATH=$HUB_TEST_TMP/shim:$PATH
}

@test "issue with no subcommand word is gh issue list, options in place" {
  run hub --noop issue
  assert_success
  assert_output_equals "gh issue list"
  run hub --noop issue -s closed -a mislav -L 5
  assert_success
  assert_output_equals "gh issue list -s closed -a mislav -L 5"
  run hub --noop issue --repo=mislav/dotfiles
  assert_success
  assert_output_equals "gh issue list --repo=mislav/dotfiles"
  run hub --noop issue -R mislav/dotfiles --label bug -S "sort:updated-desc"
  assert_success
  assert_output_equals "gh issue list -R mislav/dotfiles --label bug -S sort:updated-desc"
  assert_gh_not_called
}

@test "issue show is gh issue view, with every other argument in its place" {
  run hub --noop issue show 12 --comments
  assert_success
  assert_output_equals "gh issue view 12 --comments"
  run hub --noop issue -R mislav/dotfiles show 12
  assert_success
  assert_output_equals "gh issue -R mislav/dotfiles view 12"
  run hub --noop issue --repo=mislav/dotfiles show 12 -w
  assert_success
  assert_output_equals "gh issue --repo=mislav/dotfiles view 12 -w"
}

@test "issue passes gh's subcommands and options through unchanged, in order" {
  local args
  for args in "list --label bug --json number,title" "status" "transfer 12 mislav/other" \
    "comment 12 --body +1 --some-new-flag x" "close 12 -r duplicate --duplicate-of 7" "reopen 12 -c Again" \
    "edit 12 13 --add-label bug --remove-label wip" "create --title Crash --body-file notes.md -l bug" \
    "view https://github.com/mislav/dotfiles/issues/12" "develop 12 --checkout"; do
    # shellcheck disable=SC2086  # split on purpose
    run hub --noop issue $args
    assert_success
    assert_output_equals "gh issue $args"
  done
  assert_gh_not_called
}

@test "issue does not translate old hub's subcommands or options: they reach gh as typed" {
  run hub --noop issue labels -L 100
  assert_success
  assert_output_equals "gh issue labels -L 100"
  run hub --noop issue update 12 -s closed -c "Fixed in #14"
  assert_success
  assert_output_equals "gh issue update 12 -s closed -c Fixed\\ in\\ #14"
  run hub --noop issue update 12 13 -t New --add-label bug
  assert_success
  assert_output_equals "gh issue update 12 13 -t New --add-label bug"
  run hub --noop issue create -m Crash -l bug
  assert_success
  assert_output_equals "gh issue create -m Crash -l bug"
  run hub --noop issue create -F msg.txt -wmTitle
  assert_success
  assert_output_equals "gh issue create -F msg.txt -wmTitle"
  stub_gh 'issue update 12 -s closed' 'unknown command "update" for "gh issue"' 1
  run hub issue update 12 -s closed
  assert_failure
  assert_output_equals 'unknown command "update" for "gh issue"'
  assert_equals "$(gh_calls)" 'gh issue update 12 -s closed'
}

@test "issue: a batch is one gh command, which gh checks whole before its first request" {
  GH_REPO=default/repo run hub --noop issue update https://github.com/other/project/issues/1 2 -m Changed -s closed
  assert_success
  assert_output_equals "gh issue update https://github.com/other/project/issues/1 2 -m Changed -s closed"
  GH_REPO=default/repo run hub --noop issue update 1 not-an-issue -s closed
  assert_success
  assert_output_equals "gh issue update 1 not-an-issue -s closed"
  GH_REPO=default/repo run hub --noop issue edit https://github.com/other/project/issues/1 2 --title Changed
  assert_success
  assert_output_equals "gh issue edit https://github.com/other/project/issues/1 2 --title Changed"
  stub_gh 'issue close 1 not-an-issue' 'accepts 1 arg(s), received 2' 1
  GH_REPO=default/repo run hub issue close 1 not-an-issue
  assert_failure
  assert_output_equals 'accepts 1 arg(s), received 2'
  assert_equals "$(gh_calls)" 'gh issue close 1 not-an-issue'
}

@test "issue: nothing after -- is read, not even a subcommand word" {
  GH_REPO=github.localhost/intended/repo run hub --noop issue update --title Changed -- 1 --repo=github.localhost/other/repo
  assert_success
  assert_output_equals "gh issue update --title Changed -- 1 --repo=github.localhost/other/repo"
  GH_REPO=github.localhost/intended/repo run hub --noop issue edit --title Changed -- 1 --repo=github.localhost/other/repo
  assert_success
  assert_output_equals "gh issue edit --title Changed -- 1 --repo=github.localhost/other/repo"
  run hub --noop issue update 1 -- --title Changed
  assert_success
  assert_output_equals "gh issue update 1 -- --title Changed"
  run hub --noop issue close -r "not planned" -- 12 https://github.com/mislav/dotfiles/issues/13
  assert_success
  assert_output_equals "gh issue close -r not\\ planned -- 12 https://github.com/mislav/dotfiles/issues/13"
  run hub --noop issue -- show 12
  assert_success
  assert_output_equals "gh issue list -- show 12"
  run hub --noop issue -R mislav/dotfiles -- show 12
  assert_success
  assert_output_equals "gh issue list -R mislav/dotfiles -- show 12"
  assert_gh_not_called
}

@test "issue: closing as a duplicate is gh's one command; its repository and object checks are gh's too" {
  make_repo repo upstream=https://github.localhost/org/repo.git origin=https://github.localhost/alice/repo.git
  git config remote.origin.gh-resolved base
  run hub --noop issue close 12 --duplicate-of http://github.localhost/org/repo/issues/12
  assert_success
  assert_output_equals "gh issue close 12 --duplicate-of http://github.localhost/org/repo/issues/12"
  run hub --noop issue close 12 --duplicate-of http://github.localhost/alice/repo/issues/12
  assert_success
  assert_output_equals "gh issue close 12 --duplicate-of http://github.localhost/alice/repo/issues/12"
  run hub --noop issue update 12 --title Changed -s closed --duplicate-of http://github.localhost/alice/repo/issues/12
  assert_success
  assert_output_equals "gh issue update 12 --title Changed -s closed --duplicate-of http://github.localhost/alice/repo/issues/12"
  run hub --noop issue close http://github.localhost/o/r/pull/1 --duplicate-of 2
  assert_success
  assert_output_equals "gh issue close http://github.localhost/o/r/pull/1 --duplicate-of 2"
  run hub --noop issue close http://github.localhost/o/r/issues/1 --duplicate-of http://github.localhost/o/r/pull/2
  assert_success
  assert_output_equals "gh issue close http://github.localhost/o/r/issues/1 --duplicate-of http://github.localhost/o/r/pull/2"
  run hub --noop issue close 12 -r completed --duplicate-of 12 --duplicate-of 7
  assert_success
  assert_output_equals "gh issue close 12 -r completed --duplicate-of 12 --duplicate-of 7"
  assert_gh_not_called
}

@test "issue: titles, bodies and their files are gh's options; standard input reaches gh untouched" {
  run hub --noop issue update https://github.com/o/r/issues/1 -F '' -m Changed
  assert_success
  assert_output_equals "gh issue update https://github.com/o/r/issues/1 -F '' -m Changed"
  run hub --noop issue create -F '' --title T
  assert_success
  assert_output_equals "gh issue create -F '' --title T"
  run hub --noop issue create --title T --body-file -
  assert_success
  assert_output_equals "gh issue create --title T --body-file -"
  shim_gh
  PATH=$SHIM_PATH run hub issue create --title T --body-file - <<<$'Full title\n\nComplete body'
  assert_success
  assert_output_equals $'gh issue create --title T --body-file - | stdin=Full title\n\nComplete body'
}

@test "issue: whether an option is in effect is gh's to judge: --body-file= and --help=false reach gh as typed" {
  run hub --noop issue create -m Title --body-file=
  assert_success
  assert_output_equals "gh issue create -m Title --body-file="
  run hub --noop issue create --title T --body B --help=false
  assert_success
  assert_output_equals "gh issue create --title T --body B --help=false"
  run hub --noop issue edit 1 --title Title --help=false
  assert_success
  assert_output_equals "gh issue edit 1 --title Title --help=false"
  run hub --noop issue --help=false
  assert_success
  assert_output_equals "gh issue list --help=false"
  assert_gh_not_called
}

@test "issue finds the subcommand word where gh does: an option's value is never one" {
  run hub --noop issue -s show
  assert_success
  assert_output_equals "gh issue list -s show"
  run hub --noop issue --label show list
  assert_success
  assert_output_equals "gh issue --label show list"
  run hub --noop issue -sclosed show 12
  assert_success
  assert_output_equals "gh issue -sclosed view 12"
  run hub --noop issue '' show 12
  assert_success
  assert_output_equals "gh issue '' view 12"
  run hub --noop issue -R
  assert_success
  assert_output_equals "gh issue list -R"
}

@test "issue adds no repository of its own: gh resolves it from the remotes, GH_REPO or -R" {
  make_repo r1 origin=https://github.com/mislav/r1.git upstream=https://ghe.example.com/corp/r1.git
  run hub --noop issue view 12
  assert_success
  assert_output_equals "gh issue view 12"
  GH_REPO=ghe.example.com/corp/r1 run hub --noop issue close 12
  assert_success
  assert_output_equals "gh issue close 12"
  assert_gh_not_called
}

@test "issue -h and --help before the subcommand word print hub's manual; after it, gh's" {
  run hub issue --help
  assert_success
  assert_output_contains "Usage: hub issue [SUBCOMMAND] [gh issue options]"
  run hub issue -h
  assert_success
  assert_output_contains "Usage: hub issue"
  run hub issue -R mislav/dotfiles --help
  assert_success
  assert_output_contains "Usage: hub issue"
  run hub help issue
  assert_success
  assert_output_contains "Usage: hub issue"
  run hub --noop issue list --help
  assert_success
  assert_output_equals "gh issue list --help"
  run hub --noop issue create -h
  assert_success
  assert_output_equals "gh issue create -h"
  assert_gh_not_called
}

@test "issue hands over to gh and returns its output and status" {
  stub_gh 'issue list -s closed' '12\tCLOSED\tCrash'
  run hub issue -s closed
  assert_success
  assert_output_equals $'12\tCLOSED\tCrash'
  stub_gh 'issue view 404' 'GraphQL: Could not resolve to an issue' 1
  run hub issue show 404
  assert_failure
  assert_output_equals "GraphQL: Could not resolve to an issue"
  assert_equals "$(gh_calls)" $'gh issue list -s closed\ngh issue view 404'
}

@test "issue without gh gives hub's message" {
  mkdir nogh
  ln -s "$(command -v bash)" nogh/bash
  ln -s "$(command -v git)" nogh/git
  PATH=$PWD/nogh run hub issue
  assert_failure
  assert_output_equals "hub: this command needs the GitHub CLI (gh): https://cli.github.com"
}
