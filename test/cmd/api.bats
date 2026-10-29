#!/usr/bin/env bats
load ../test_helper

@test "api is gh api, arguments unchanged and in order" {
  run hub --noop api -X POST 'repos/{owner}/{repo}/issues' -F title=Bug -f body=x -H 'Accept: application/json' -i --paginate --input data.json --some-new-flag
  assert_success
  assert_output_equals "gh api -X POST repos/\\{owner\\}/\\{repo\\}/issues -F title=Bug -f body=x -H Accept:\\ application/json -i --paginate --input data.json --some-new-flag"
  assert_gh_not_called
}

@test "api graphql and gh's output options pass through unchanged" {
  run hub --noop api graphql -F owner='{owner}' -f query=@q.graphql --paginate --slurp --jq .data
  assert_success
  assert_output_equals "gh api graphql -F owner=\\{owner\\} -f query=@q.graphql --paginate --slurp --jq .data"
  run hub --noop api user --template '{{.login}}' -q .login
  assert_success
  assert_output_equals "gh api user --template \\{\\{.login\\}\\} -q .login"
}

@test "api with no arguments is gh api" {
  run hub --noop api
  assert_success
  assert_output_equals "gh api"
}

@test "api -t is dropped with a warning, since gh's -t means --template" {
  run hub --noop api -t users/octocat
  assert_success
  assert_line_equals 0 "hub: ignoring -t/--flat: gh api has no flat output; use --jq or --template instead"
  assert_line_equals 1 "gh api users/octocat"
  [[ ${#lines[@]} -eq 2 ]]
}

@test "api --flat is dropped with a warning too" {
  run hub --noop api users/octocat --flat -i
  assert_success
  assert_output_equals $'hub: ignoring -t/--flat: gh api has no flat output; use --jq or --template instead\ngh api users/octocat -i'
}

@test "api leaves -t alone as the value of another option or after --" {
  run hub --noop api users/octocat -H 'X-Note: -t' -f q=-t --jq -t
  assert_success
  assert_output_equals "gh api users/octocat -H X-Note:\\ -t -f q=-t --jq -t"
  run hub --noop api users/octocat -- -t
  assert_success
  assert_output_equals "gh api users/octocat -- -t"
}

@test "api --cache with a bare number of seconds gets gh's unit" {
  run hub --noop api --cache 600 user
  assert_success
  assert_output_equals "gh api --cache 600s user"
  run hub --noop api user --cache=3600
  assert_success
  assert_output_equals "gh api user --cache=3600s"
}

@test "api --cache with a duration is unchanged" {
  run hub --noop api --cache 1h user
  assert_success
  assert_output_equals "gh api --cache 1h user"
  run hub --noop api --cache=90m user
  assert_success
  assert_output_equals "gh api --cache=90m user"
}

@test "api runs gh api" {
  stub_gh 'api user --jq .login' 'mislav'
  run hub api user --jq .login
  assert_success
  assert_output_equals "mislav"
  assert_gh_called 'api user --jq .login'
}

@test "api passes gh's exit status through" {
  stub_gh 'api repos/x/y' '{"message":"Not Found"}' 1
  run hub api repos/x/y
  assert_failure
  assert_output_equals '{"message":"Not Found"}'
}

@test "api -h and --help print the manual" {
  run hub api --help
  assert_success
  assert_output_contains "Usage: hub api ENDPOINT"
  run hub api user -h
  assert_success
  assert_output_contains "--cache N"
  run hub help api
  assert_success
  assert_output_contains "Usage: hub api ENDPOINT"
  assert_gh_not_called
}
