#!/usr/bin/env bats
load ../test_helper

@test "issue with no arguments lists issues" {
  run hub --noop issue
  assert_success
  assert_output_equals "gh issue list"
  assert_gh_not_called
}

@test "issue with only options lists issues with them" {
  run hub --noop issue -s closed -a mislav -L 5
  assert_success
  assert_output_equals "gh issue list -s closed -a mislav -L 5"
}

@test "issue list and gh's other subcommands pass through unchanged, in order" {
  run hub --noop issue list --label bug -S "sort:updated-desc" --json number,title
  assert_success
  assert_output_equals "gh issue list --label bug -S sort:updated-desc --json number,title"
  run hub --noop issue transfer 12 mislav/other
  assert_success
  assert_output_equals "gh issue transfer 12 mislav/other"
  run hub --noop issue comment 12 --body +1 --some-new-flag x
  assert_success
  assert_output_equals "gh issue comment 12 --body +1 --some-new-flag x"
  run hub --noop issue close 12 -r duplicate --duplicate-of 7
  assert_success
  assert_output_equals "gh issue close 12 -r duplicate --duplicate-of 7"
}

@test "issue keeps -R given before the subcommand" {
  run hub --noop issue -R mislav/dotfiles show 12
  assert_success
  assert_output_equals "gh issue view -R mislav/dotfiles 12"
  run hub --noop issue --repo=mislav/dotfiles
  assert_success
  assert_output_equals "gh issue list --repo=mislav/dotfiles"
  run hub --noop issue -R mislav/dotfiles labels
  assert_success
  assert_output_equals "gh label list -R mislav/dotfiles"
}

@test "issue show is gh issue view" {
  run hub --noop issue show 12 --comments
  assert_success
  assert_output_equals "gh issue view 12 --comments"
}

@test "issue labels is gh label list" {
  run hub --noop issue labels -L 100 --sort name
  assert_success
  assert_output_equals "gh label list -L 100 --sort name"
}

@test "issue create -m with only a title sends an empty body" {
  run hub --noop issue create -m Crash -l bug
  assert_success
  assert_output_equals "gh issue create --title Crash --body '' -l bug"
}

@test "issue create -m splits the title from the body at the first blank line" {
  run hub --noop issue create -m $'Crash\non start\n\nSteps:\n1. run it'
  assert_success
  assert_output_equals "gh issue create --title Crash\\ on\\ start --body \$'Steps:\\n1. run it'"
}

@test "issue create joins repeated -m values as paragraphs" {
  run hub --noop issue create -m Crash -m "It crashes." -m Always.
  assert_success
  assert_output_equals "gh issue create --title Crash --body \$'It crashes.\\n\\nAlways.'"
}

@test "issue create accepts --message, --message= and -mMESSAGE" {
  run hub --noop issue create --message Crash
  assert_success
  assert_output_equals "gh issue create --title Crash --body ''"
  run hub --noop issue create --message=Crash -mDetails
  assert_success
  assert_output_equals "gh issue create --title Crash --body Details"
}

@test "issue create puts --title/--body where -m was and keeps gh's options in order" {
  run hub --noop issue create -l bug -m Crash --milestone v1 -a @me -m Details -p Roadmap
  assert_success
  assert_output_equals "gh issue create -l bug --title Crash --body Details --milestone v1 -a @me -p Roadmap"
}

@test "issue create -F reads the title and body from a file" {
  printf 'Crash on start\n\nSteps:\n1. run it\n' >msg.txt
  run hub --noop issue create -F msg.txt -l bug
  assert_success
  assert_output_equals "gh issue create --title Crash\\ on\\ start --body \$'Steps:\\n1. run it' -l bug"
  printf 'Crash\n' >title.txt
  run hub --noop issue create --file=title.txt
  assert_success
  assert_output_equals "gh issue create --title Crash --body ''"
}

@test "issue create -F - reads the title and body from standard input" {
  run hub --noop issue create -F - <<<$'Crash\n\nIt crashes.'
  assert_success
  assert_output_equals "gh issue create --title Crash --body It\\ crashes."
}

@test "issue create -m with gh's own body or template option adds no empty body" {
  run hub --noop issue create -m Crash --body-file notes.md
  assert_success
  assert_output_equals "gh issue create --title Crash --body-file notes.md"
  run hub --noop issue create -m Crash -T bug_report.md
  assert_success
  assert_output_equals "gh issue create --title Crash -T bug_report.md"
}

@test "issue create without -m or -F is gh issue create, unchanged" {
  run hub --noop issue create -t Crash -b "It crashes." -e -w
  assert_success
  assert_output_equals "gh issue create -t Crash -b It\\ crashes. -e -w"
}

@test "issue create does not take option values for hub's options" {
  run hub --noop issue create -t Crash -b -mnot-a-message --label -F
  assert_success
  assert_output_equals "gh issue create -t Crash -b -mnot-a-message --label -F"
}

@test "issue create aborts on -m with -F, a missing value or an unreadable file" {
  printf 'Crash\n' >msg.txt
  run hub --noop issue create -m Crash -F msg.txt
  assert_failure
  assert_output_equals "Aborted: -m and -F cannot be used together."
  run hub --noop issue create -l bug -m
  assert_failure
  assert_output_equals "Aborted: -m needs a value."
  run hub --noop issue create -F missing.txt
  assert_failure
  assert_output_equals "Aborted: cannot read missing.txt"
}

@test "issue update is gh issue edit, options unchanged" {
  run hub --noop issue update 12 -t "New title" --add-label bug --remove-label wip -m v2
  assert_success
  assert_output_equals "gh issue edit 12 -t New\\ title --add-label bug --remove-label wip -m v2"
}

@test "issue update -s closed closes the issue" {
  run hub --noop issue update 12 -s closed
  assert_success
  assert_output_equals "gh issue close 12"
  run hub --noop issue update https://github.com/mislav/dotfiles/issues/12 --state closed
  assert_success
  assert_output_equals "gh issue close https://github.com/mislav/dotfiles/issues/12"
}

@test "issue update -s open reopens the issue" {
  run hub --noop issue update 12 --state=open
  assert_success
  assert_output_equals "gh issue reopen 12"
  run hub --noop issue update -sopen 12
  assert_success
  assert_output_equals "gh issue reopen 12"
}

@test "issue update -s gives gh issue close its own options" {
  run hub --noop issue update 12 -s closed -c "Fixed in #13" -r "not planned"
  assert_success
  assert_output_equals "gh issue close 12 -c Fixed\\ in\\ #13 -r not\\ planned"
  run hub --noop issue update 12 -s closed --duplicate-of 7
  assert_success
  assert_output_equals "gh issue close 12 --duplicate-of 7"
}

@test "issue update -s with other options edits first, then closes; -R goes to both" {
  run hub --noop issue update 12 -t New --add-label fixed -s closed -R mislav/dotfiles -c Done
  assert_success
  assert_output_equals $'gh issue edit 12 -R mislav/dotfiles -t New --add-label fixed\ngh issue close 12 -R mislav/dotfiles -c Done'
}

@test "issue update -s aborts on an unknown state or a missing number" {
  run hub --noop issue update 12 -s merged
  assert_failure
  assert_output_equals "Aborted: --state must be open or closed, not 'merged'."
  run hub --noop issue update -s closed
  assert_failure
  assert_output_contains "Usage: hub issue update NUMBER"
}

@test "issue update -s does not close when the edit fails" {
  stub_gh 'issue edit 12 -t New' 'could not edit' 1
  stub_gh 'issue close 12' ''
  run hub issue update 12 -t New -s closed
  assert_failure
  assert_output_equals "could not edit"
  assert_gh_called 'issue edit 12 -t New'
  [[ $(gh_calls) != *"issue close"* ]]
}

@test "issue update -s runs gh issue edit, then gh issue close" {
  stub_gh 'issue edit 12 *' ''
  stub_gh 'issue close 12' 'Closed issue #12'
  run hub issue update 12 -t New -s closed
  assert_success
  assert_output_equals "Closed issue #12"
  [[ $(gh_calls) == $'gh issue edit 12 -t New\ngh issue close 12' ]]
}

@test "issue runs gh with the mapped arguments" {
  stub_gh 'issue list -s closed' '12\tCLOSED\tCrash'
  run hub issue -s closed
  assert_success
  assert_output_equals $'12\tCLOSED\tCrash'
  assert_gh_called 'issue list -s closed'
}

@test "issue -h and --help print the manual, also after hub's subcommands" {
  run hub issue --help
  assert_success
  assert_output_contains "Usage: hub issue"
  run hub issue -h
  assert_success
  assert_output_contains "Usage: hub issue"
  run hub --noop issue create -m Crash --help
  assert_success
  assert_output_contains "hub issue create -m MESSAGE"
  run hub --noop issue update 12 -h
  assert_success
  assert_output_contains "hub issue update NUMBER"
  run hub help issue
  assert_success
  assert_output_contains "Usage: hub issue"
  assert_gh_not_called
}

@test "issue SUBCOMMAND --help for gh's own subcommands is gh's help" {
  run hub --noop issue list --help
  assert_success
  assert_output_equals "gh issue list --help"
}
