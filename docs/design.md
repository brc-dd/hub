# hub: design

hub is a small bash program that sits in front of git. It handles a few
GitHub-aware commands itself and hands everything else to the real git,
unchanged. It does no GitHub API work of its own: every request, login, token
and host setting belongs to the official GitHub CLI, `gh`.

## Why `alias git=hub` works

git cannot be taught new behaviour for its own commands. When you run
`git clone`, git looks for a built-in command, then a `git-clone` program on
PATH, and only then for an alias; git-config(1) says aliases that hide
existing git commands are ignored. So `git config alias.clone '!…'` never
changes `git clone OWNER/REPO` (checked: `git -c alias.clone='!echo X' clone
a/b` runs the real clone). A git alias can only add *new* names, such as
`git pr`.

A shell alias works one step earlier. With `alias git=hub`, the interactive
shell replaces the word `git` with `hub` before any program starts, so every
git command typed at the prompt reaches hub first. That is exactly how the
original Go hub worked. hub then decides:

- the command word is one of hub's (a module exists for it): hub handles it;
- anything else: `exec git` with the original arguments, nothing changed.

Because only the interactive shell expands aliases, scripts, Makefiles,
editors and git itself (git calling git) keep using the real git. `hub alias`
prints the line for each shell (`alias git=hub`, or `alias git hub` for csh
and tcsh).

The cost is one bash start-up per git command: about 15 ms on a busy laptop,
measured against plain git. The fast path sources nothing.

## Prerequisites

- **bash 5 or newer.** macOS ships bash 3.2; install a current one with
  Homebrew (`brew install bash`) and put Homebrew's bin directory before
  `/bin` in PATH. `bin/hub` uses `#!/usr/bin/env bash` and refuses to run on an
  older bash, with that hint.
- **git**, and **gh** logged in (`gh auth login`, plus `gh auth login -h HOST`
  for GitHub Enterprise). Commands that only build URLs or run git work
  without gh.
- Optional: `open`, `xdg-open`, `$GH_BROWSER` or `$BROWSER` for the browser, and a clipboard
  tool (`pbcopy`, `wl-copy`, `xclip`) for `-c`.

## Layout

```
bin/hub                 dispatcher
lib/hub/core.sh         helpers shared by all modules (hub::*)
lib/hub/cmd/NAME.sh     commands git doesn't have: pull-request, browse, fork, ...
lib/hub/ext/NAME.sh     git commands hub extends (clone, push, fetch, ...), and sync
completions/            bash, zsh and fish completion
test/                   bats tests, the gh stub and the test helper
```

## Dispatch

`bin/hub` does, in order:

1. Checks the bash version.
2. Finds its installation by following symlinks (so a link in
   `/usr/local/bin` works), and sets `HUB_ROOT` and `HUB_LIB`.
3. Reads git's global options in front of the command word, as git would:
   `-C DIR` changes directory; `-c KEY=VALUE` is exported through
   `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` so that every git
   that runs later sees it; `--git-dir`, `--work-tree`, `--no-pager` and the
   other global options are kept in `HUB_GIT_OPTS` and passed to every git
   call. `--noop` is hub's own. `--version` and `--help` go to hub's `version`
   and `help`. An option hub doesn't know ends the scan, and git gets the whole
   command line.
4. If the command word looks like a plain name (`^[a-z][a-z0-9-]*$`) and
   `lib/hub/cmd/NAME.sh` or `lib/hub/ext/NAME.sh` exists, sources `core.sh`,
   locates the real git (`hub::find_git` skips hub itself, even if someone
   installed hub as `git`), sources the module and calls
   `hub_cmd_NAME` / `hub_ext_NAME` (dashes become underscores) with the
   remaining arguments.
5. Otherwise takes the **fast path**: `exec git` with the forwarded options,
   the command word and the arguments. Nothing is sourced. Under `--noop` the
   git command line is printed instead.

## Module contract

- **File name = command name.** `cmd/` holds commands git doesn't have.
  `ext/` holds the git commands that hub extends, which must hand anything
  they don't handle to git unchanged (`hub::exec_git`), plus `sync`, which
  only runs git.
- **Entry point** `hub_cmd_NAME` or `hub_ext_NAME`; private helpers are named
  `_hub_NAME_*`. Modules only use `hub::*` from core.sh and their own helpers.
- **The header is the manual.** The leading comment block holds
  `# Summary:` (one line; `hub help` lists it), `# Usage:`, a description,
  the options and examples (`$ command` followed by `> what runs`).
  `hub help NAME` prints it, and so does `hub NAME --help` through
  `hub::usage`.
- **Side effects go through helpers** that `--noop` turns into printed,
  shell-quoted command lines: `hub::git`, `hub::gh`, `hub::run`,
  `hub::exec_git`, `hub::exec_gh` (`git …`, `gh …`), `hub::open_url`
  (`open URL`) and `hub::copy` (`copy to clipboard: …`). Read-only lookups use
  `hub::git_query` and `hub::gh_query`, which always run, so `--noop` shows
  what would really happen in this repository.
- **Hand over with exec** when nothing follows, so that gh or git owns the
  terminal, the prompts and the exit status.
- **Errors** go through `hub::die` (stderr, exit 1). Messages start with
  `Aborted:` or `hub NAME:`; usage errors print the Usage line.
- Helpers that "return" more than one value set documented `HUB_*` globals,
  e.g. `hub::main_project` prints OWNER/REPO and sets `HUB_PROJECT_HOST`.

## Repository, host and identity

- **The current project** is the first GitHub remote among `upstream`,
  `github` and `origin`, then any other GitHub remote (`hub::main_remote`).
  `GH_REPO=[HOST/]OWNER/REPO` overrides it (`hub::main_project`).
- **GitHub hosts** are github.com, `GH_HOST`, `GITHUB_HOST` and every
  `git config hub.host` entry. A remote whose host is an ssh_config alias is
  resolved with `ssh -G`. Explicit `OWNER/REPO` arguments use the default
  host (`hub::host`), which follows gh's own rule: `GH_HOST`, else the single
  host gh is logged in to (read from gh's `hosts.yml`), else github.com. hub
  2.x's `GITHUB_HOST` is accepted and exported to gh as `GH_HOST`, so both
  tools always resolve the same host.
- **Your login** comes from gh's cached `gh config get user -h HOST`, else
  `gh api user` (`hub::current_user`). A bare `REPO` argument means
  `LOGIN/REPO`.
- **The default branch** is read from `refs/remotes/REMOTE/HEAD`, else asked of
  gh, else `main`.
- **Remote URLs** use `git config hub.protocol`, else gh's `git_protocol`,
  else https.
- **Branch-aware commands** (browse, compare) look at where the current branch
  pushes (`%(push:remotename)`), so a branch that tracks your fork is opened
  in, or compared from, the fork.

## Option design

Which option letters a command takes depends on whose command name it is:

- **Names gh also has** (`pr`, `issue`, `release`, `gist`, `api`) take gh's
  options: hub runs the gh command of the same name and only maps the old hub
  subcommands and argument forms that gh lacks (`pr show`, `issue update`,
  `release -a`, `api --cache 600`).
- **hub-only names** (`pull-request`, `browse`, `compare`, `create`, `fork`,
  `delete`, `ci-status`, `sync`, `alias`) keep hub's option letters and
  translate them for gh (`create -p` is gh's `--private`, `delete -y` is
  `--yes`, `pull-request -b/-h` are `--base/--head`). Where the old default
  was risky, the safer one wins: `hub create` makes private repositories.
- **git commands hub extends** (`clone`, `fetch`, `push`, `remote`,
  `checkout`, `merge`, `am`, `apply`, `cherry-pick`) take git's options; hub
  only recognises its GitHub shorthands (`clone OWNER/REPO`, `push a,b`,
  `fetch USER`, pull-request and commit URLs).

hub doesn't imitate old hub's output or prompts: what you see is gh's and
git's.

## Testing

- The suite is [bats](https://github.com/bats-core/bats-core); `make check`
  runs shellcheck and then `bats --recursive test`. CI runs it on Ubuntu and
  macOS.
- `test/test_helper.bash` gives each test an empty HOME, git config and gh
  config directory, and puts `test/stubs/gh` first in PATH. The stub logs
  every call and replays responses registered with
  `stub_gh 'ARGS GLOB' 'STDOUT' [EXIT]`; an unexpected call exits 97.
  `config get user -h github.com` answers `mislav` by default.
- Most tests run `hub --noop …` and compare the exact `git …`, `gh …` and
  `open URL` lines (`assert_output_equals`, `assert_gh_called`,
  `assert_gh_not_called`). Fixture repositories are made with real git
  (`make_repo NAME remote=URL…`, `set_remote_head`).
- Behaviour that only shows without `--noop` is tested against local bare
  repositories (push, fork's fetch) or a throwaway gh shim (create's working
  directory). No test uses the network.

## Adding a command

1. Choose `lib/hub/cmd/NAME.sh` (new command) or `lib/hub/ext/NAME.sh` (a git
   command hub extends).
2. Write the header: `# shellcheck shell=bash`, `# Summary:`, `# Usage:`,
   description, options, examples.
3. Define `hub_cmd_NAME` (or `hub_ext_NAME`): parse the arguments, call
   `hub::usage` for `--help`, and do the work with the `hub::*` helpers.
4. Add `test/cmd/NAME.bats` (`load ../test_helper`, `run hub --noop NAME …`).
5. A new command name also goes into the three files in `completions/`.
6. Run `make check`.

## Install

`make install [PREFIX=/usr/local]` symlinks `bin/hub` into `$PREFIX/bin` and
the completions into `$PREFIX/share/zsh/site-functions/_hub`,
`$PREFIX/etc/bash_completion.d/hub` and
`$PREFIX/share/fish/vendor_completions.d/hub.fish` when those directories
exist. It never replaces a file it didn't link, and `make uninstall` removes
only its own links. The completions make `git <TAB>` keep working through the
alias (zsh's `_git`, git's bash completion and fish's git completion do the
work) and add hub's own commands.

## Non-goals

- No `--format`/`-f` placeholder templates; use gh's `--json`, `--jq` and
  `--template`.
- No authentication, token storage, configuration file or API client of its
  own; that is all gh (`gh auth login`, `gh auth refresh -s delete_repo`).
- Not installed as `git` and not a replacement for git in scripts: it is an
  interactive-shell alias.
- No reproduction of old hub's output formats, prompts or quirks.

## Follow-ups

Helpers that two or more modules currently define privately and that belong in
`lib/hub/core.sh` once their shape has settled:

- `hub::project_vars` — set `HUB_PROJECT` and `HUB_PROJECT_HOST` without
  printing (`hub::main_project` prints, so its host is lost inside `$(…)`);
  used by browse, compare, fork and pull-request.
- `hub::push_target BRANCH` — the remote and branch a branch pushes to;
  duplicated in browse, compare and pull-request.
- `hub::remote_for_project OWNER/REPO HOST` — the local remote pointing at a
  project; duplicated in merge and cherry-pick.
- `hub::gh_hostname_args HOST` — `--hostname HOST`; inlined in am, cherry-pick,
  ci-status and pull-request (the last two now always pass it, since gh's
  default host can differ from the project's).
- `hub::message FILE|MSG…` — join repeated `-m` values or read `-F FILE`, then
  `hub::split_message`; duplicated in issue, release and pull-request.
- `hub::url_escape STR` — percent-encode a path segment; duplicated in browse
  and compare.
- `hub::next_opt` — split `--x=v`, `-xv` and `-x v` option forms; the same scan
  loop appears in five parsers.

