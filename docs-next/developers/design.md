---
title: How hub is built
description: Principles, dispatch and re-entry, the module contract, operands, push remotes, tests and limits.
---

# How hub is built

This page is for contributors who change or add a module: it shows how hub
reaches its commands, what a module promises and how hub reads a command line.
[Working on hub](development.md) covers the tests, make targets and releases.
The examples write `hub` and show what `--noop` prints.

## Ask git, never guess

When hub cannot tell what the user means, it stops with a message or hands the
line to git untouched. It never guesses. An earlier implementation modeled
git's rules in bash (push destinations, fetch refspecs, `GIT_CONFIG`, option
abbreviations), and every fix added more model that stayed wrong. This hub
asks git: `for-each-ref` atoms such as `%(upstream:remotename)`, `rev-parse`,
`merge-base --is-ancestor`, `git remote get-url`. git's own commands refuse
what is unsafe, and exotic setups are documented
[limitations](#limitations). hub has no API client, token or configuration of
its own: GitHub CLI (gh) does GitHub.

git expands `--dep` to `--depth`, so `1` is the value of `--depth`. A table of
git's options does not list `--dep`, so it would take `1` for the repository.
hub cannot be sure, so it hands the line to git untouched:

```sh
hub --noop clone --dep 1 alice/x
# => git clone --dep 1 alice/x
```

## Why a shell alias

git ignores an alias that hides a built-in command:

```sh
git -c alias.clone='!echo X' clone a/b
# => fatal: repository 'a/b' does not exist
```

So `alias git=hub` in the shell is the only way to see `git clone OWNER/REPO`
before git does, and `hub alias` prints the line for the user's shell. With
the alias, `git` and `hub` are one command. A command hub does not handle
costs one bash start, about 15 ms, before `exec git`. A command with a module
pays one more git and bash start, because hub re-enters through git (see
[Dispatch and re-entry](#dispatch-and-re-entry)). Every command with a module
also shadows a git alias of the same name, such as `alias.pr`.

## Dispatch and re-entry

`bin/hub` reads `hub [--noop] [GIT-OPTIONS...] COMMAND [ARGS...]`. Up to the
hand-over to git, `bin/hub` is bash 3.2 code, with no `mapfile`, `declare -A`
or `${x,,}`. Under the alias, `git status` must work with whatever bash `env`
finds. On macOS, that is `/bin/bash` 3.2. `bin/hub` follows symbolic links to
its installation, exports `HUB_ROOT` and `HUB_LIB`, and walks the arguments:

| Word | What it does |
|---|---|
| `--noop` | Turns on hub's own flag. hub removes it from the line. |
| `-C`, `-c`, `--config-env`, `--git-dir`, `--work-tree`, `--namespace`, `--attr-source`, `--super-prefix`, `--shallow-file` | Gives a global option that takes the next word, whatever it is. |
| Any other word that starts with `-` | Gives a global flag. |
| The first other word | Names the command. `--version` and `-v` mean `version`, `--help` and `-h` mean `help`. |

A command word is hub's when it matches `^[a-z][a-z0-9-]*$` and
`lib/hub/cmd/WORD.sh` exists. Otherwise hub sources nothing and runs `exec git`
with the arguments as given, minus `--noop`. Before either `exec`, hub refuses
to run when the first `git` on `PATH` is its own file, which `exec git` would
start again forever. For a command that has a module, the dispatcher refuses a
bash older than 5. Then it re-enters through git with this line:

```text
HUB_REEXEC=1 HUB_NOOP=0|1 HUB_KEEP_GIT_DIR=0|1 \
  exec git GLOBALS... -c "alias.hub-run=!exec 'PATH-TO-HUB' --run" hub-run COMMAND ARGS...
```

git applies the global options and exports their effect to every child
process, gh's git calls included. git applies `-C` itself, so `CDPATH` and
symbolic links do not change the directory. It applies `-c` and
`--config-env` in its own order, and `--git-dir`, `--bare` and the rest as
well. hub accepts `--run` only when `HUB_REEXEC=1` is set. Without the marker,
hub hands `--run` to git, which refuses it as an unknown option. hub checks
bash 5 again, then repairs what git does to a `!` alias:

| What git does | What hub does, and why |
|---|---|
| git runs the alias from the top of the work tree and exports the user's subdirectory as `GIT_PREFIX`. | hub runs `cd -P -- "./$GIT_PREFIX"` and unsets it, so relative paths keep their meaning. |
| git exports the git directory it found as `GIT_DIR`. | hub unsets `GIT_DIR` unless the user set it, which the dispatcher records as `HUB_KEEP_GIT_DIR=1`. The paragraph after this table says why. |
| git exports `GIT_IMPLICIT_WORK_TREE=0` from a bare repository or a `.git` directory. | hub unsets it with `GIT_DIR`. Left set, a clone that hub starts would leave its hooks and submodules without a work tree. |
| git keeps a user's `GIT_CONFIG`, which points `git config`, and no other git command, at another file. | hub unsets it, so hub's queries read the configuration that `git push` reads. A plain git command never reaches the re-entry and keeps it. |
| git exports the user's `-c` values as `GIT_CONFIG_PARAMETERS`. | hub keeps it as git exported it, so every git that hub or gh starts sees the user's `-c` values and the harmless `alias.hub-run` entry. |
| git answers `--exec-path`, `--html-path` and `--list-cmds=` and exits before the alias runs. | Nothing. |

The user sets `GIT_DIR` in the environment, with `--git-dir` or with
`--bare`. A git that sees `GIT_DIR` without `GIT_WORK_TREE` takes the current
directory for the top of the work tree. After the `cd`, every git that hub
starts would take the user's subdirectory for it.

Then hub exports `HUB_COMMAND`, sources `core.sh` and the module, and calls
`hub_cmd_NAME`. hub refuses a word that is not a module:
`hub: not a hub command: X`.

## What `--noop` prints

Under `--noop`, hub prints every git and gh command that changes something
instead of running it. It quotes each word with `printf '%q '` so that the line
can be pasted back. It leaves out the global options and the environment they
set. Read-only lookups still run, the patch downloads of `am` and `apply`
included. Opening and copying print `open URL` and `copy URL`. A plain git
command prints `git` and its arguments as given, global options included. hub
ignores `HUB_NOOP` in the environment.

`tag` is a plain git command, so hub prints it with its global options. In a
clone of mislav/dotfiles, `browse` prints the URL that it would open:

```sh
# A plain git command keeps -C
hub -C . --noop tag v1
# => git -C . tag v1
hub --noop tag 'two words'
# => git tag two\ words
# In a clone of mislav/dotfiles
hub --noop browse -- issues
# => open https://github.com/mislav/dotfiles/issues
```

## Three kinds of command

Each module in `lib/hub/cmd/` is one command. The first sentence of its
description states the kind in a fixed wording:

| Kind | Commands | Fixed sentence | What hub does |
|---|---|---|---|
| hub's own commands | alias, browse, ci-status, compare, create, delete, fork, help, pull-request, sync, version | "hub's own command: these are all of its options." | Any other option is a usage error. sync says "it takes no options", and help says "any other arguments go to git help" and hands them to `git help`. |
| gh commands | api, gist, issue, pr, release | "gh's command: gh NAME's options and output." | For gist, issue, pr and release, maps the subcommand names of the original hub (mislav/hub 2.x) (`show` is `view`, no subcommand is `list`) and runs `exec gh NAME ARGS...`. api hands every argument to `gh api` unchanged. |
| git commands hub extends | am, apply, checkout, cherry-pick, clone, fetch, merge, push, remote | "A git command hub extends: git NAME's options apply." | Reads the line only to find its operands, acts on its shorthands and GitHub URLs, and runs git. When in doubt, hub hands the line to git untouched (`exec git NAME "$@"`). |

`hub NAME --help` prints hub's manual. For a git command hub extends,
`--help` and `-h` are git's, and `hub help NAME` gives hub's manual.

hub renames the original hub's `show` to `view` and supplies `list` when no
subcommand is given:

```sh
hub --noop issue show 12
# => gh issue view 12
hub --noop pr
# => gh pr list
```

## The module contract

A module keeps six promises. The steps that put them into practice for a new
command are in [Working on hub](development.md#add-a-command).

1. The header is the manual. `hub help NAME` and `hub NAME --help` print the
   module's leading `#` lines without `# `, skipping `# shellcheck` lines
   (`hub::module_doc`): `Summary:`, `Usage:`, a short description, `Options:`
   and examples (`$ hub ...` followed by `> git ...` or `> gh ...`).
   `hub help` lists the Summary lines, and the completions use them as
   descriptions. A test checks that the completions offer exactly the options
   in the `Options:` block of each of hub's own commands.
2. The manuals website reads the same headers. `script/site` renders `bin/hub`
   as the index and each module header as a page of the
   [manuals website](https://brc-dd.github.io/hub/), so a header follows the
   rules the pages rely on. The Summary line comes first, then the Usage lines
   up to the first blank line, then blocks separated by blank lines. In a
   block, unindented lines are a paragraph that the browser reflows, and lines
   indented by two or more spaces are preformatted. An unindented line that
   ends in a colon, right before indented lines, is a heading, such as
   `Options:`.
3. Shared logic is `hub::*`. Logic that two or more modules use lives in
   `core.sh` as `hub::name`, with a one-line contract
   (`# hub::name ARGS : what it gives.`). A helper prints its answer on stdout
   and returns non-zero when it has none (`x=$(hub::name) || ...`). The few
   that set a global name it: `HUB_ARGS`, `HUB_OPERANDS`, `HUB_OPTIONS`,
   `HUB_URL`. Logic one module uses is a private `_hub_NAME_*` function in
   that module, and core's own are `_hub_core_*`. Modules never source each
   other.
4. Side effects go through `hub::run`. `hub::run CMD ARGS...` runs a command
   with side effects, or prints it under `--noop`. `hub::git` and `hub::gh`
   call it for git and gh, `hub::exec_git` and `hub::exec_gh` hand the process
   over, and all of them print instead under `--noop`. Read-only calls use
   `hub::git_query` and `hub::gh_query`, or plain `git` and `gh` where the
   module reads their messages.
5. Validate before the first side effect. Every check and read-only lookup
   comes first: fetch asks GitHub about every new user before it adds the
   first remote, and pull-request refuses to prompt without a terminal before
   it pushes. A command that needs gh calls `hub::require_gh` once, before any
   lookup, and every gh call names the host. When git or gh fails, its own
   message reaches the user unchanged. The exit status is the handed-over
   program's, or 1 for hub's refusals. ci-status documents 0 to 3.
6. One message format. A message is one lowercase sentence, unless it starts
   with a name or value given verbatim. It names the offending value first or
   after a colon, and ends with the way out in parentheses when there is one:
   `remote already exists: X (name another with --remote-name NAME)`. hub's
   own commands use `hub::normalize_opts` to split short-option clusters
   (`-qb` becomes `-q -b`) and to detach values (`--remote-name=X` becomes
   `--remote-name X`), then name every option in a `case` loop that refuses
   `unknown option: X`.

These `core.sh` helpers print the messages:

| Helper | What it does |
|---|---|
| `hub::die` | Prints `hub NAME: MESSAGE` on stderr, then exits 1. The dispatcher's prefix is `hub:`. |
| `hub::usage_error` | Prints the message, then the header's Usage lines, and exits 1. |
| `hub::warn` | Prints `hub NAME: warning: MESSAGE`, and the command goes on. |
| `hub::shown` | Shows a user's word in a refusal such as `unexpected argument: X`: an empty word is `''`, a newline `$'...'`. |

An unknown option to one of hub's own commands is a usage error, so hub prints
the message and then the Usage lines:

```sh
hub version -x
# => hub version: unknown option: -x
# => Usage: hub version [--build-options]
# =>        hub --version [--build-options]
```

## Operands of the git commands hub extends

An extended command finds its operands without knowing all of git's options:
`hub::scan VALUED ARGS...` walks ARGS with VALUED, the command's table of
options that take a separate value, and sets `HUB_OPERANDS` and `HUB_OPTIONS`.
The tables come from `git CMD -h` of git 2.54. A test checks them against
git's output, and that no flag of the command is a proper prefix of an entry.

| Command | Separate-value options |
|---|---|
| clone | `-o --origin -b --branch -u --upload-pack --reference --reference-if-able --separate-git-dir --depth --shallow-since --shallow-exclude -j --jobs --template -c --config --filter --bundle-uri --server-option --ref-format --revision` |
| fetch | `--depth --deepen --shallow-since --shallow-exclude --refmap -j --jobs -o --server-option --upload-pack --negotiation-tip --filter` |
| push | `-o --push-option --repo --receive-pack --exec --recurse-submodules` |
| remote add | `-t --track -m --master` |
| merge | `-m --message -F --file -s --strategy -X --strategy-option --into-name --cleanup`, and `-S=` |
| am | `-p -C --exclude --include --directory --whitespace --patch-format --resolvemsg --quoted-cr --empty`, and `-S=` |
| apply | `-p -C --exclude --include --directory --whitespace --build-fake-ancestor` |
| cherry-pick | `-m --mainline --strategy -X --strategy-option --cleanup --empty`, and `-S=` |

`hub::scan` reads the words as git does:

1. After `--` or `--end-of-options`, every word is an operand.
2. A table entry consumes the next word, whatever it looks like.
3. `--long=value` is one word.
4. A short cluster ends at its first value-taking letter, the rest of the word
   being the value.
5. `-` and words that do not start with `-` are operands, and other options
   are flags.
6. An entry `-X=` marks a letter whose optional value is only attached
   (merge's `-S[KEYID]`).

hub hands the line to git untouched when it cannot read it with certainty:

- A `--word` without `=` that is not in the table but is a proper prefix of an
  entry, which git would expand (`--dep 1`).
- A short cluster in which a value-taking letter follows another letter
  (`-qb main`).
- A value-taking option as the last word, which git refuses.
- `--help`, `--help-all` and `h` among a cluster's flags.

| Rule | What it does |
|---|---|
| What stays out | Options whose optional value is attached only, such as `--force-with-lease[=X]`, stay out of the tables. With `=` they are one word, bare they are flags. |
| URLs as option values | am, apply and cherry-pick convert only the operands before `--` (or `--end-of-options`). So a URL given as an option's value (`--include URL`) reaches git as given. |
| checkout | checkout looks for a pull request URL only before `--`, and needs no table. Only `--pathspec-from-file`'s value can be such a URL. So hub hands a line with a word that starts with `--pathspec-f` (the option, its prefixes, its `=` form or `--pathspec-file-nul`) to git untouched. |
| Modules that read git's options | A module that reads some of git's options itself is as careful. An abbreviation such as merge's `--squ` or fetch's `--mul` hands the line to git. |
| hub's `-p` | `hub::drop_flag` removes it from clone and `remote add` before the scan, so no line handed to git carries it. |

hub converts the shorthand when it can read the line, and hands the line to
git untouched when it cannot:

```sh
hub --noop clone -b main rails/rails
# => git clone -b main https://github.com/rails/rails.git
hub --noop clone -qb main rails/rails
# => git clone -qb main rails/rails
hub --noop merge --squ https://github.com/cli/cli/pull/1
# => git merge --squ https://github.com/cli/cli/pull/1
```

## Repository, host and identity

These `core.sh` helpers answer which repository, on which host, as whom. Users
read [The project and its remotes](../guide/project-and-remotes.md) and
[Hosts and login](../guide/hosts-and-login.md).

| Helper | What it gives |
|---|---|
| `hub::project` | `HOST OWNER REPO`: `GH_REPO` when set (`OWNER/REPO`, `HOST/OWNER/REPO` or a URL, and an invalid value is an error), else the first GitHub remote among `upstream`, `github` and `origin`, then the others in `git remote` order. |
| `hub::project_remote` | The first remote, in that order, that points at the project, so it works under `GH_REPO` too. |
| `hub::gh_hosts` | The top-level keys of gh's `hosts.yml` (in `$GH_CONFIG_DIR`, else `$XDG_CONFIG_HOME/gh`, else `~/.config/gh`), in the block style gh writes. hub has no host list of its own. |
| `hub::host` | `GH_HOST`, else the one host gh is logged in to, else github.com, in lowercase. A `GH_HOST` that is not a host name is an error. A known host is github.com, `GH_HOST` or a gh host, in any case. |
| `hub::login HOST` | gh's cached user (`gh config get user -h HOST`), or the API's answer when a token is set. Neither falls back to the other. When nothing answers, hub stops and names `gh auth login -h HOST`. |
| `hub::protocol HOST` | gh's `git_protocol` for the host. hub uses https when the setting is empty or gh is not installed. `gh config set git_protocol ssh` is the setting, and `-p` on clone and `remote add` is a one-off. |
| `hub::clone_url` | `https://HOST/O/R.git` or `git@HOST:O/R.git`. On `*.ghe.com` the ssh user is the tenant. |
| `hub::open_url` | The browser gh would take: `GH_BROWSER`, else gh's `browser` setting (`gh config get browser`, empty without gh), else `BROWSER`, else `open` or `xdg-open`. |
| `hub::copy` | The clipboard: `pbcopy`, else `wl-copy`, else `xclip -selection clipboard`. |
| `hub::parse_url` | `HOST OWNER REPO` of an https, http, git, ssh (also `git+ssh` and `ssh+git`) or scp-like URL (no `/` before the first colon). The host is lowercased and the port ignored. OWNER and REPO must have GitHub's shapes, and the host must be known. |
| `hub::parse_project` | `HOST OWNER REPO` of what users type. A three-part host must contain a dot or be known, so `cli/cli/issues` is refused. |
| `hub::default_branch` | `refs/remotes/REMOTE/HEAD` when that symbolic ref and its target exist, else gh's answer. A command that changes something never assumes `main`. |

When only the original hub's `GITHUB_HOST` is set, `core.sh` exports it as
`GH_HOST`. `hub::login` asks the API when `GH_TOKEN`, `GITHUB_TOKEN`,
`GH_ENTERPRISE_TOKEN` or `GITHUB_ENTERPRISE_TOKEN` is set, since the token may
be someone else's. For an ssh URL with an unknown host, `hub::parse_url` asks
`ssh -G HOST` once, with the alias as written, and takes its `hostname`.
`ssh.github.com` is github.com.

An invalid `GH_REPO` stops the command before anything else:

```sh
GH_REPO=cli/cli/issues hub --noop browse -u
# => hub browse: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL
```

## Where a branch pushes

pull-request, browse and compare need the repository the current branch
pushes to, and git has no reliable answer. `git rev-parse @{push}` fails under
the default `push.default` when the upstream has another name, and names the
start point under `push.default=upstream`. In a fork, `%(push:remotename)`
names `origin`, the parent. `hub::push_remote BRANCH` takes the first rule to
apply:

1. `branch.BRANCH.pushRemote`.
2. `remote.pushDefault`.
3. The upstream's remote, when the upstream has the branch's own name (the
   branch was pushed with `-u`).
4. The only remote, when there is exactly one.
5. The one remote whose push URL is a repository of the user's login: the
   user's fork.
6. `origin`, when it exists.

| Case | What hub does |
|---|---|
| No rule applies | No answer, and the command says so. |
| pushRemote or pushDefault is set but names no remote | No answer: an empty value, which git push refuses, or a URL, which git push takes as an anonymous remote but which has no remote-tracking refs for hub to read. |
| Rule 5 cannot read the user's login for a host | No answer: falling through to `origin` could mean the parent repository. |
| Two remotes of the user's login | Rule 5 falls through to `origin`. |
| An upstream of another name | Rule 3 skips it on purpose: after `git checkout -b fix origin/main`, the upstream is a start point, not a destination. Following it would push a topic branch onto `main`, or into the parent repository when the user has a fork. The branch's name on the remote is always its own. |

`hub::pushed BRANCH REMOTE` checks whether the branch is pushed. It returns 0
when `refs/remotes/REMOTE/BRANCH` contains `refs/heads/BRANCH`, and 1 when
either is missing. Otherwise it returns 2 and prints the count of unpushed
commits.

In this example, `origin` is rails/rails, `mislav` is the user's fork, and
both have the branch `fix`, made with `git checkout -b fix origin/main`:

```sh
# -u prints the URL instead of opening it. Rule 5 picks the user's fork:
hub --noop browse -u
# => https://github.com/mislav/rails/tree/fix
git config remote.pushDefault origin
# Rule 2 now picks origin:
hub --noop browse -u
# => https://github.com/rails/rails/tree/fix
```

`pull-request -p` pushes a full refspec, which never collides with a tag named
like the branch. A mirror remote makes git refuse the refspec, and hub relays
git's message. Remove the setting with `git config --unset remote.pushDefault`.
Rule 5 then picks the user's fork again:

```sh
git config --unset remote.pushDefault
hub --noop pull-request -p -m title
# => git push --set-upstream -- mislav HEAD:refs/heads/fix
# => gh pr create --repo github.com/rails/rails --head mislav:fix --title title --body ''
```

pull-request adds `--set-upstream` or leaves it out by the branch's upstream:

| Upstream | What hub does |
|---|---|
| None, a local branch, or a start point (as here) | Adds `--set-upstream`, so that `git push` and `hub sync` work afterwards. |
| The branch's own name (tracked, or a triangular setup, where pushRemote or pushDefault sends the branch to another remote than the one it pulls from) | Leaves `--set-upstream` out. |
| A start point on another remote, while pushRemote or pushDefault is set | Leaves `--set-upstream` out. |

## Testing

The bats tests never use the network or touch the user's repositories,
configuration or GitHub account. They assert effects (refs on the served
repositories, local refs and configuration, files, the gh log, the opened URL,
the copied text), and every run asserts its status. They assert `--noop`
output only for what cannot happen locally, such as gh creating a fork.

GitHub is a set of bare repositories reached with their real URLs, through a
`git-remote-https` stub and an `ssh` stub. The gh stub answers only what a
test registered, and fails any other call. Besides the isolation that
[Working on hub](development.md#run-the-tests) lists, `hub_test_setup` sets
`GH_PROMPT_DISABLED=1` and registers the login that gh answers on github.com:

```sh
stub_gh 'config get user -h github.com' mislav
```

[Working on hub](development.md#understand-the-fake-github) describes the
stubs and the helpers, and what the tests do not cover.

## Limitations

These limitations are the design's own. What the original hub had and this
hub leaves out, with the command to use instead, is in
[Not supported](../compatibility/not-supported.md).

| Area | Limitation |
|---|---|
| Unreadable configuration | Inside a repository whose configuration git cannot read, hub's own commands, `version`, `alias` and `help` included, get git's fatal message, because the re-entry goes through git. Plain git commands are unaffected. |
| Outside the work tree | hub's own commands must run from inside the work tree. With `--work-tree` or `GIT_WORK_TREE` and a current directory outside it, `hub::require_repo` refuses. |
| Push settings | For pull-request, browse and compare, hub does not read `remote.*.push` refspecs, `push.default` modes, custom fetch mappings or mirror remotes. The rules in [Where a branch pushes](#where-a-branch-pushes) decide, and `pull-request -p` pushes an explicit refspec. `hub push A,B` follows a remote's push refspecs and its mirror setting. |
| URL rewrites in push and fetch | `hub push` asks git how it reads a word with a comma, and `hub fetch` how it reads its first operand (`git ls-remote --get-url`). So a word git rewrites through `url.BASE.insteadOf` is one destination. git fetch `--multiple` never rewrites a list's members, so fetch asks only about the whole word. |
| URL rewrites in remote and push | `hub remote add` and `set-url` read `url.BASE.insteadOf` as git does, also for a word that names a remote, so such a word is stored as given. push does not read a rewrite set only through `url.BASE.pushInsteadOf`, and splits such a word as a list of remotes. |
| Split remotes | For a remote that fetches from one repository and pushes to another, `hub::pushed` reads the push remote's remote-tracking branch by name. Use `-p` or `-f` when it is wrong. |
| Old formats | hub does not read legacy `.git/remotes` files or a flow-style `hosts.yml`. |
| sync: the fetch | sync runs `git fetch --prune` with the user's fetch settings on every tracked remote. Nothing guards against other processes changing refs meanwhile. |
| sync: pull request branches | sync leaves alone the branches that `gh pr checkout` made for forks (upstream `refs/pull/N/head`). When the fetch refspecs map `refs/pull/*`, sync fast-forwards them like any other branch. |
| sync: branches not checked out | To move such a branch, sync fetches from the repository itself into that branch. Settings against local paths (`protocol.file.allow`, `GIT_ALLOW_PROTOCOL`) do not stop that fetch, and it does not recurse into submodules. The fetch of the remotes does, by the user's settings. |
| sync: other work trees | sync leaves a branch checked out in another work tree alone, but `git worktree list` does not show a branch that another work tree is rebasing or bisecting. With git older than 2.35, sync can fast-forward such a branch. git 2.35 and later refuse to move it. |
| cherry-pick | git cherry-pick also takes the revision walker's options (`--grep`, `--author` and others). hub's table leaves them out, so a commit URL given as their value is read as an operand. |
| pull-request | No `--no-edit` with `-h`, and no organization heads (a limitation of gh). |
| ci-status | It reports GitHub's combined verdict and lists the first 100 contexts under `-v`. A token that cannot read check runs gets gh's error. |

## See also

- [Working on hub](development.md): the tests, make targets and releases.
- [Install hub](../getting-started/install.md)
- [Shell completion](../getting-started/completions.md)
- [The project and its remotes](../guide/project-and-remotes.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [Not supported](../compatibility/not-supported.md)
- [README.md](../../README.md)
