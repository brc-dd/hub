#!/usr/bin/env bats
load ../test_helper

@test "fork forks hub's project through the API, then adds the fork as a remote named after your login and fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name\ngit remote add mislav https://github.com/mislav/dotfiles.git\ngit fetch mislav'
  assert_gh_called 'config get user -h github.com'
  [[ $(gh_calls) != *"/forks"* ]]
}

@test "fork forks the upstream remote's repository, whatever gh's default repository is" {
  make_repo dotfiles origin=https://github.com/hubot/dotfiles.git upstream=https://github.com/dotcom/dotfiles.git
  git config remote.origin.gh-resolved base # what gh repo set-default origin records
  run hub --noop fork
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name\ngit remote add mislav https://github.com/mislav/dotfiles.git\ngit fetch mislav'
}

@test "fork names the project's host for gh, and uses your login and the protocol on that host" {
  make_repo app origin=git@ghe.example.com:corp/app.git
  git config hub.host ghe.example.com # gh's default host stays github.com
  stub_gh 'config get user -h ghe.example.com' 'mona'
  stub_gh 'config get git_protocol -h ghe.example.com' 'ssh'
  run hub --noop fork
  assert_success
  assert_output_equals $'gh api --hostname ghe.example.com -X POST repos/corp/app/forks --jq .full_name\ngit remote add mona git@ghe.example.com:mona/app.git\ngit fetch mona'
}

@test "fork forks GH_REPO when it is set" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  export GH_REPO=ghe.example.com/corp/app
  stub_gh 'config get user -h ghe.example.com' 'mona'
  run hub --noop fork
  assert_success
  assert_output_equals $'gh api --hostname ghe.example.com -X POST repos/corp/app/forks --jq .full_name\ngit remote add mona https://ghe.example.com/mona/app.git\ngit fetch mona'
}

@test "fork --org forks into the organization and names the remote after it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --org myorg
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg --jq .full_name\ngit remote add myorg https://github.com/myorg/dotfiles.git\ngit fetch myorg'
  run hub --noop fork --org=myorg
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg --jq .full_name\ngit remote add myorg https://github.com/myorg/dotfiles.git\ngit fetch myorg'
  [[ $(gh_calls) != *"config get user"* ]]
}

@test "fork --remote-name picks the remote name" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --remote-name fork
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name\ngit remote add fork https://github.com/mislav/dotfiles.git\ngit fetch fork'
  run hub --noop fork --remote-name=mine --org myorg
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg --jq .full_name\ngit remote add mine https://github.com/myorg/dotfiles.git\ngit fetch mine'
}

@test "fork --fork-name asks for that name, and --noop shows the fork by it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --fork-name dots
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f name=dots --jq .full_name\ngit remote add mislav https://github.com/mislav/dots.git\ngit fetch mislav'
  run hub --noop fork --fork-name=dots --org myorg
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg -f name=dots --jq .full_name\ngit remote add myorg https://github.com/myorg/dots.git\ngit fetch myorg'
}

@test "fork --default-branch-only forks only the default branch, and gh's --remote is hub's default" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --default-branch-only --remote
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -F default_branch_only=true --jq .full_name\ngit remote add mislav https://github.com/mislav/dotfiles.git\ngit fetch mislav'
  run hub --noop fork --default-branch-only=true --fork-name dots --org myorg --no-remote
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg -f name=dots -F default_branch_only=true --jq .full_name"
  run hub --noop fork --default-branch-only --default-branch-only=false --no-remote
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name"
}

@test "fork --no-remote only forks" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub --noop fork --no-remote
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name"
  run hub --noop fork --remote=false --org myorg --fork-name dots
  assert_success
  assert_output_equals "gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg -f name=dots --jq .full_name"
  assert_gh_not_called
}

@test "fork --no-remote prints the fork GitHub returns and adds no remote" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  stub_gh 'api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name' 'mislav/dots'
  run hub fork --no-remote
  assert_success
  assert_output_equals "mislav/dots"
  [[ $(git remote) == origin ]]
}

@test "fork keeps a remote that already points at the fork and fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:Mislav/dotfiles.git
  run hub --noop fork
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name\nUsing the existing remote \'mislav\' for mislav/dotfiles.\ngit fetch mislav'
  git remote add mine https://github.com/myorg/dots.git
  run hub --noop fork --org myorg --fork-name dots --remote-name mine
  assert_success
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg -f name=dots --jq .full_name\nUsing the existing remote \'mine\' for myorg/dots.\ngit fetch mine'
}

@test "fork stops before forking when the remote name is taken by a repository that cannot be the fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  stub_gh 'api --hostname github.com -X POST *' 'mislav/dotfiles'
  run hub fork --remote-name origin
  assert_failure
  assert_output_equals "Aborted: a remote named 'origin' already exists for https://github.com/dotcom/dotfiles.git, not for mislav's fork; pick another name with --remote-name NAME."
  git remote add mislav ../elsewhere.git
  run hub fork
  assert_failure
  assert_output_equals "Aborted: a remote named 'mislav' already exists for ../elsewhere.git, not for mislav's fork; pick another name with --remote-name NAME."
  git config hub.host ghe.example.com
  git remote set-url mislav https://ghe.example.com/mislav/dotfiles.git
  run hub fork --fork-name dots
  assert_failure
  assert_output_equals "Aborted: a remote named 'mislav' already exists for https://ghe.example.com/mislav/dotfiles.git, not for mislav's fork; pick another name with --remote-name NAME."
  git remote set-url mislav https://github.com/mislav/dotfiles.git
  run hub fork --org myorg --remote-name mislav
  assert_failure
  assert_output_contains "not for myorg's fork;"
  [[ $(gh_calls) != *"/forks"* ]]
}

@test "fork refuses names it could not use, a repository argument and --clone before running gh" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub fork --remote-name 'my fork'
  assert_failure
  assert_output_equals "Aborted: 'my fork' is not a valid remote name."
  run hub fork --remote-name -f
  assert_failure
  assert_output_equals "Aborted: '-f' is not a valid remote name."
  run hub fork --fork-name 'my dots'
  assert_failure
  assert_output_equals "Aborted: 'my dots' is not a repository name GitHub keeps as it is; use letters, digits, '-', '_' and '.'."
  run hub fork --org=
  assert_failure
  assert_output_equals "hub fork: --org needs a value"
  run hub fork --remote-name
  assert_failure
  assert_output_equals "hub fork: --remote-name needs a value"
  run hub fork other/repo
  assert_failure
  assert_output_contains "Usage: hub fork"
  run hub fork --clone
  assert_failure
  assert_output_contains "does not clone it"
  assert_gh_not_called
}

@test "fork refuses gh repo fork's other options and git clone flags before running gh" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  run hub fork --yes
  assert_failure
  assert_output_equals "Aborted: hub fork does not take '--yes'. It forks through the GitHub API, not gh repo fork, and its options are --no-remote, --remote-name NAME, --org ORG, --fork-name NAME and --default-branch-only."
  run hub fork --org myorg -x
  assert_failure
  assert_output_contains "does not take '-x'."
  run hub fork --default-branch-only=yes
  assert_failure
  assert_output_contains "does not take '--default-branch-only=yes'."
  run hub fork --remote=no
  assert_failure
  assert_output_contains "does not take '--remote=no'."
  run hub fork --fork-name dots -- --depth=1
  assert_failure
  assert_output_equals "Aborted: hub fork adds the fork as a remote of this repository and does not clone it; use gh repo fork OWNER/REPO --clone for that."
  assert_gh_not_called
}

@test "fork adds the remote itself and fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  git init -q --bare "$HUB_TEST_TMP/fork.git"
  git push -q "$HUB_TEST_TMP/fork.git" main
  # Fetch "from GitHub" out of the local bare repository.
  git config --global url."$HUB_TEST_TMP/fork.git".insteadOf https://github.com/mislav/dotfiles.git
  stub_gh 'api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name' 'mislav/dotfiles'
  run hub fork
  assert_success
  [[ $output != *"The fork is"* ]]
  [[ $(git config remote.mislav.url) == https://github.com/mislav/dotfiles.git ]]
  git rev-parse --verify -q refs/remotes/mislav/main
}

@test "fork adds the fork GitHub returns, which can be named otherwise than asked" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  git init -q --bare "$HUB_TEST_TMP/fork.git"
  git push -q "$HUB_TEST_TMP/fork.git" main
  git config --global url."$HUB_TEST_TMP/fork.git".insteadOf https://github.com/mislav/dots.git
  # The fork mislav already has keeps its name, whatever --fork-name asks for.
  stub_gh 'api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f name=dotfiles2 --jq .full_name' 'mislav/dots'
  run hub fork --fork-name dotfiles2
  assert_success
  assert_line_equals 0 "The fork is mislav/dots, not mislav/dotfiles2."
  [[ $(git config remote.mislav.url) == https://github.com/mislav/dots.git ]]
  git rev-parse --verify -q refs/remotes/mislav/main
  assert_gh_called 'api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f name=dotfiles2 --jq .full_name'
}

@test "fork keeps a remote that points at the fork GitHub returns under another name, and fetches it" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=git@github.com:mislav/dots.git
  git init -q --bare "$HUB_TEST_TMP/fork.git"
  git push -q "$HUB_TEST_TMP/fork.git" main
  # Fetch "over SSH from GitHub" out of the local bare repository (the remote's URL stays GitHub's).
  printf '#!/usr/bin/env bash\nexec git upload-pack "$HUB_TEST_TMP/fork.git"\n' >"$HUB_TEST_TMP/ssh"
  chmod +x "$HUB_TEST_TMP/ssh"
  export GIT_SSH_COMMAND=$HUB_TEST_TMP/ssh GIT_SSH_VARIANT=simple
  stub_gh 'api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name' 'mislav/dots'
  run hub fork
  assert_success
  assert_line_equals 0 "The fork is mislav/dots, not mislav/dotfiles."
  assert_line_equals 1 "Using the existing remote 'mislav' for mislav/dots."
  [[ $(git config remote.mislav.url) == git@github.com:mislav/dots.git ]]
  git rev-parse --verify -q refs/remotes/mislav/main
}

@test "fork leaves a remote of yours alone that points at another repository than the fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git mislav=https://github.com/mislav/other.git
  stub_gh 'api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name' 'mislav/dotfiles'
  run hub fork
  assert_failure
  assert_output_equals "Aborted: a remote named 'mislav' already exists for https://github.com/mislav/other.git, not for the fork mislav/dotfiles; pick another name with --remote-name NAME."
  [[ $(git config remote.mislav.url) == https://github.com/mislav/other.git ]]
  ! git rev-parse --verify -q refs/remotes/mislav/main
  run hub --noop fork
  assert_failure
  assert_output_equals $'gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name\nAborted: a remote named \'mislav\' already exists for https://github.com/mislav/other.git, not for the fork mislav/dotfiles; pick another name with --remote-name NAME.'
}

@test "fork adds no remote and fetches nothing when gh fails or GitHub's answer is no fork" {
  make_repo dotfiles origin=https://github.com/dotcom/dotfiles.git
  stub_gh 'api --hostname github.com -X POST *' '' 4
  run hub fork
  [[ $status -eq 4 ]]
  assert_output_equals ""
  stub_gh 'api --hostname github.com -X POST *' ''
  run hub fork
  assert_failure
  assert_output_equals "Aborted: expected the fork's OWNER/REPO from GitHub, got ''."
  stub_gh 'api --hostname github.com -X POST *' 'Dotcom/dotfiles'
  run hub fork
  assert_failure
  assert_output_equals "Aborted: GitHub gave dotcom/dotfiles itself as the fork; a repository cannot be forked into the account that owns it."
  [[ $(git remote) == origin ]]
}

@test "fork needs a repository with a GitHub remote" {
  run hub --noop fork
  assert_failure
  assert_output_contains "not a git repository"
  make_repo local-only
  run hub --noop fork
  assert_failure
  assert_output_contains "Aborted: could not find a GitHub remote"
  assert_gh_not_called
}

@test "fork --help prints the manual" {
  run hub fork --help
  assert_success
  assert_output_contains 'renamed to "upstream"'
  assert_output_contains "--fork-name NAME"
  assert_output_contains "--default-branch-only"
}
