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

flat_error="hub api: -t/--flat is not supported: gh api has no flat KEY<TAB>VALUE output; use --jq or --template instead"

@test "api -t and --flat are errors (exit 2), not JSON in place of hub 2.x's flat lines" {
  run hub --noop api -t users/octocat
  assert_output_equals "$flat_error"
  [[ $status -eq 2 ]]
  run hub --noop api users/octocat --flat -i
  assert_output_equals "$flat_error"
  [[ $status -eq 2 ]]
  assert_gh_not_called
}

@test "api -t is an error bundled with -i or with a value too, as gh would read it as --template" {
  local arg
  for arg in -it -ti -iit '-t{{.login}}'; do
    run hub --noop api "$arg" users/octocat
    assert_output_equals "$flat_error"
    [[ $status -eq 2 ]] || {
      printf 'expected exit 2 for %s, got %s\n' "$arg" "$status"
      return 1
    }
  done
}

@test "api -t fails without running gh" {
  run hub api users/octocat -t
  assert_output_equals "$flat_error"
  [[ $status -eq 2 ]]
  assert_gh_not_called
}

@test "api leaves -t alone as the value of another option or after --" {
  run hub --noop api users/octocat -H 'X-Note: -t' -f q=-t --jq -t
  assert_success
  assert_output_equals "gh api users/octocat -H X-Note:\\ -t -f q=-t --jq -t"
  run hub --noop api users/octocat -iH 'X-Note: -t' -iq -t
  assert_success
  assert_output_equals "gh api users/octocat -iH X-Note:\\ -t -iq -t"
  run hub --noop api users/octocat -- -t
  assert_success
  assert_output_equals "gh api users/octocat -- -t"
}

@test "api passes gh's other short options through, alone or bundled" {
  run hub --noop api -iXPOST 'repos/{owner}/{repo}/issues' -Ftitle=Bug -fbody=text -XGET -i
  assert_success
  assert_output_equals "gh api -iXPOST repos/\\{owner\\}/\\{repo\\}/issues -Ftitle=Bug -fbody=text -XGET -i"
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
