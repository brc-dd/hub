#!/usr/bin/env bats
# hub remote: add and set-url with GitHub OWNER[/REPO] names; everything else is git remote's.

load test_helper

url_of() { git config --get "remote.$1.${2:-url}"; }

ghe_hosts() {
  mkdir -p "$GH_CONFIG_DIR"
  printf 'github.com:\n    user: mislav\nghe.example.com:\n    user: mona\n' \
    >"$GH_CONFIG_DIR/hosts.yml"
}

@test "remote add USER adds USER's copy of the project, named after USER" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/alice/dotfiles.git
  assert_gh_called 'config get git_protocol -h github.com'
}

@test "remote add NAME OWNER and NAME OWNER/REPO name the remote and the repository" {
  serve_github mislav/dotfiles
  clone_served mislav/dotfiles
  run hub remote add work alice
  assert_success
  assert_equals "$(url_of work)" https://github.com/alice/dotfiles.git
  run hub remote add upstream github/hub.git
  assert_success
  assert_equals "$(url_of upstream)" https://github.com/github/hub.git
  run hub remote add mine me/dots
  assert_equals "$(url_of mine)" https://github.com/me/dots.git
}

@test "remote add -f fetches the expanded repository with every git option in place" {
  serve_github mislav/dotfiles alice/dotfiles
  git -C "$(server_dir alice/dotfiles)" branch other main
  clone_served mislav/dotfiles
  run hub remote add -f -t main --no-tags alice
  assert_success
  assert_equals "$(url_of alice fetch)" +refs/heads/main:refs/remotes/alice/main
  assert_equals "$(url_of alice tagOpt)" --no-tags
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
  run git rev-parse --verify --quiet refs/remotes/alice/other
  assert_failure
}

@test "remote add -- USER keeps the -- and puts the name after it" {
  serve_github mislav/dotfiles alice/dotfiles
  clone_served mislav/dotfiles
  run hub remote add -f -- alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/alice/dotfiles.git
  assert_equals "$(git rev-parse refs/remotes/alice/main)" "$(server_ref alice/dotfiles main)"
}

@test "remote add never takes the value of -t, -m, --track or --master for an operand" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add -t alice bob
  assert_success
  assert_equals "$(url_of bob)" https://github.com/bob/dotfiles.git
  assert_equals "$(url_of bob fetch)" +refs/heads/alice:refs/remotes/bob/alice
  run hub remote add --track carol dave
  assert_equals "$(url_of dave fetch)" +refs/heads/carol:refs/remotes/dave/carol
  run hub remote add -m main erin
  assert_success
  assert_equals "$(git symbolic-ref refs/remotes/erin/HEAD)" refs/remotes/erin/main
  run hub remote add --master main frank
  assert_equals "$(url_of frank)" https://github.com/frank/dotfiles.git
  run hub remote add --mirror=fetch gina
  assert_success
  assert_equals "$(url_of gina)" https://github.com/gina/dotfiles.git
  assert_equals "$(url_of gina fetch)" '+refs/*:refs/*'
  run hub remote add -t -p hank
  assert_success
  assert_equals "$(url_of hank)" https://github.com/hank/dotfiles.git
}

@test "remote add -p uses an ssh URL wherever it stands, without asking gh" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add -p alice
  assert_success
  assert_equals "$(url_of alice)" git@github.com:alice/dotfiles.git
  run hub remote add bob carol/tools -p
  assert_equals "$(url_of bob)" git@github.com:carol/tools.git
  assert_gh_not_called
}

@test "remote add -p works inside a cluster of git's flags" {
  serve_github mislav/dotfiles alice/dotfiles
  clone_served mislav/dotfiles
  run hub remote add -fp alice
  assert_success
  assert_equals "$(url_of alice)" git@github.com:alice/dotfiles.git
  run hub remote add -pf bob
  assert_equals "$(url_of bob)" git@github.com:bob/dotfiles.git
  run hub remote add -pt main carol
  assert_success
  assert_equals "$(url_of carol)" git@github.com:carol/dotfiles.git
  assert_equals "$(url_of carol fetch)" +refs/heads/main:refs/remotes/carol/main
  run hub --noop remote add -ph erin
  assert_output_equals 'git remote add -h erin'
  assert_gh_not_called
  run hub remote add -tp dave
  assert_success
  assert_equals "$(url_of dave)" https://github.com/dave/dotfiles.git
  assert_equals "$(url_of dave fetch)" +refs/heads/p:refs/remotes/dave/p
}

@test "remote -v add, with git's verbose flag before the subcommand, is expanded too" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote -v add work alice
  assert_success
  assert_equals "$(url_of work)" https://github.com/alice/dotfiles.git
  run hub remote --verb -vv set-url work bob
  assert_success
  assert_equals "$(url_of work)" https://github.com/bob/dotfiles.git
  run hub remote -x add carol
  assert_status 129
  run url_of carol
  assert_failure
}

@test "remote add and set-url without gh use https, and origin alone refuses" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  local needs='this command needs the GitHub CLI, gh (https://cli.github.com)'
  PATH=$(no_gh_path) run hub remote add alice
  assert_success
  assert_output_equals ''
  assert_equals "$(url_of alice)" https://github.com/alice/dotfiles.git
  PATH=$(no_gh_path) run hub remote set-url origin bob
  assert_success
  assert_equals "$(url_of origin)" https://github.com/bob/dotfiles.git
  git remote remove origin
  PATH=$(no_gh_path) run hub remote add origin
  assert_status 1
  assert_output_equals "hub remote: $needs"
  run url_of origin
  assert_failure
  PATH=$(no_gh_path) run hub remote add -p origin
  assert_status 1
  assert_output_equals "hub remote: $needs"
  run url_of origin
  assert_failure
  PATH=$(no_gh_path) run hub remote add -p carol
  assert_success
  assert_equals "$(url_of carol)" git@github.com:carol/dotfiles.git
  assert_gh_not_called
}

@test "remote add follows gh's git_protocol" {
  stub_gh 'config get git_protocol -h github.com' ssh
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" git@github.com:alice/dotfiles.git
}

@test "remote add origin alone adds your own copy of the project" {
  make_repo hub upstream=https://github.com/github/hub.git
  run hub remote add origin
  assert_success
  assert_equals "$(url_of origin)" https://github.com/mislav/hub.git
  assert_gh_called 'config get user -h github.com'
}

@test "remote add origin with an owner keeps origin a plain name" {
  make_repo hub upstream=https://github.com/github/hub.git
  run hub remote add origin bob
  assert_success
  assert_equals "$(url_of origin)" https://github.com/bob/hub.git
  run gh_calls
  assert_output_lacks 'config get user'
}

@test "remote add origin alone on an Enterprise project uses your login there" {
  ghe_hosts
  stub_gh 'config get user -h ghe.example.com' mona
  stub_gh 'config get git_protocol -h ghe.example.com' https
  make_repo proj upstream=https://ghe.example.com/team/proj.git
  run hub remote add origin
  assert_success
  assert_equals "$(url_of origin)" https://ghe.example.com/mona/proj.git
  assert_gh_called 'config get user -h ghe.example.com'
}

@test "remote add NAME origin takes origin for an owner, not your login" {
  make_repo hub upstream=https://github.com/github/hub.git
  run hub remote add work origin
  assert_success
  assert_equals "$(url_of work)" https://github.com/origin/hub.git
  run gh_calls
  assert_output_lacks 'config get user'
}

@test "remote add origin refuses when your login is unknown, and adds nothing" {
  stub_gh 'config get user -h github.com' '' 1
  stub_gh 'api --hostname github.com user --jq .login' '' 1
  make_repo hub upstream=https://github.com/github/hub.git
  run hub remote add origin
  assert_status 1
  local why='could not determine your GitHub login for github.com'
  assert_output_equals "hub remote: $why (run: gh auth login -h github.com)"
  run url_of origin
  assert_failure
}

@test "remote add takes the repository name from upstream before origin" {
  make_repo work origin=https://github.com/me/fork-name.git upstream=https://github.com/org/proj.git
  run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/alice/proj.git
}

@test "remote add takes the repository name from GH_REPO, and refuses an invalid one" {
  make_repo work origin=https://github.com/mislav/dotfiles.git
  GH_REPO=other/thing run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/alice/thing.git
  GH_REPO=nonsense run hub remote add bob
  assert_status 1
  assert_output_equals \
    'hub remote: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
  GH_REPO=nonsense run hub remote add bob carol/x
  assert_status 1
  run url_of bob
  assert_failure
}

@test "remote add without a GitHub remote takes the directory's name, from a subdirectory too" {
  make_repo 'my project'
  mkdir sub
  cd sub
  run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/alice/my-project.git
}

@test "remote add in a bare repository takes its name without .git" {
  git init -q --bare tool.git
  cd tool.git
  run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/alice/tool.git
}

@test "remote add uses the project's host and that host's protocol" {
  ghe_hosts
  stub_gh 'config get git_protocol -h ghe.example.com' ssh
  make_repo proj origin=https://ghe.example.com/team/proj.git
  run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" git@ghe.example.com:alice/proj.git
  assert_gh_called 'config get git_protocol -h ghe.example.com'
}

@test "remote add uses the host GH_REPO names" {
  stub_gh 'config get git_protocol -h ghe.example.com' https
  make_repo work origin=https://github.com/mislav/dotfiles.git
  GH_REPO=ghe.example.com/o/r run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://ghe.example.com/alice/r.git
}

@test "remote add without a GitHub remote uses GH_HOST" {
  stub_gh 'config get git_protocol -h ghe.example.com' https
  make_repo plain
  GH_HOST=ghe.example.com run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://ghe.example.com/alice/plain.git
}

@test "remote add NAME PATH keeps a local path, but a lone USER is expanded" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  mkdir alice
  git init -q --bare tools.git
  git init -q notes.git
  run hub remote add backup alice
  assert_success
  assert_equals "$(url_of backup)" alice
  run hub remote add mirror tools
  assert_equals "$(url_of mirror)" tools
  run hub remote add jot notes
  assert_equals "$(url_of jot)" notes
  run hub remote add alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/alice/dotfiles.git
}

@test "remote add keeps a path git reads from the top directory, and one here" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git init -q alice
  mkdir -p sub/bob
  cd sub
  run hub remote add backup alice
  assert_success
  assert_equals "$(url_of backup)" alice
  run hub remote add other bob
  assert_success
  assert_equals "$(url_of other)" bob
  run hub remote add carol carol
  assert_equals "$(url_of carol)" https://github.com/carol/dotfiles.git
}

@test "remote add with a URL, a path or a name that is no owner is plain git" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add up https://example.com/x.git
  assert_success
  assert_equals "$(url_of up)" https://example.com/x.git
  run hub remote add -p scp git@example.com:x/y.git
  assert_success
  assert_equals "$(url_of scp)" git@example.com:x/y.git
  run hub remote add rel ../x
  assert_equals "$(url_of rel)" ../x
  run hub remote add dotted some.dir
  assert_equals "$(url_of dotted)" some.dir
  run hub remote add three ghe.example.com/o/r
  assert_equals "$(url_of three)" ghe.example.com/o/r
  assert_gh_not_called
}

@test "remote add with other operand counts is plain git" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add alice/dots
  assert_status 129
  assert_output_contains 'usage: git remote add'
  run hub remote add
  assert_status 129
  run hub remote add a b c
  assert_status 129
  run git remote
  assert_output_equals origin
  assert_gh_not_called
}

@test "remote add of an existing remote gets git's refusal" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add origin bob
  assert_status 3
  assert_output_equals 'error: remote origin already exists.'
  assert_equals "$(url_of origin)" https://github.com/mislav/dotfiles.git
}

@test "remote add leaves a line it cannot read with certainty to git" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote add --tra main zed alice
  assert_success
  assert_equals "$(url_of zed)" alice
  assert_equals "$(url_of zed fetch)" +refs/heads/main:refs/remotes/zed/main
  run hub remote add bob alice -t
  assert_status 129
  run url_of bob
  assert_failure
  assert_gh_not_called
}

@test "remote add outside a repository is git's error" {
  run hub remote add alice
  assert_status 128
  assert_output_contains 'not a git repository'
  assert_gh_not_called
}

@test "remote set-url NAME OWNER[/REPO] sets the URL, over ssh with -p" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote set-url origin alice
  assert_success
  assert_equals "$(url_of origin)" https://github.com/alice/dotfiles.git
  run hub remote set-url -p origin alice/dots
  assert_success
  assert_equals "$(url_of origin)" git@github.com:alice/dots.git
}

@test "remote set-url uses the project's host" {
  ghe_hosts
  stub_gh 'config get git_protocol -h ghe.example.com' https
  make_repo proj origin=https://ghe.example.com/team/proj.git
  run hub remote set-url origin alice
  assert_success
  assert_equals "$(url_of origin)" https://ghe.example.com/alice/proj.git
}

@test "remote set-url --push writes the push URL, and --add --push appends one" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote set-url --push origin alice
  assert_success
  assert_equals "$(url_of origin)" https://github.com/mislav/dotfiles.git
  assert_equals "$(url_of origin pushurl)" https://github.com/alice/dotfiles.git
  run hub remote set-url --add --push origin bob
  assert_success
  run git config --get-all remote.origin.pushurl
  assert_output_equals $'https://github.com/alice/dotfiles.git\nhttps://github.com/bob/dotfiles.git'
}

@test "remote set-url --delete, abbreviated too, is plain git with the operand a pattern" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  git config --add remote.origin.pushurl https://github.com/alice/dotfiles.git
  git config --add remote.origin.pushurl https://github.com/bob/dotfiles.git
  run hub remote set-url --delete --push origin alice
  assert_success
  run git config --get-all remote.origin.pushurl
  assert_output_equals https://github.com/bob/dotfiles.git
  git config --add remote.origin.pushurl https://example.com/carol.git
  run hub remote set-url --del --push origin carol
  assert_success
  run git config --get-all remote.origin.pushurl
  assert_output_equals https://github.com/bob/dotfiles.git
  assert_gh_not_called
}

@test "remote set-url with OLDURL, a URL, a local path or one operand is plain git" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote set-url origin
  assert_status 129
  assert_equals "$(url_of origin)" https://github.com/mislav/dotfiles.git
  run hub remote set-url origin alice dotfiles
  assert_success
  assert_equals "$(url_of origin)" alice
  run hub remote set-url origin https://example.com/x.git
  assert_equals "$(url_of origin)" https://example.com/x.git
  git init -q --bare tools.git
  run hub remote set-url origin tools
  assert_success
  assert_equals "$(url_of origin)" tools
  assert_gh_not_called
}

@test "the other subcommands are plain git remote" {
  make_repo dotfiles origin=https://github.com/mislav/dotfiles.git
  run hub remote rename origin alice
  assert_success
  assert_equals "$(url_of alice)" https://github.com/mislav/dotfiles.git
  run hub remote -v
  assert_line_equals 0 $'alice\thttps://github.com/mislav/dotfiles.git (fetch)'
  run hub remote
  assert_output_equals alice
  assert_gh_not_called
}

@test "remote --help is git's manual, and hub help remote is hub's" {
  run hub --noop remote add alice --help
  assert_success
  assert_output_equals 'git remote add alice --help'
  run hub --noop remote --help
  assert_output_equals 'git remote --help'
  run hub help remote
  assert_success
  assert_line_equals 0 'Summary: Add or change a remote by its GitHub OWNER[/REPO] name.'
  assert_equals "${lines[${#lines[@]} - 1]}" "git's own manual: git remote --help"
}
