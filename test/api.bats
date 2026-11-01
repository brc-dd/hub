#!/usr/bin/env bats
# hub api: gh api with every argument unchanged.

load test_helper

@test "hub api runs gh api with the arguments as given" {
  stub_gh 'api *' '"v2.7.0"'
  run hub api 'repos/{owner}/{repo}/releases' --jq '.[0].tag_name'
  assert_success
  assert_output_equals '"v2.7.0"'
  assert_equals "$(gh_calls)" 'gh api repos/{owner}/{repo}/releases --jq .[0].tag_name'
}

@test "hub api keeps every argument whole and in order, options and -- included" {
  stub_gh 'api *' ''
  PATH=$(recording_gh):$PATH run hub api -XPATCH -t '{{.name}}' --help=false \
    -f 'body=two words' -F n=1 -H '' repos/mislav/hub -- --paginate
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' api -XPATCH -t '{{.name}}' --help=false \
    -f 'body=two words' -F n=1 -H '' repos/mislav/hub -- --paginate)"
}

@test "hub api adds no host or repository inside a repository" {
  make_repo work origin=https://github.com/mislav/hub.git
  stub_gh 'api *' ''
  PATH=$(recording_gh):$PATH run hub api 'repos/{owner}/{repo}'
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/args")" "$(printf '%s\n' api 'repos/{owner}/{repo}')"
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=unset GH_REPO=unset'
}

@test "hub api gives gh its standard input" {
  stub_gh 'api *' ''
  PATH=$(recording_gh stdin):$PATH run hub api graphql --input - <<<'{"query":"{viewer{login}}"}'
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' api graphql --input -)"
  assert_equals "$(<stdin)" '{"query":"{viewer{login}}"}'
}

@test "hub api passes hub 2.x's GITHUB_HOST to gh as GH_HOST" {
  stub_gh 'api *' ''
  GITHUB_HOST=ghe.example.com PATH=$(recording_gh):$PATH run hub api user
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=ghe.example.com GH_REPO=unset'
  assert_equals "$(gh_calls)" 'gh api user'
}

@test "hub api keeps GH_HOST over GITHUB_HOST" {
  stub_gh 'api *' ''
  GH_HOST=github.example.com GITHUB_HOST=ghe.example.com PATH=$(recording_gh):$PATH \
    run hub api user
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/env")" 'GH_HOST=github.example.com GH_REPO=unset'
  assert_equals "$(gh_calls)" 'gh api user'
}

@test "hub api exits with gh's status and keeps its output and messages apart" {
  stub_gh 'api repos/mislav/nope' partial 4
  PATH=$(failing_gh 'gh: Not Found (HTTP 404)'):$PATH \
    run --separate-stderr hub api repos/mislav/nope
  assert_status 4
  assert_output_equals partial
  assert_equals "$stderr" 'gh: Not Found (HTTP 404)'
}

@test "hub api without arguments leaves the complaint to gh" {
  stub_gh 'api' 'accepts 1 arg(s), received 0' 2
  run hub api
  assert_status 2
  assert_output_equals 'accepts 1 arg(s), received 0'
  assert_equals "$(gh_calls)" 'gh api'
}

@test "hub api --help and -h as the first argument print hub's manual" {
  run hub api --help
  assert_success
  assert_line_equals 0 'Summary: Make an authenticated GitHub API request (gh api).'
  assert_line_equals 1 'Usage: hub api ENDPOINT [GH-API-ARGS...]'
  run hub api -h user
  assert_success
  assert_line_equals 0 'Summary: Make an authenticated GitHub API request (gh api).'
  assert_gh_not_called
}

@test "hub api --help after the first argument is gh's" {
  stub_gh 'api user --help' 'Makes an authenticated HTTP request to the GitHub API.'
  run hub api user --help
  assert_success
  assert_output_equals 'Makes an authenticated HTTP request to the GitHub API.'
  assert_equals "$(gh_calls)" 'gh api user --help'
}

@test "hub api -h after the first argument is gh's" {
  stub_gh 'api user -h' 'Makes an authenticated HTTP request to the GitHub API.'
  run hub api user -h
  assert_success
  assert_output_equals 'Makes an authenticated HTTP request to the GitHub API.'
  assert_equals "$(gh_calls)" 'gh api user -h'
}

@test "hub api -- --help goes to gh unchanged" {
  stub_gh 'api -- --help' 'accepts 1 arg(s)'
  run hub api -- --help
  assert_success
  assert_output_equals 'accepts 1 arg(s)'
  assert_equals "$(gh_calls)" 'gh api -- --help'
}

@test "hub help api prints the same manual" {
  run hub api --help
  assert_success
  local manual=$output
  assert_output_contains 'gh api --cache 600s'
  run hub help api
  assert_success
  assert_output_equals "$manual"
}

@test "hub --noop api prints the gh command" {
  run hub --noop api -X DELETE 'repos/{owner}/{repo}/git/refs/heads/old topic'
  assert_success
  assert_output_equals 'gh api -X DELETE repos/\{owner\}/\{repo\}/git/refs/heads/old\ topic'
  assert_gh_not_called
}

@test "hub api without gh says gh is needed" {
  PATH=$(no_gh_path) run hub api user
  assert_status 1
  assert_output_equals 'hub api: this command needs the GitHub CLI, gh (https://cli.github.com)'
}
