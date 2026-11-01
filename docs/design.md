# Design

This document is for contributors: how hub reaches its commands, what a module
promises, and how hub decides what a command line means. The requirements are
in the [README](../README.md); make targets, the layout and releases are in
[development.md](development.md). One rule comes first: hub never runs the
wrong side effect. When it cannot tell what the user means, it stops with a
message or hands the command line to git untouched.

## Why a shell alias

git ignores an alias that hides a built-in command: `alias.clone` never runs
for `git clone`. A shell alias, `alias git=hub`, is the only way to see
`git clone OWNER/REPO` before git does; `hub alias` prints the line for the
user's shell. For a command hub does not handle, the cost is one bash start,
about 15 ms, before `exec git`. hub's own commands pay one more git and bash
start for the re-entry below. A user's git alias named like a hub command,
such as `alias.pr`, is shadowed by hub's command.

## Dispatch and re-entry

`bin/hub` reads `hub [--noop] [GIT-OPTIONS...] COMMAND [ARGS...]`. Up to the
hand-over to git it is bash 3.2 code (no `mapfile`, `declare -A` or `${x,,}`):
under the alias, `git status` must work with whatever bash `env` finds, and on
macOS that is `/bin/bash` 3.2. The dispatcher follows symbolic links to its
installation, exports `HUB_ROOT` and `HUB_LIB`, and walks the arguments.
`--noop` is hub's and is removed. `-C`, `-c`, `--config-env`, `--git-dir`,
`--work-tree`, `--namespace`, `--attr-source`, `--super-prefix` and
`--shallow-file` take the next word, whatever it is. Any other word starting
with `-` is a global flag, and the first other word is the command word.
`--version` and `-v` mean `version`; `--help` and `-h` mean `help`.

A command word is hub's when it matches `^[a-z][a-z0-9-]*$` and
`lib/hub/cmd/WORD.sh` exists. Otherwise hub sources nothing and runs
`exec git` with the arguments as given, minus `--noop`. Before either `exec`,
hub refuses to run when the first `git` on `PATH` is its own file, which
`exec git` would start again forever. For a hub command, the dispatcher
refuses a bash older than 5, then re-enters through git:

```
HUB_REEXEC=1 HUB_NOOP=0|1 HUB_KEEP_GIT_DIR=0|1 \
  exec git GLOBALS... -c "alias.hub-run=!exec 'PATH-TO-HUB' --run" hub-run COMMAND ARGS...
```

git applies the global options itself (`-C` without `CDPATH` or symbolic link
surprises, `-c` and `--config-env` in git's order, `--git-dir`, `--work-tree`,
`--bare`, `--namespace` and the rest) and exports their effect to every child
process. The re-entry is `--run` with the `HUB_REEXEC` marker; without the
marker, `--run` is an unknown option for git. hub checks bash 5 again, then
repairs two things git does to a `!` alias. When the current directory is
inside the work tree, git runs the alias from the top of the work tree and
exports the user's subdirectory as `GIT_PREFIX`: hub runs
`cd -P -- "./$GIT_PREFIX"` and unsets it, so relative paths keep their
meaning. git also exports the git directory it found as `GIT_DIR`, and without
`GIT_WORK_TREE` every git hub starts would take the subdirectory for the top
of the work tree: hub unsets `GIT_DIR` unless the user set it (`GIT_DIR` in
the environment, `--git-dir` or `--bare`, recorded as `HUB_KEEP_GIT_DIR=1`).
With it hub unsets `GIT_IMPLICIT_WORK_TREE`, which git exports as 0 from a
bare repository or a `.git` directory; left set, it would leave the hooks and
submodules of a clone that hub starts without a work tree. hub also unsets
`GIT_CONFIG`, which points git config, but no other git command, at another
file: hub's own queries then read the configuration that git push and the
rest read. A plain git command never reaches the re-entry and keeps it.
hub then exports `HUB_COMMAND`, sources `core.sh` and the module, and calls
`hub_cmd_NAME`. A word that is not a module is refused:
`hub: not a hub command: X`. `GIT_CONFIG_PARAMETERS` stays as git exported it,
so every git that hub or gh starts sees the user's `-c` values and the
harmless `alias.hub-run` entry. git's immediate options (`--exec-path`,
`--html-path`, `--list-cmds=`) need no special case: git answers and exits
before the alias runs.

**The promise of `--noop`.** Every git and gh command that changes something
is printed instead of run, quoted with `printf '%q '` so it can be pasted
back: the line hub would run, without global options and without the
environment they set. Read-only lookups still run, the patch downloads of `am`
and `apply` included. Opening and copying print `open URL` and `copy URL`. A
plain git command prints `git` and its arguments as given, global options
included. `HUB_NOOP` in the environment is ignored.

## Three kinds of command

Each module in `lib/hub/cmd/` is one command, and the first sentence of its
description states the kind in a fixed wording:

- **hub's own commands** (alias, browse, ci-status, compare, create, delete,
  fork, help, pull-request, sync, version): "hub's own command: these are all
  of its options." Any other option is a usage error. sync, which takes none,
  says "it takes no options", and help hands other arguments to `git help`.
- **gh's commands** (api, gist, issue, pr, release): "gh's command: gh NAME's
  options and output." hub maps hub 2.x's subcommand names (`show` is `view`,
  no subcommand is `list`) and runs `exec gh NAME ARGS...`.
- **git commands hub extends** (am, apply, checkout, cherry-pick, clone,
  fetch, merge, push, remote): "A git command hub extends: git NAME's options
  apply." hub reads the line only to find its operands, acts on its shorthands
  and GitHub URLs, and runs git; in doubt, `exec git NAME "$@"`.

`hub NAME --help` prints hub's manual, except for an extended git command,
where `--help` and `-h` are git's; there `hub help NAME` gives hub's manual.

## The module contract

**The header is the manual.** `hub help NAME` and `hub NAME --help` print the
module's leading `#` lines without `# `, skipping `# shellcheck` lines
(`hub::module_doc`): `Summary:`, `Usage:`, a short description, `Options:` and
examples (`$ hub ...` followed by `> git ...` or `> gh ...`). `hub help` lists
the Summary lines, the completions use them as descriptions, and a test checks
that the completions offer exactly each `Options:` block.

**Shared logic is `hub::*`.** Logic that two or more modules use lives in
`core.sh` as `hub::name`, with a one-line contract
(`# hub::name ARGS : what it gives.`). A helper prints its answer on stdout
and returns non-zero when it has none (`x=$(hub::name) || ...`); the few that
set a global name it (`HUB_ARGS`, `HUB_OPERANDS`, `HUB_OPTIONS`, `HUB_URL`).
Logic one module uses is a private `_hub_NAME_*` function in that module;
core's own are `_hub_core_*`. Modules never source each other.

**Side effects go through `hub::run`.** `hub::git` and `hub::gh` run git and
gh with side effects, `hub::exec_git` and `hub::exec_gh` hand the process
over, and all of them print instead under `--noop`. Read-only calls use
`hub::git_query` and `hub::gh_query`, or plain `git` and `gh` where the module
reads their messages.

**Validate before the first side effect.** Every check and read-only lookup
comes first: fetch asks GitHub about every new user before it adds the first
remote, and pull-request refuses to prompt without a terminal before it
pushes. A command that needs gh calls `hub::require_gh` once, before any
lookup, and every gh call names the host. When git or gh fails, its own
message reaches the user unchanged. The exit status is the handed-over
program's, or 1 for hub's refusals; ci-status documents 0 to 3.

**One message format.** `hub::die` prints `hub NAME: MESSAGE` on stderr and
exits 1; the dispatcher's prefix is `hub:`. A message is one lowercase
sentence, unless it starts with a name or value given verbatim. It names the
offending value first or after a colon, and ends with the way out in
parentheses when there is one:
`remote already exists: X (name another with --remote-name NAME)`. Refusals
that echo a user's word, such as `unexpected argument: X`, show it through
`hub::shown`: an empty word is `''`, a newline `$'...'`. `hub::usage_error`
adds the header's Usage lines; `hub::warn` prints
`hub NAME: warning: MESSAGE`, and the command goes on. hub's own commands
split clusters and detach values with `hub::normalize_opts`, then name every
option in a `case` loop that refuses `unknown option: X`.

## Operands of the git commands hub extends

An extended command finds its operands without knowing all of git's options:
`hub::scan VALUED ARGS...` walks ARGS with VALUED, the command's table of
options that take a separate value. After `--` or `--end-of-options` every
word is an operand. A table entry consumes the next word, whatever it looks
like; `--long=value` is one word; a short cluster ends at its first
value-taking letter, the rest of the word being the value. `-` and words not
starting with `-` are operands; other options are flags. An entry `-X=` marks
a letter whose optional value is only attached (merge's `-S[KEYID]`). The scan
sets `HUB_OPERANDS` and `HUB_OPTIONS`.

| command | separate-value options |
|---|---|
| clone | `-o --origin -b --branch -u --upload-pack --reference --reference-if-able --separate-git-dir --depth --shallow-since --shallow-exclude -j --jobs --template -c --config --filter --bundle-uri --server-option --ref-format --revision` |
| fetch | `--depth --deepen --shallow-since --shallow-exclude --refmap -j --jobs -o --server-option --upload-pack --negotiation-tip --filter` |
| push | `-o --push-option --repo --receive-pack --exec --recurse-submodules` |
| remote add | `-t --track -m --master` |
| merge | `-m --message -F --file -s --strategy -X --strategy-option --into-name --cleanup`, and `-S=` |
| am | `-p -C --exclude --include --directory --whitespace --patch-format --resolvemsg --quoted-cr --empty`, and `-S=` |
| apply | `-p -C --exclude --include --directory --whitespace --build-fake-ancestor` |
| cherry-pick | `-m --mainline --strategy -X --strategy-option --cleanup --empty`, and `-S=` |

The tables come from `git CMD -h` of git 2.54. A test checks them against
git's output, and that no flag of the command is a proper prefix of an entry.
Options whose optional value is attached only, such as
`--force-with-lease[=X]`, stay out: with `=` they are one word, bare they are
flags. am, apply and cherry-pick convert only the operands before `--` (or
`--end-of-options`), so a URL given as an option's value (`--include URL`)
reaches git as given. checkout looks for a pull request URL before `--`; only
`--pathspec-from-file`'s value can be one, so a line with a word starting
`--pathspec-f` (the option, its prefixes, its `=` form or
`--pathspec-file-nul`) goes to git untouched, and checkout needs no table.
hub hands the command line to git untouched when it cannot read it with
certainty:

1. a `--word` without `=` that is not in the table but is a proper prefix of
   an entry, which git would expand (`--dep 1`);
2. a short cluster in which a value-taking letter follows another letter
   (`-qb main`);
3. a value-taking option as the last word, which git refuses.

`--help`, `--help-all` and `h` among a cluster's flags also go to git. A
module that reads some of git's options itself is as careful: an abbreviation
such as merge's `--squ` or fetch's `--mul` hands the command line to git.
`hub::drop_flag` removes hub's `-p` from clone and `remote add` before the
scan, so no line handed to git carries it.

## Repository, host and identity

**The project.** `hub::project` prints `HOST OWNER REPO`: `GH_REPO` when set
(`OWNER/REPO`, `HOST/OWNER/REPO` or a URL; an invalid value is an error), else
the first GitHub remote among `upstream`, `github` and `origin`, then the
others in `git remote` order. `hub::project_remote` is the first remote, in
that order, that points at the project, so it works under `GH_REPO` too.

**Hosts.** hub has no host list of its own. `hub::gh_hosts` reads the
top-level keys of gh's `hosts.yml` (in `$GH_CONFIG_DIR`, else
`$XDG_CONFIG_HOME/gh`, else `~/.config/gh`), in the block style gh writes.
`hub::host` is `GH_HOST`, else the one host gh is logged in to, else
github.com, in lowercase; a `GH_HOST` that is not a host name is an error.
When only hub 2.x's `GITHUB_HOST` is set, `core.sh` exports it as `GH_HOST`. A
known host is github.com, `GH_HOST` or a gh host, in any case.

**Login and protocol.** `hub::login HOST` is gh's cached user
(`gh config get user -h HOST`). With `GH_TOKEN`, `GITHUB_TOKEN`,
`GH_ENTERPRISE_TOKEN` or `GITHUB_ENTERPRISE_TOKEN` set, the API answers
instead, since the token may be someone else's. Neither falls back to the
other; when nothing answers, hub stops and names `gh auth login -h HOST`.
`hub::protocol HOST` is gh's `git_protocol` for the host, else https, also
without gh: `gh config set git_protocol ssh` is the setting, and `-p` on clone
and `remote add` is a one-off. `hub::clone_url` builds `https://HOST/O/R.git`
or `git@HOST:O/R.git`; on `*.ghe.com` the ssh user is the tenant.

**URLs.** `hub::parse_url` reads https, http, git, ssh (also `git+ssh` and
`ssh+git`) and scp-like URLs (no `/` before the first colon) as
`HOST OWNER REPO`. The host is lowercased and the port ignored; OWNER and REPO
must have GitHub's shapes, and the host must be known. For an ssh URL with an
unknown host, hub asks `ssh -G HOST` once, with the alias as written, and
takes its `hostname`; `ssh.github.com` is github.com. `hub::parse_project`
reads what users type; a three-part host must contain a dot or be known, so
`cli/cli/issues` is refused. `hub::default_branch` follows
`refs/remotes/REMOTE/HEAD` when that symbolic ref and its target exist, else
asks gh; a command that changes something never assumes `main`.

## Where a branch pushes

pull-request, browse and compare need the repository the current branch pushes
to. `hub::push_remote BRANCH` takes the first rule that applies:

1. `branch.BRANCH.pushRemote`;
2. `remote.pushDefault`;
3. the upstream's remote, when the upstream has the branch's own name (the
   branch was pushed with `-u`);
4. the only remote, when there is exactly one;
5. the one remote whose push URL is a repository of your login: your fork;
6. `origin`, when it exists.

Otherwise there is no answer, and the command says so. A pushRemote or
pushDefault that is set but empty is no answer either, as git push refuses it.
When rule 5 cannot read your login for a host, there is no answer: falling
through to `origin` could mean the parent repository. Two remotes of your
login fall through to `origin`.

Rule 3 skips an upstream of another name on purpose. After
`git checkout -b fix origin/main`, the upstream is a start point, not a
destination: following it would push a topic branch onto `main`, or into the
parent repository when the user has a fork. The branch's name on the remote is
always its own. `hub::pushed BRANCH REMOTE` returns 0 when
`refs/remotes/REMOTE/BRANCH` contains `refs/heads/BRANCH`, 1 when either is
missing, and otherwise 2 with the count of unpushed commits on stdout.

`pull-request -p` runs
`git push [--set-upstream] -- REMOTE HEAD:refs/heads/BRANCH`: the full refspec
never collides with a tag named like the branch. `--set-upstream` is added
when the branch has no upstream, a local one, or a start point, so that
`git push` and `hub sync` work afterwards. It is left out when the upstream
has the branch's own name (tracked, or a triangular setup), and for a start
point on another remote while pushRemote or pushDefault is set. A mirror
remote makes git refuse the refspec; git's message is relayed.

## Testing

The bats tests never use the network or touch the caller's repositories,
configuration or GitHub account. `hub_test_setup` unsets every `GIT_*`,
`GH_*`, `GITHUB_*` and `HUB_*` variable, `CDPATH`, `BROWSER`, `BASH_ENV` and
`ENV`, and gives each test its own directory, `HOME`, git and gh
configuration, `GH_PROMPT_DISABLED=1` and `LC_ALL=C`. GitHub is a set of bare
repositories under `$HUB_TEST_SRV/HOST/OWNER/REPO.git` (`serve_github`),
reached with their real GitHub URLs: a `git-remote-https` stub in a private
`GIT_EXEC_PATH` serves https and http, and an `ssh` stub serves ssh and
scp-like URLs, passing `ssh -G` to the real ssh with the test `HOME`'s
configuration only. The gh stub logs every call and replays the latest
registration whose glob matches (`stub_gh 'ARGS GLOB' STDOUT [STATUS]`); an
unregistered call exits 97. The browser and clipboard stubs record the URL and
the text.

Tests assert effects: refs on the served repositories, local refs and
configuration, files, the gh log, the opened URL, the copied text. `--noop`
output is asserted only for what cannot happen locally, such as gh creating a
fork. Every run asserts its status. Not tested automatically: gh's prompts
and editor (the refusals without a terminal are tested); the bash 3.2 path,
run only where `/bin/bash` is older than 5; fish completion beyond `fish -n`;
GitHub itself, the workflows and the formula's `brew test`.

## Adding a command

Write `lib/hub/cmd/NAME.sh` header first (Summary, Usage, the kind sentence,
Options, two or three examples) and define `hub_cmd_NAME`, with dashes turned
into underscores; the dispatcher and `hub help` find the module by its file
name. Parse as the kind requires: `hub::normalize_opts` and a closed `case`
loop, `hub::gh_subcommand`, or `hub::scan` with a table pinned by a test.
Check everything, then run side effects through `hub::git`, `hub::gh` or the
`exec` helpers, and lookups through `hub::git_query` and `hub::gh_query`.
Write `test/NAME.bats` asserting effects. Add NAME, its Summary and, for hub's
own, its options to the three completion files; `test/completions.bats` fails
until they match. Then run `make check`.

## Limitations

These limitations are the rewrite's own. What hub 2.x had and this hub leaves
out, with the command to use instead, is in
[compatibility.md](compatibility.md).

- Inside a repository whose configuration git cannot read, hub's own
  commands, `version`, `alias` and `help` included, get git's fatal message,
  because the re-entry goes through git. Plain git commands are unaffected.
- hub's own commands must run from inside the work tree: with `--work-tree`
  or `GIT_WORK_TREE` and a current directory outside it,
  `hub::require_repo` refuses. Plain git commands are unaffected.
- For pull-request, browse and compare, `remote.*.push` refspecs,
  `push.default` modes, custom fetch mappings and mirror remotes are not read:
  the rules in [Where a branch pushes](#where-a-branch-pushes) decide, and
  `pull-request -p` pushes an explicit refspec. `hub push A,B` follows a
  remote's push refspecs and its mirror setting.
- `hub push` asks git how it reads a word with a comma, and `hub fetch` how
  it reads its first operand (`git ls-remote --get-url`), so a word git
  rewrites through `url.BASE.insteadOf` is one destination. `hub remote add`
  and `set-url` read `url.BASE.insteadOf` as git does, also for a word that
  names a remote, so such a word is stored as given. A rewrite set only
  through `url.BASE.pushInsteadOf` is not read by push, and such a word is
  split as a list of remotes. git fetch `--multiple` never
  rewrites a list's members, so fetch asks only about the whole word.
- For a remote that fetches from one repository and pushes to another, the
  pushed check reads the push remote's remote-tracking branch by name; use
  `-p` or `-f` when it is wrong.
- Legacy `.git/remotes` files and a flow-style `hosts.yml` are not supported.
- sync runs `git fetch --prune` with your fetch settings on every tracked
  remote. Branches that `gh pr checkout` made for forks (upstream
  `refs/pull/N/head`) are left alone, unless the fetch refspecs map
  `refs/pull/*`; then sync fast-forwards them like any other branch.
  Nothing guards against other processes changing refs meanwhile. sync
  leaves a branch checked out in another work tree alone, but
  `git worktree list` does not show a branch that another work tree is
  rebasing or bisecting: with git older than 2.35, sync can fast-forward
  such a branch (git 2.35 and later refuse to move it).
- git cherry-pick also takes the revision walker's options (`--grep`,
  `--author` and others); hub's table leaves them out, so a commit URL given
  as their value is read as an operand.
- pull-request does not support `--no-edit` with `-h`, or organization heads
  (a limitation of gh).
- ci-status reports GitHub's combined verdict and lists the first 100
  contexts under `-v`; a token that cannot read check runs gets gh's error.
