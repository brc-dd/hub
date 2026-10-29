#!/usr/bin/env bats
load ../test_helper

@test "create makes a private repository from the current one by default" {
  make_repo dotfiles
  run hub --noop create
  assert_success
  assert_output_equals "gh repo create --source=. --remote=origin --private"
}

@test "create --public makes it public; -p and --private keep it private" {
  make_repo dotfiles
  run hub --noop create --public
  assert_success
  assert_output_equals "gh repo create --source=. --remote=origin --public"
  run hub --noop create -p
  assert_output_equals "gh repo create --source=. --remote=origin --private"
  run hub --noop create --public --private
  assert_output_equals "gh repo create --source=. --remote=origin --private"
  run hub --noop create --internal myorg/app
  assert_output_equals "gh repo create myorg/app --source=. --remote=origin --internal"
}

@test "create NAME and ORG/NAME name the repository" {
  make_repo dotfiles
  run hub --noop create my-dots
  assert_success
  assert_output_equals "gh repo create my-dots --source=. --remote=origin --private"
  run hub --noop create myorg/dotfiles
  assert_output_equals "gh repo create myorg/dotfiles --source=. --remote=origin --private"
}

@test "create passes the description and home page" {
  make_repo dotfiles
  run hub --noop create -d 'My dotfiles' -h https://example.com/dots
  assert_success
  assert_output_equals 'gh repo create --source=. --remote=origin --private -d My\ dotfiles -h https://example.com/dots'
  run hub --noop create --description=Dots --homepage=https://example.com
  assert_output_equals "gh repo create --source=. --remote=origin --private -d Dots -h https://example.com"
}

@test "create --remote-name names the new remote" {
  make_repo dotfiles origin=https://gitlab.com/mislav/dotfiles.git
  run hub --noop create --remote-name github
  assert_success
  assert_output_equals "gh repo create --source=. --remote=github --private"
}

@test "create passes other gh options through, and does not push by default" {
  make_repo dotfiles
  run hub --noop create --push --license=mit
  assert_success
  assert_output_equals "gh repo create --source=. --remote=origin --private --push --license=mit"
}

@test "create -o opens the new repository afterwards" {
  make_repo dotfiles
  run hub --noop create -o
  assert_success
  assert_output_equals $'gh repo create --source=. --remote=origin --private\nopen https://github.com/mislav/dotfiles'
  run hub --noop create --browse myorg/new.repo
  assert_output_equals $'gh repo create myorg/new.repo --source=. --remote=origin --private\nopen https://github.com/myorg/new.repo'
  run hub --noop create -o other.git
  assert_line_equals 1 "open https://github.com/mislav/other"
}

@test "create -o names the URL the way GitHub names the repository" {
  make_repo 'my dot+files'
  run hub --noop create -o
  assert_success
  assert_line_equals 1 "open https://github.com/mislav/my-dot-files"
}

@test "create -o uses GH_HOST and your login there" {
  make_repo app
  stub_gh 'config get user -h ghe.example.com' 'mona'
  GH_HOST=ghe.example.com run hub --noop create -o
  assert_success
  assert_line_equals 1 "open https://ghe.example.com/mona/app"
}

@test "create stops before creating anything when the remote exists" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub --noop create
  assert_failure
  assert_output_equals "Aborted: a remote named 'origin' already exists; pick another name with --remote-name NAME."
  assert_gh_not_called
}

@test "create outside a repository fails" {
  run hub --noop create
  assert_failure
  assert_output_contains "not a git repository"
  assert_gh_not_called
}

@test "create runs gh from the top of the work tree" {
  make_repo dotfiles
  mkdir -p lib/deep && cd lib/deep
  mkdir "$HUB_TEST_TMP/shim"
  cat >"$HUB_TEST_TMP/shim/gh" <<'SH'
#!/usr/bin/env bash
pwd -P >"$HUB_TEST_TMP/gh.pwd"
printf 'gh %s\n' "$*" >>"$HUB_TEST_LOG"
SH
  chmod +x "$HUB_TEST_TMP/shim/gh"
  PATH=$HUB_TEST_TMP/shim:$PATH run hub create
  assert_success
  assert_gh_called 'repo create --source=. --remote=origin --private'
  [[ $(cat "$HUB_TEST_TMP/gh.pwd") == "$(cd "$HUB_TEST_TMP/dotfiles" && pwd -P)" ]]
}

@test "create fails when gh fails" {
  make_repo dotfiles
  export BROWSER="printf 'BROWSER %s\n'"
  stub_gh 'repo create *' '' 1
  run hub create -o
  assert_failure
  [[ $output != *BROWSER* ]]
}

@test "create rejects two names and options without values" {
  make_repo dotfiles
  run hub create one two
  assert_failure
  assert_output_contains "Usage: hub create"
  run hub create -d
  assert_failure
  assert_output_contains "-d needs a value"
}

@test "create --help prints the manual" {
  run hub create --help
  assert_success
  assert_output_contains "PRIVATE unless --public"
}
