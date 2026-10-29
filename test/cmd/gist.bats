#!/usr/bin/env bats
load ../test_helper

@test "gist create FILES is gh gist create" {
  run hub --noop gist create a.txt b.md -d Notes
  assert_success
  assert_output_equals "gh gist create a.txt b.md -d Notes"
  assert_gh_not_called
}

@test "gist create --public becomes -p" {
  run hub --noop gist create --public a.txt
  assert_success
  assert_output_equals "gh gist create -p a.txt"
}

@test "gist create -o and --browse become -w" {
  run hub --noop gist create -o a.txt
  assert_success
  assert_output_equals "gh gist create -w a.txt"
  run hub --noop gist create a.txt --browse --public
  assert_success
  assert_output_equals "gh gist create a.txt -w -p"
}

@test "gist create without files leaves gh to read standard input" {
  run hub --noop gist create --public -f notes.md
  assert_success
  assert_output_equals "gh gist create -p -f notes.md"
  run hub --noop gist create - a.txt
  assert_success
  assert_output_equals "gh gist create - a.txt"
}

@test "gist create keeps gh's options and their values unchanged" {
  run hub --noop gist create -p -w -d "-o is not --browse" --filename -o a.txt
  assert_success
  assert_output_equals "gh gist create -p -w -d -o\\ is\\ not\\ --browse --filename -o a.txt"
}

@test "gist show ID is gh gist view ID --raw" {
  run hub --noop gist show 8f3c4e2
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 --raw"
}

@test "gist show ID FILENAME picks the file with --filename" {
  run hub --noop gist show 8f3c4e2 notes.md
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 --raw --filename notes.md"
  run hub --noop gist show https://gist.github.com/mislav/8f3c4e2 notes.md
  assert_success
  assert_output_equals "gh gist view https://gist.github.com/mislav/8f3c4e2 --raw --filename notes.md"
}

@test "gist show keeps gh's own options" {
  run hub --noop gist show 8f3c4e2 --web
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 --raw --web"
  run hub --noop gist show 8f3c4e2 -f notes.md
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 --raw -f notes.md"
}

@test "gist passes gh's other subcommands through unchanged" {
  run hub --noop gist list --public -L 5
  assert_success
  assert_output_equals "gh gist list --public -L 5"
  run hub --noop gist view 8f3c4e2 --files
  assert_success
  assert_output_equals "gh gist view 8f3c4e2 --files"
  run hub --noop gist edit 8f3c4e2 -a new.txt
  assert_success
  assert_output_equals "gh gist edit 8f3c4e2 -a new.txt"
  run hub --noop gist delete 8f3c4e2 --yes
  assert_success
  assert_output_equals "gh gist delete 8f3c4e2 --yes"
}

@test "gist show runs gh gist view" {
  stub_gh 'gist view 8f3c4e2 --raw --filename notes.md' 'hello'
  run hub gist show 8f3c4e2 notes.md
  assert_success
  assert_output_equals "hello"
  assert_gh_called 'gist view 8f3c4e2 --raw --filename notes.md'
}

@test "gist create runs gh gist create with standard input" {
  stub_gh 'gist create -p' 'https://gist.github.com/mislav/8f3c4e2'
  run hub gist create --public <<<"hello"
  assert_success
  assert_output_equals "https://gist.github.com/mislav/8f3c4e2"
}

@test "gist without a subcommand, -h and --help print the manual" {
  run hub gist
  assert_success
  assert_output_contains "Usage: hub gist create"
  run hub gist --help
  assert_success
  assert_output_contains "Usage: hub gist create"
  run hub --noop gist create -o -h
  assert_success
  assert_output_contains "hub gist show ID [FILENAME]"
  run hub --noop gist show 8f3c4e2 --help
  assert_success
  assert_output_contains "Usage: hub gist create"
  run hub help gist
  assert_success
  assert_output_contains "Usage: hub gist create"
  assert_gh_not_called
}
