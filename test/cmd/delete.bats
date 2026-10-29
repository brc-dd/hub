#!/usr/bin/env bats
load ../test_helper

@test "delete NAME deletes your repository of that name" {
  run hub --noop delete dotfiles
  assert_success
  assert_output_equals "gh repo delete mislav/dotfiles"
  assert_gh_called 'config get user -h github.com'
}

@test "delete OWNER/NAME and HOST/OWNER/NAME are passed as they are" {
  run hub --noop delete myorg/dotfiles
  assert_success
  assert_output_equals "gh repo delete myorg/dotfiles"
  run hub --noop delete ghe.example.com/corp/app
  assert_success
  assert_output_equals "gh repo delete ghe.example.com/corp/app"
  assert_gh_not_called
}

@test "delete -y and --yes skip gh's confirmation" {
  run hub --noop delete -y dotfiles
  assert_success
  assert_output_equals "gh repo delete mislav/dotfiles --yes"
  run hub --noop delete myorg/dotfiles --yes
  assert_output_equals "gh repo delete myorg/dotfiles --yes"
}

@test "delete uses your login on GH_HOST" {
  stub_gh 'config get user -h ghe.example.com' 'mona'
  GH_HOST=ghe.example.com run hub --noop delete app
  assert_success
  assert_output_equals "gh repo delete mona/app"
}

@test "delete GITHUB_HOST: gh deletes on the host hub resolved the login on" {
  mkdir "$HUB_TEST_TMP/shim"
  cat >"$HUB_TEST_TMP/shim/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s | GH_HOST=%s\n' "$*" "${GH_HOST-}" >>"$HUB_TEST_LOG"
if [[ $* == 'config get user -h '* ]]; then echo mona; fi
SH
  chmod +x "$HUB_TEST_TMP/shim/gh"
  PATH=$HUB_TEST_TMP/shim:$PATH GITHUB_HOST=ghe.example.com run hub delete -y owner/repo
  assert_success
  assert_gh_called 'repo delete owner/repo --yes | GH_HOST=ghe.example.com'
  PATH=$HUB_TEST_TMP/shim:$PATH GITHUB_HOST=ghe.example.com run hub delete -y app
  assert_success
  assert_gh_called 'config get user -h ghe.example.com | GH_HOST=ghe.example.com'
  assert_gh_called 'repo delete mona/app --yes | GH_HOST=ghe.example.com'
}

@test "delete runs gh and reports its failure" {
  stub_gh 'repo delete mislav/dotfiles --yes' '' 1
  run hub delete -y dotfiles
  assert_failure
  assert_gh_called 'repo delete mislav/dotfiles --yes'
}

@test "delete needs exactly one repository" {
  run hub --noop delete
  assert_failure
  assert_output_equals "Usage: hub delete [-y] [OWNER/]NAME"
  run hub --noop delete one two
  assert_failure
  assert_output_equals "Usage: hub delete [-y] [OWNER/]NAME"
  run hub --noop delete --force dotfiles
  assert_failure
  assert_output_contains "unknown option: --force"
  assert_gh_not_called
}

@test "delete --help mentions the delete_repo scope" {
  run hub delete --help
  assert_success
  assert_output_contains "gh auth refresh -s delete_repo"
}
