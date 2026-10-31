# hub: design

hub is a small bash program that sits in front of git. It handles a few
GitHub-aware commands itself and hands everything else to the real git,
unchanged. It does no GitHub API work of its own: every request, login, token
and host setting belongs to the official GitHub CLI, `gh`.

Two rules shape the whole program:

- **git is the only authority on git's command line.** hub never interprets
  git's global options (`-C`, `-c`, `--git-dir`, `--bare`, ...). For a plain
  git command it passes the command line through untouched; for one of its
  own commands it lets git apply those options and then re-enters hub (see
  [Dispatch](#dispatch)).
- **A command either owns its grammar or passes it on; never both.** A
  hub-owned command documents every option it takes and rejects the rest. A
  gh-backed command maps a subcommand name and hands everything else to gh.
  A git command that hub extends recognizes its GitHub shorthands and hands
  everything else to git. No command translates some of another tool's
  options and guesses at the rest.

## Why `alias git=hub` works

git cannot be taught new behavior for its own commands. When you run
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
measured against plain git. The fast path sources nothing. hub's own commands
pay for one more git and bash start, about 20 ms.

## Prerequisites

- **bash 5.3 or newer.** macOS ships bash 3.2; install a current one with
  Homebrew (`brew install bash`) and put Homebrew's bin directory before
  `/bin` in PATH. `bin/hub` uses `#!/usr/bin/env bash` and refuses to run on an
  older bash, with that hint.
- **git 2.41 or newer**: hub relies on `%(push:remoteref)` in
  git-for-each-ref, `--end-of-options`, `git switch` and `git -c` with
  `--config-env`.
- **gh 2.40 or newer**, logged in (`gh auth login`, plus `gh auth login -h HOST`
  for GitHub Enterprise). hub uses `gh repo create --source --remote --push`,
  `gh repo fork --remote --remote-name`, `gh pr create --head`,
  `gh pr checkout -b/--detach`, `--json` output and `gh api -F/--jq`. Commands
  that only build URLs or run git work without gh.
- Optional: `open`, `xdg-open`, `$GH_BROWSER` or `$BROWSER` for the browser,
  and a clipboard tool (`pbcopy`, `wl-copy`, `xclip`) for `-c`.

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

`hub [--noop] [GIT-OPTIONS...] COMMAND [ARGS...]`

`bin/hub` does, in order:

1. Checks the bash version, and that `git` in PATH is not hub itself (hub
   installed under the name `git` would otherwise call itself forever).
2. Finds its installation by following symlinks (so a link in
   `/usr/local/bin` works), and sets `HUB_ROOT` and `HUB_LIB`.
3. **Finds the command word without interpreting anything.** It walks the
   leading arguments: `--noop` is hub's own and is removed; an argument that
   is one of git's value-taking global options (`-C`, `-c`, `--config-env`,
   `--git-dir`, `--work-tree`, `--namespace`, `--attr-source`, `--super-prefix`,
   `--shallow-file`) skips the value after it; any other argument starting
   with `-` is skipped as a flag; the first remaining argument is the command
   word. `--version`/`-v` and `--help`/`-h` stand for hub's `version` and
   `help`, as in git. The options git answers by itself and exits
   (`--exec-path` without a value, `--html-path`, `--man-path`, `--info-path`,
   `--list-cmds=...`) end the search: git gets the whole command line, and a
   command word after them is never run. hub does not add its commands to
   `--list-cmds`; the completions list them.
4. **Verbatim passthrough.** If the command word is not the name of a module
   (`^[a-z][a-z0-9-]*$` with `lib/hub/cmd/NAME.sh` or `lib/hub/ext/NAME.sh`),
   or there is no command word, hub runs `exec git` with the original
   arguments, minus `--noop`. Nothing is sourced; an empty command word, an
   unknown option or a missing option value is git's to reject. Under `--noop`
   the git command line is printed instead.
5. **Re-entry through git.** For a module, hub runs

   ```
   exec git GIT-OPTIONS... -c alias.hubrun='!exec /path/to/hub --run' hubrun N GIT-OPTIONS... COMMAND ARGS...
   ```

   git applies the global options itself, exactly as it would for any
   command: it changes directory for `-C`, captures the git directory for
   `--bare` at that point of the command line, resolves `--git-dir`,
   `--work-tree` and `--namespace`, exports `GIT_CONFIG_PARAMETERS` for `-c`
   and `--config-env` (keeping their order, valueless keys and every byte),
   and sets `GIT_NO_REPLACE_OBJECTS`, `GIT_NO_LAZY_FETCH`,
   `GIT_OPTIONAL_LOCKS`, `GIT_LITERAL_PATHSPECS`, `GIT_PAGER=cat` for
   `--no-pager`, and so on. Then it runs the alias, which starts hub again
   with `--run`. git rejects anything it doesn't understand before hub runs
   anything. The alias is given on the command line, so it beats a user alias
   of the same name, and git runs it from the top of the working tree with
   `GIT_PREFIX` set to the original subdirectory. `N` is the number of global
   options that follow; hub only uses them to print faithful `--noop` lines.
6. **The re-entered hub** (`hub --run ...`) goes back to the user's directory
   (`cd -P -- "./${GIT_PREFIX:-.}"`), so relative paths in the arguments and
   in `GIT_WORK_TREE` mean what the user meant; the directory hub was started
   in travels along as `HUB_INVOKED_PWD`, for `--noop`'s gh lines. It unsets
   `GIT_DIR` when neither the user's environment nor the command line set it:
   git exports the directory it discovered, but a `GIT_DIR` without
   `GIT_WORK_TREE` would make the user's subdirectory the work tree. With
   `--git-dir`, `--bare` or a `GIT_DIR` in the environment, git's `GIT_DIR`
   stays. It removes its own alias from `GIT_CONFIG_PARAMETERS`, sources
   `core.sh` and the module, and calls `hub_cmd_NAME` / `hub_ext_NAME`
   (dashes become underscores) with the remaining arguments. Every git and gh
   the module runs inherits this environment, so the same context reaches
   hub's own git commands and the git commands gh runs.

   `--run` is internal: it is honored only with the marker hub sets in the
   environment for the alias.

## Module contract

Which options a command takes depends on whose command it is. Each module is
exactly one of these three kinds and says so in its header.

- **hub-owned commands** (`cmd/`: pull-request, create, fork, browse, compare,
  ci-status, delete, alias, help, version; `ext/sync`) own a closed grammar:
  the header lists every option, `hub::normalize_opts` splits clusters
  (`-pf`), attached values (`-bmain`, `--base=main`) and `--`, and the
  module's `case` rejects anything else with a usage error. They translate
  their options into gh's and never pass unknown options on. Where old hub's
  default was risky, the safer one wins: `hub create` makes private
  repositories. Compound operations use gh's own compound commands
  (`gh repo create --source --remote --push`, `gh repo fork --remote`) rather
  than hub's own sequence of calls, and validate everything local before the
  first step that changes anything anywhere.
- **gh-backed commands** (`cmd/`: pr, issue, release, gist, api) take gh's
  options. hub finds the subcommand word as gh does (`-x VALUE` and `--long
  VALUE` take the next argument, `-xVALUE` and `--long=VALUE` are complete,
  `--` ends the search), maps the few old hub subcommand names gh lacks
  (`show` to `view`, no subcommand to `list`) and runs `exec gh NAME ...`
  with every other argument in place.
  Old hub's option letters for these commands are not translated; gh's
  apply. Behavior hub cannot see, such as which host a URL argument selects,
  is gh's.
- **git commands hub extends** (`ext/`: clone, fetch, push, remote, checkout,
  merge, am, apply, cherry-pick) take git's options. hub reads them as the
  installed git does, only so that it can find the operands: the long
  options, which of them take a value and what an abbreviation stands for
  come from git's own option table (`git CMD --git-completion-helper-all`),
  the short options from the usage `git CMD -h` prints (both through
  `hub::git_option`), and each module names the few short options that take
  a value (`-j 4`, `-Skey`). Among the operands hub recognizes its GitHub
  shorthands (`clone OWNER/REPO`, `push a,b`, `fetch USER`, `remote add
  USER`, pull-request and commit URLs, `USER@SHA`). Everything else,
  anything ambiguous and an option git would refuse is `hub::exec_git` with
  the arguments as given.

Common rules:

- **File name = command name.** `cmd/` holds commands git doesn't have;
  `ext/` holds the git commands that hub extends, plus `sync`.
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
  (`open URL`) and `hub::copy` (`copy to clipboard: …`). Printed git lines
  start with the global options the user gave hub, so they can be pasted
  back into the same shell. gh has no `-C`, so a printed gh line becomes
  `(cd DIR && gh …)` when `-C` moved hub away from the directory it was
  started in (`HUB_INVOKED_PWD`, `hub::gh_line`), and a gh that needs a
  variable is printed as `env VAR=VALUE gh …`. Read-only lookups use
  `hub::git_query` and `hub::gh_query`, which always run, so `--noop` shows
  what would really happen in this repository.
- **Never change directory.** The user's directory is the context for every
  relative path and environment value; a module that needs the top of the
  work tree asks git for it (`hub::toplevel`) and passes it on.
- **Validate before the first side effect**, and when a later step fails,
  say what already happened (the URL of a repository or pull request that
  was created). A failed browser or clipboard step is a failure of the
  command, after everything else is done.
- **Hand over with exec** when nothing follows, so that gh or git owns the
  terminal, the prompts and the exit status.
- **Errors** go through `hub::die` (stderr, exit 1). Messages start with
  `Aborted:` or `hub NAME:`; usage errors print the Usage line.
- Helpers that "return" more than one value set documented `HUB_*` globals,
  e.g. `hub::main_project` prints OWNER/REPO and sets `HUB_PROJECT_HOST`.

## Repository, host and identity

- **The current project** is the first GitHub remote among `upstream`,
  `github` and `origin`, then any other GitHub remote (`hub::main_remote`,
  which lists `git remote`; remotes defined in the legacy `.git/remotes` and
  `.git/branches` files are not considered). `GH_REPO` overrides it and must
  be `OWNER/REPO`, `HOST/OWNER/REPO` or a repository URL, gh's own rule
  (`hub::parse_project`): no empty or extra parts, no trailing slash.
- **Remote URLs** are parsed by scheme (`hub::parse_remote_url`): `https`,
  `http`, `ssh`, `git` and scp-like `user@host:owner/repo`, with exactly
  `OWNER/REPO[.git]` as the path. `file://` and extra path components are not
  GitHub repositories.
- **GitHub hosts** are github.com, `GH_HOST`, `GITHUB_HOST`, every host gh is
  logged in to (read from gh's `hosts.yml`, in the block style gh writes or
  in a flow mapping a hand edit may have left) and every `git config hub.host`
  entry. For an SSH remote, hub asks the ssh git would run (`GIT_SSH_COMMAND`,
  `core.sshCommand`, `GIT_SSH`, else `ssh`) what host an alias really means
  (`ssh -G`, with the URL's user and port, so `Match` rules see the same
  connection); a program that isn't OpenSSH is not asked. `ssh.github.com` is
  github.com after that. HTTPS hosts are taken literally; ssh_config never
  rewrites them. Explicit `OWNER/REPO` arguments use the default host
  (`hub::host`), which follows gh's rule: `GH_HOST`, else the single host gh is
  logged in to, else github.com. hub 2.x's `GITHUB_HOST` is accepted and
  exported to gh as `GH_HOST`, so both tools resolve the same host.
- **Your login** comes from gh's cached `gh config get user -h HOST`, else
  `gh api user` (`hub::current_user`). A bare `REPO` argument means
  `LOGIN/REPO`.
- **Shorthand precedence** (`hub::is_project_name`, `hub::local_source`): an
  operand is a GitHub shorthand only when it is lexically one (`REPO`, which
  may start with a dot, as `.github`, or `OWNER/REPO`) and git would not read
  it as something local: an existing remote or remote group name is a
  remote; an existing path, or `NAME.git` holding a repository (and
  `NAME.bundle`, for clone) is a local source. `remote add NAME` with one
  operand expands regardless of paths, since git gives that form no meaning.
- **Branches** are read as full refs (`refs/heads/NAME`,
  `refs/remotes/REMOTE/NAME`) and the namespace is stripped; abbreviations
  that git disambiguates (`heads/topic` next to a tag `topic`) never leak
  into pushes or URLs.
- **The default branch** is `refs/remotes/REMOTE/HEAD` when it points at a
  branch that still exists, else gh's answer, else `main`.
- **Where a branch pushes** (`hub::push_target`) follows git's own rules:
  `remote.*.push` refspecs, then `branch.*.pushRemote`, `remote.pushDefault`,
  `branch.*.remote` and `push.default`. When git would refuse, or would push
  other branches and leave this one alone (`remote.*.push` refspecs that map
  none of it, or map it to something other than a branch; `push.default
  nothing`; `simple` with a differently named upstream; no upstream), hub
  says why (`HUB_PUSH_WHY`) before pushing anywhere. Branch-aware commands
  (browse, compare, pull-request) use it, so a branch that tracks your fork
  is opened in, compared from and published to the fork.
- **A remote's fetch URL and push URL** may name different repositories. The
  remote-tracking branches come from the fetch URL, so they show nothing
  about the repository the remote pushes to: `compare` and `pull-request`
  (without `-p` or `-f`) refuse to read them as evidence that a branch is
  pushed there, and ask for the head by name instead.
- **Owner and repository names** compare without regard to case, as on
  GitHub, and keep their spelling in output.
- **hub's own fetches write one ref.** `merge` and `cherry-pick` fetch a pull
  request into a private ref of the run with `--refmap=`, so the remote's
  configured refspecs (a `+refs/pull/*/head:refs/heads/pull-*` mapping, say)
  update nothing on the side.
- **The default branch is known or unknown, never assumed** where something
  changes: `hub::default_branch` reads `refs/remotes/REMOTE/HEAD`, else asks
  gh, else fails. `pull-request` then requires `-b`, and `sync` leaves a
  branch deleted upstream alone; `compare` and `browse`, which only build a
  URL, assume `main`.
- **Clone URLs** use `git config hub.protocol`, else gh's `git_protocol`, else
  https. On GHE.com hosts the SSH user is the tenant, whether or not `GH_HOST`
  carries a port.

## Testing

- The suite is [bats](https://github.com/bats-core/bats-core); `make check`
  runs shellcheck, shfmt and `bats --recursive test`. CI runs it on Ubuntu
  and macOS.
- **Tests assert effects, not printed commands, wherever the effect is
  local.** Fixture repositories are made with real git (`make_repo`,
  `set_remote_head`); `serve_github [HOST/]OWNER/REPO...` creates bare
  repositories that stand in for github.com. git reaches them through two
  stubs, `test/stubs/ssh` (first in PATH; `-G` queries go to the real ssh) and
  `test/stubs/git-remote-https` (shadowing git's helper through
  `GIT_EXEC_PATH`), so remotes keep the URLs a user would have, with no URL
  rewriting that `git remote get-url` would show hub, and clone, fetch, push,
  remote and sync tests look at the resulting refs, configuration and work
  tree. `--noop` output is compared only for what cannot happen locally
  (browser URLs, gh invocations).
- `test/test_helper.bash` gives each test an empty HOME, git configuration
  and gh configuration directory, clears every `GIT_*`, `GH_*`, `GITHUB_*` and
  `HUB_*` setting inherited from the caller (a developer's `GIT_DIR` must not
  make the fixtures touch their repository), and puts `test/stubs/gh` first
  in PATH. The stub logs every call and replays responses registered with
  `stub_gh 'ARGS GLOB' 'STDOUT' [EXIT]`; an unexpected call exits 97.
  `config get user -h github.com` answers `mislav` by default.
- Race tests slip another process between two of hub's git commands with
  `shim_git 'ARGS GLOB' COMMAND`, a git that runs COMMAND once, right before
  the first call matching the glob. `script/release`'s repository check runs
  the same way as everything else, from a copy of the script in a scratch
  repository.
- Every finding that was ever reproduced against hub becomes a regression
  test that reproduces it the same way.
- No test uses the network.

## Adding a command

1. Choose `lib/hub/cmd/NAME.sh` (new command) or `lib/hub/ext/NAME.sh` (a git
   command hub extends), and which of the three kinds it is.
2. Write the header: `# shellcheck shell=bash`, `# Summary:`, `# Usage:`,
   description, options, examples.
3. Define `hub_cmd_NAME` (or `hub_ext_NAME`): parse the arguments as its kind
   prescribes, call `hub::usage` for `--help`, and do the work with the
   `hub::*` helpers.
4. Add `test/cmd/NAME.bats` (`load ../test_helper`), asserting effects.
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
work) and add hub's own commands without replacing what the user configured.

## Non-goals and accepted limitations

- No `--format`/`-f` placeholder templates; use gh's `--json`, `--jq` and
  `--template`.
- No authentication, token storage, configuration file or API client of its
  own; that is all gh (`gh auth login`, `gh auth refresh -s delete_repo`).
- Not installed as `git` and not a replacement for git in scripts: it is an
  interactive-shell alias.
- No reproduction of old hub's output formats, prompts or quirks, and no
  translation of old hub's option letters for the commands gh also has.
- hub finds operands by reading the installed git's option table, so an
  option it has never heard of is read as git reads it, abbreviations
  included; two options git lists otherwise than it reads them (`merge
  --file`, which takes the next argument, and `remote add --mirror`, which
  takes only an attached value) are special-cased. A short option that git's
  usage (`git CMD -h`) does not list leaves the whole command line to git,
  before hub adds a remote or fetches anything. An option value that looks
  like a URL (`--pathspec-from-file=https://...`) is a value, never an
  operand. Outside a repository a command that needs one has no option table
  (nor, for a subcommand, a usage); hub then hands the command line to git,
  which fails the same way.
- `merge` treats a pull-request URL anywhere among its arguments as the
  request to merge, and takes no other revision with it.
- `sync` fetches with a fixed refspec (`--refmap=` and
  `+refs/heads/*:refs/remotes/REMOTE/*`), so the remote's configured refspecs,
  `fetch.prune` and `fetch.pruneTags` cannot make it write or delete local
  branches or tags; a branch is gone when the remote has no such head.
- `sync` assumes that nothing else rewrites branches or adds work trees
  while it runs. Each update is conditional on the commit sync saw and
  writes the ref it examined (`update-ref --no-deref`), so a branch that
  moved, or became a symbolic ref, meanwhile is not followed; but, as with
  `git fetch`, a work tree that checks a branch out between sync's look and
  its update is not detected.
- Remotes defined in `.git/remotes` and `.git/branches` are not seen by
  repository discovery; `git remote add` them.
- Everything gh does with a URL or `-R` argument, including which host it
  selects, is gh's behavior.

## Shared helpers

`lib/hub/core.sh` holds what more than one module needs: running git and gh
(`hub::git`, `hub::gh`, `hub::exec_git`, `hub::exec_gh`, the `_query`
variants, `hub::gh_line`), option parsing for hub-owned commands
(`hub::normalize_opts`), git's own option tables for the commands hub extends
(`hub::git_options`, `hub::git_short_options`, `hub::git_option`) and the
subcommand scan of gh-backed ones (`hub::gh_subcommand_args`),
repository and host resolution (`hub::main_project`, `hub::parse_project`,
`hub::remote_project`, `hub::remote_for_project`, `hub::project_or_dir`,
`hub::push_target`, `hub::default_branch`, `hub::current_branch`,
`hub::toplevel`, `hub::gh_hosts`, `hub::host`, `hub::same_host`), shorthand
rules (`hub::is_project_name`, `hub::local_source`, `hub::expand_project`),
identity and URLs (`hub::current_user`, `hub::git_url`,
`hub::parse_remote_url`, `hub::parse_github_url`, `hub::url_escape`,
`hub::url_segment`), and text (`hub::message`, `hub::split_message`). A module
keeps a helper private only while it is the sole user; when a second module
needs it, it moves here.
