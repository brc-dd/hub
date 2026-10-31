#!/usr/bin/env bats
load ../test_helper

@test "delete NAME deletes your repository of that name, after gh's confirmation" {
  run hub --noop delete dotfiles
  assert_success
  assert_output_equals "gh repo delete mislav/dotfiles"
  assert_equals "$(gh_calls)" "gh config get user -h github.com"
}

@test "delete OWNER/NAME, HOST/OWNER/NAME and a URL are passed as they are" {
  run hub --noop delete myorg/dotfiles
  assert_success
  assert_output_equals "gh repo delete myorg/dotfiles"
  run hub --noop delete ghe.example.com/corp/app
  assert_success
  assert_output_equals "gh repo delete ghe.example.com/corp/app"
  run hub --noop delete https://github.com/myorg/dotfiles
  assert_success
  assert_output_equals "gh repo delete https://github.com/myorg/dotfiles"
  assert_gh_not_called
}

@test "delete -y and --yes skip gh's confirmation; nothing else does" {
  run hub --noop delete -y dotfiles
  assert_success
  assert_output_equals "gh repo delete mislav/dotfiles --yes"
  run hub --noop delete myorg/dotfiles --yes
  assert_success
  assert_output_equals "gh repo delete myorg/dotfiles --yes"
  run hub --noop delete -- -y
  assert_failure
  assert_output_contains "hub delete: not a repository name: -y"
  local opt
  for opt in --yes=1 -yes --force -f --confirm; do
    run hub delete "$opt" myorg/dotfiles
    assert_failure
    assert_output_contains "hub delete: unknown option: "
    assert_output_contains "Usage: hub delete [-y] [OWNER/]NAME"
  done
  [[ $(gh_calls) != *"repo delete"* ]]
}

@test "delete runs gh once, with exactly the repository named, and exits with its status" {
  stub_gh 'repo delete myorg/dotfiles' 'Deleted repository myorg/dotfiles'
  run hub delete myorg/dotfiles
  assert_success
  assert_output_equals "Deleted repository myorg/dotfiles"
  assert_equals "$(gh_calls)" "gh repo delete myorg/dotfiles"
  : >"$HUB_TEST_LOG"
  stub_gh 'repo delete mislav/dotfiles --yes' 'X Failed to delete repository: Must have admin rights to Repository.' 1
  run hub delete -y dotfiles
  assert_failure
  assert_output_equals "X Failed to delete repository: Must have admin rights to Repository."
  assert_equals "$(gh_calls)" $'gh config get user -h github.com\ngh repo delete mislav/dotfiles --yes'
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

@test "delete needs exactly one repository, and a name that is one" {
  run hub --noop delete
  assert_failure
  assert_output_equals $'hub delete: name one repository\nUsage: hub delete [-y] [OWNER/]NAME'
  run hub --noop delete one two
  assert_failure
  assert_output_equals $'hub delete: name one repository\nUsage: hub delete [-y] [OWNER/]NAME'
  run hub --noop delete o/r/
  assert_failure
  assert_output_contains "hub delete: not a repository: o/r/"
  run hub --noop delete 'my repo'
  assert_failure
  assert_output_contains "hub delete: not a repository name: my repo"
  assert_gh_not_called
}

@test "delete --help mentions the delete_repo scope" {
  run hub delete --help
  assert_success
  assert_output_contains "gh auth refresh -s delete_repo"
  assert_output_contains "Usage: hub delete [-y] [OWNER/]NAME"
}
