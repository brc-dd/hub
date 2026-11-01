#!/usr/bin/env bats
# hub api: gh api with every argument unchanged.

load test_helper

# A gh that records GH_HOST, GH_REPO and then one argument per line in args (and with "stdin" its
# standard input in stdin), to see what the stub's log does not show: the environment and word
# boundaries.
make_recording_gh() {
  local read_stdin=
  [[ ${1-} != stdin ]] || read_stdin="cat >\"$HUB_TEST_TMP/stdin\""
  mkdir -p "$HUB_TEST_TMP/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s "$@" >"%s/args"\n%s\n' \
    '"${GH_HOST-unset}" "${GH_REPO-unset}"' "$HUB_TEST_TMP" "$read_stdin" >"$HUB_TEST_TMP/bin/gh"
  chmod +x "$HUB_TEST_TMP/bin/gh"
}

@test "hub api runs gh api with the arguments as given" {
  stub_gh 'api *' '"v2.7.0"'
  run hub api 'repos/{owner}/{repo}/releases' --jq '.[0].tag_name'
  assert_success
  assert_output_equals '"v2.7.0"'
  assert_equals "$(gh_calls)" 'gh api repos/{owner}/{repo}/releases --jq .[0].tag_name'
}

@test "hub api keeps every argument whole and in order, options and -- included" {
  make_recording_gh
  PATH=$HUB_TEST_TMP/bin:$PATH run hub api -XPATCH -t '{{.name}}' --help=false \
    -f 'body=two words' -F n=1 -H '' repos/mislav/hub -- --paginate
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' unset unset api -XPATCH -t '{{.name}}' --help=false \
    -f 'body=two words' -F n=1 -H '' repos/mislav/hub -- --paginate)"
}

@test "hub api adds no host or repository inside a repository" {
  make_repo work origin=https://github.com/mislav/hub.git
  make_recording_gh
  PATH=$HUB_TEST_TMP/bin:$PATH run hub api 'repos/{owner}/{repo}'
  assert_success
  assert_equals "$(<"$HUB_TEST_TMP/args")" "$(printf '%s\n' unset unset api 'repos/{owner}/{repo}')"
}

@test "hub api gives gh its standard input" {
  make_recording_gh stdin
  PATH=$HUB_TEST_TMP/bin:$PATH run hub api graphql --input - <<<'{"query":"{viewer{login}}"}'
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' unset unset api graphql --input -)"
  assert_equals "$(<stdin)" '{"query":"{viewer{login}}"}'
}

@test "hub api passes hub 2.x's GITHUB_HOST to gh as GH_HOST" {
  make_recording_gh
  GITHUB_HOST=ghe.example.com PATH=$HUB_TEST_TMP/bin:$PATH run hub api user
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' ghe.example.com unset api user)"
}

@test "hub api keeps GH_HOST over GITHUB_HOST" {
  make_recording_gh
  GH_HOST=github.example.com GITHUB_HOST=ghe.example.com PATH=$HUB_TEST_TMP/bin:$PATH \
    run hub api user
  assert_success
  assert_equals "$(<args)" "$(printf '%s\n' github.example.com unset api user)"
}

@test "hub api exits with gh's status and keeps its output and messages apart" {
  mkdir -p bin
  printf '#!/usr/bin/env bash\necho partial\necho "gh: Not Found (HTTP 404)" >&2\nexit 4\n' >bin/gh
  chmod +x bin/gh
  PATH=$HUB_TEST_TMP/bin:$PATH run --separate-stderr hub api repos/mislav/nope
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
  mkdir nogh
  ln -s "$(command -v git)" nogh/git
  ln -s "$(command -v bash)" nogh/bash
  PATH=$HUB_TEST_TMP/nogh:/usr/bin:/bin run hub api user
  assert_status 1
  assert_output_equals 'hub api: this command needs the GitHub CLI, gh (https://cli.github.com)'
}
