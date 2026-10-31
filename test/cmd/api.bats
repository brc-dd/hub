#!/usr/bin/env bats
load ../test_helper

# shim_gh : a gh on PATH that prints its arguments, GH_HOST and its standard input (give it one).
shim_gh() {
  mkdir -p "$HUB_TEST_TMP/shim"
  cat >"$HUB_TEST_TMP/shim/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s | GH_HOST=%s | stdin=%s\n' "$*" "${GH_HOST-}" "$(cat)"
SH
  chmod +x "$HUB_TEST_TMP/shim/gh"
  SHIM_PATH=$HUB_TEST_TMP/shim:$PATH
}

@test "api is gh api, arguments unchanged and in order" {
  run hub --noop api -X POST 'repos/{owner}/{repo}/issues' -F title=Bug -f body=x -H 'Accept: application/json' -i --paginate --input data.json --some-new-flag
  assert_success
  assert_output_equals "gh api -X POST repos/\\{owner\\}/\\{repo\\}/issues -F title=Bug -f body=x -H Accept:\\ application/json -i --paginate --input data.json --some-new-flag"
  run hub --noop api graphql -F owner='{owner}' -f query=@q.graphql --paginate --slurp --jq .data
  assert_success
  assert_output_equals "gh api graphql -F owner=\\{owner\\} -f query=@q.graphql --paginate --slurp --jq .data"
  run hub --noop api user --template '{{.login}}' -q .login
  assert_success
  assert_output_equals "gh api user --template \\{\\{.login\\}\\} -q .login"
  run hub --noop api
  assert_success
  assert_output_equals "gh api"
  assert_gh_not_called
}

@test "api does not translate old hub's options: they reach gh as typed" {
  run hub --noop api -t users/octocat
  assert_success
  assert_output_equals "gh api -t users/octocat"
  run hub --noop api users/octocat --flat -i
  assert_success
  assert_output_equals "gh api users/octocat --flat -i"
  run hub --noop api -it users/octocat
  assert_success
  assert_output_equals "gh api -it users/octocat"
  run hub --noop api --cache 600 user
  assert_success
  assert_output_equals "gh api --cache 600 user"
  run hub --noop api user --cache=3600 --obey-ratelimit --color
  assert_success
  assert_output_equals "gh api user --cache=3600 --obey-ratelimit --color"
  run hub --noop api --cache 1h user
  assert_success
  assert_output_equals "gh api --cache 1h user"
  stub_gh 'api --cache 600 user' 'invalid argument "600" for "--cache" flag: time: missing unit in duration "600"' 1
  run hub api --cache 600 user
  assert_failure
  assert_output_equals 'invalid argument "600" for "--cache" flag: time: missing unit in duration "600"'
  assert_equals "$(gh_calls)" 'gh api --cache 600 user'
}

@test "api: option values, clusters and everything after -- are gh's to read" {
  run hub --noop api users/octocat -H 'X-Note: -t' -f q=-t --jq -t
  assert_success
  assert_output_equals "gh api users/octocat -H X-Note:\\ -t -f q=-t --jq -t"
  run hub --noop api -iXPOST 'repos/{owner}/{repo}/issues' -Ftitle=Bug -fbody=text -XGET -i
  assert_success
  assert_output_equals "gh api -iXPOST repos/\\{owner\\}/\\{repo\\}/issues -Ftitle=Bug -fbody=text -XGET -i"
  run hub --noop api users/octocat -- -t --help
  assert_success
  assert_output_equals "gh api users/octocat -- -t --help"
  run hub --noop api --help=false user
  assert_success
  assert_output_equals "gh api --help=false user"
  assert_gh_not_called
}

@test "api leaves the host to gh: --hostname and GH_HOST reach it as they are, GITHUB_HOST as GH_HOST" {
  run hub --noop api --hostname ghe.example.com user
  assert_success
  assert_output_equals "gh api --hostname ghe.example.com user"
  shim_gh
  GH_HOST=ghe.example.com PATH=$SHIM_PATH run hub api user </dev/null
  assert_success
  assert_output_equals "gh api user | GH_HOST=ghe.example.com | stdin="
  GITHUB_HOST=ghe.example.com PATH=$SHIM_PATH run hub api user </dev/null
  assert_success
  assert_output_equals "gh api user | GH_HOST=ghe.example.com | stdin="
  GH_HOST=one.example.com GITHUB_HOST=two.example.com PATH=$SHIM_PATH run hub api user </dev/null
  assert_success
  assert_output_equals "gh api user | GH_HOST=one.example.com | stdin="
}

@test "api adds no repository of its own: placeholders are gh's to fill from the remotes, GH_REPO or -R" {
  make_repo r1 origin=https://github.com/mislav/r1.git upstream=https://ghe.example.com/corp/r1.git
  run hub --noop api 'repos/{owner}/{repo}/releases'
  assert_success
  assert_output_equals "gh api repos/\\{owner\\}/\\{repo\\}/releases"
  GH_REPO=ghe.example.com/corp/r1 run hub --noop api 'repos/{owner}/{repo}'
  assert_success
  assert_output_equals "gh api repos/\\{owner\\}/\\{repo\\}"
  assert_gh_not_called
}

@test "api --input - reads standard input through gh, not hub" {
  shim_gh
  PATH=$SHIM_PATH run hub api graphql --input - <<<'{"query":"{viewer{login}}"}'
  assert_success
  assert_output_equals 'gh api graphql --input - | GH_HOST= | stdin={"query":"{viewer{login}}"}'
}

@test "api -h and --help print hub's manual; anywhere else they are gh's" {
  run hub api --help
  assert_success
  assert_output_contains "Usage: hub api ENDPOINT [gh api options]"
  run hub api -h
  assert_success
  assert_output_contains "Usage: hub api"
  run hub help api
  assert_success
  assert_output_contains "Usage: hub api"
  run hub --noop api user --help
  assert_success
  assert_output_equals "gh api user --help"
  run hub --noop api user -h
  assert_success
  assert_output_equals "gh api user -h"
  assert_gh_not_called
}

@test "api hands over to gh and returns its output and status" {
  stub_gh 'api user --jq .login' 'mislav'
  run hub api user --jq .login
  assert_success
  assert_output_equals "mislav"
  stub_gh 'api repos/x/y' '{"message":"Not Found"}' 1
  run hub api repos/x/y
  assert_failure
  assert_output_equals '{"message":"Not Found"}'
  assert_equals "$(gh_calls)" $'gh api user --jq .login\ngh api repos/x/y'
}

@test "api without gh gives hub's message" {
  mkdir nogh
  ln -s "$(command -v bash)" nogh/bash
  ln -s "$(command -v git)" nogh/git
  PATH=$PWD/nogh run hub api user
  assert_failure
  assert_output_equals "hub: this command needs the GitHub CLI (gh): https://cli.github.com"
}
