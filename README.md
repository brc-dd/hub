# hub

**git + GitHub, powered by gh.** A minimal re-implementation of the classic
[`hub`](https://github.com/mislav/hub) git wrapper in bash 5, with every GitHub
operation delegated to the official [GitHub CLI](https://cli.github.com) (`gh`).

```sh
eval "$(hub alias -s)"          # git is now hub; hub is still git

git clone rails/rails           # => git clone https://github.com/rails/rails.git
git remote add mislav           # => git remote add mislav https://github.com/mislav/<repo>.git
git fetch mislav,rtomayko       # adds missing remotes, then fetches them
git push origin,staging topic   # one push per remote
git checkout https://github.com/org/repo/pull/123   # => gh pr checkout
git merge    https://github.com/org/repo/pull/123   # merges locally, merge-button message
git am       https://github.com/org/repo/pull/123   # applies the PR as commits
git cherry-pick https://github.com/org/repo/commit/abc123
git sync                        # fast-forward every branch, prune the merged ones
git pull-request -m "Title" -p  # push, then gh pr create
git pr list                     # gh pr list
git browse -- issues            # open the issues page
git ci-status -v                # CI state of HEAD, one line per check
git status                      # plain git, untouched, no network
```

## How it works

`hub` is a wrapper *program*, not a git alias. git ignores aliases that shadow
built-in commands, so `git clone owner/repo` can never be taught through
`git config alias.clone`. A shell alias is different: `alias git=hub` makes the
word `git` run a different program, exactly as the original hub did.

The dispatcher in `bin/hub` recognises two kinds of command words:

- **extended git commands** (`clone`, `remote`, `fetch`, `push`, `checkout`,
  `merge`, `am`, `apply`, `cherry-pick`, `sync`): the arguments are rewritten
  (a GitHub shorthand or URL is expanded) and the real `git` is `exec`'d;
- **new commands** (`pull-request`, `pr`, `issue`, `release`, `browse`,
  `compare`, `create`, `fork`, `delete`, `ci-status`, `api`, `gist`, `alias`,
  `help`, `version`): implemented on top of `gh`.

Anything else is `exec`'d as `git` immediately, with nothing loaded and no
network access. `hub --noop <command>` prints the git and gh commands that would
run instead of running them.

## Requirements

- bash 5 or newer. macOS ships bash 3.2, so `brew install bash` (the Homebrew
  formula takes care of this).
- git.
- `gh` 2.x, logged in (`gh auth login`). hub has no authentication of its own.
- macOS or Linux.

## Install

### Homebrew

This repository is also a Homebrew tap:

```sh
brew tap brc-dd/hub https://github.com/brc-dd/hub
brew install brc-dd/hub/hub          # add --HEAD until the first tagged release
```

If the old Go `hub` is installed, remove it first (`brew uninstall hub`); both
install a `hub` executable.

### From a checkout

```sh
git clone https://github.com/brc-dd/hub.git
cd hub
make install PREFIX=~/.local          # symlinks bin/hub and installs completions
```

`bin/hub` finds its library through its own path, so a symlink from anywhere on
`PATH` into the checkout works, as does copying `bin/`, `lib/` and `VERSION`
together.

### Shell setup

Add to `~/.zshrc`, `~/.bashrc` or `~/.config/fish/config.fish`:

```sh
eval "$(hub alias -s)"
```

`hub alias` with no `-s` prints the instructions for your shell. Completion
files for zsh, bash and fish are in `completions/`; Homebrew and `make install`
put them in place, and with `git` aliased to hub, git's own completion keeps
working and gains hub's commands.

Never install the wrapper under the name `git` itself. The alias only exists in
interactive shells, so scripts keep calling plain git.

## What is implemented

The yardstick is the last Go hub, 2.14.2. The intent is to cover the commands
people actually typed, not to reproduce its output formats or every flag.

Two rules decide what the flags mean:

1. **Commands that only hub has** (`pull-request`, `browse`, `compare`,
   `create`, `fork`, `delete`, `ci-status`, `sync`, `alias`, and the extended
   git commands) use **hub's flags**, translated to gh or git.
2. **Commands gh also has** (`pr`, `issue`, `release`, `api`, `gist`) use
   **gh's flags and output**. hub only maps the old subcommand names and
   argument shapes gh lacks, then hands over to gh unchanged.

### Extended git commands

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub clone [-p] [OWNER/]REPO [DIR]` | **Yes** | `git clone owner/repo`, `git clone repo` (your own), `repo.wiki`, `HOST/OWNER/REPO`; every git clone flag is kept in place | No API lookup. No `upstream` remote for forks (use `gh repo clone` for that). |
| `hub remote add [-p] [NAME] USER[/REPO]`, `hub remote set-url …` | **Yes** | A bare `USER` means `USER/<current repo>` | The "origin means my fork" special case is gone. |
| `hub fetch USER[,USER2…]` | **Yes** | Adds missing remotes, then `git fetch --multiple` | No existence check: git reports a missing fork. |
| `hub push REMOTE1,REMOTE2 [REF]` | **Yes** | One `git push` per remote, stops at the first failure; options are kept | |
| `hub checkout PR-URL [BRANCH]` | **Yes** | `gh pr checkout URL [-b BRANCH]` | `-f` is refused: gh's `--force` resets the local branch. |
| `hub merge PR-URL` | **Yes** | Fetches `refs/pull/N/head` and merges **locally** with the merge-button message | Never `gh pr merge`, which merges on GitHub. |
| `hub am URL`, `hub apply URL` | **Yes** | PR URLs through `gh pr diff --patch`, commit URLs through the API's patch/diff; local files and options untouched | Gist URLs are not supported. |
| `hub cherry-pick COMMIT-URL`, `USER@SHA` | **Yes** | Fetches the commit (or `refs/pull/N/head`) and cherry-picks it | |
| `hub sync [REMOTE]` | **Yes** | Pure git: fetch `--prune`, fast-forward branches that are behind, delete merged branches whose upstream is gone, warn about the rest | `--color` dropped. |
| `hub init -g` | No | `git init && gh repo create --source=. --private` | |
| `hub submodule add OWNER/REPO DIR` | No | `git submodule add "$(gh repo view OWNER/REPO --json url -q .url).git" DIR` | |

### New commands

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub pull-request` | **Yes**, hub flags | `gh pr create`; `-m` (repeatable) and `-F FILE` split title and body, `-e`, `-b BASE`, `-h HEAD`, `-p` pushes first, `-f`, `-d`, `-r`, `-a`, `-M`, `-l`, `--no-maintainer-edits`, `-o` opens, `-c` copies, `-i ISSUE` or an issue URL converts the issue; other flags go to gh | Milestones by number and auto-created labels are not supported. |
| `hub pr list \| checkout \| show \| merge` | **Yes**, gh flags | `show` → `gh pr view` (`-u` prints the URL), `checkout N BRANCH` → `-b BRANCH`, everything else → `gh pr …` | `merge` merges on GitHub, as gh does. |
| `hub issue …` | **Yes**, gh flags | bare → `list`; `show` → `view`; `update` → `edit`, with `-s closed\|open` → `close`/`reopen`; `labels` → `gh label list`; `create -m`/`-F` split title and body | `--include-pulls`, sorting flags and `-f` formats are gone; use gh's `--search`, `--json`, `--jq`. |
| `hub release …` | **Yes**, gh flags | bare → `list`; `show` → `view`; `create -a FILE[#label]` become asset arguments, `-m`/`-F` split title and notes, `-t REF` → `--target`; `edit -a` → `gh release upload --clobber`; `download -i GLOB` → `-p GLOB` | `-e`, `-o`, `-c` and `-f` formats are gone. |
| `hub browse [-u] [-c] [[OWNER/]REPO] [SUBPAGE]` | **Yes** | URL built locally, no API call; a checked-out non-default branch opens `tree/BRANCH` | |
| `hub compare [-u] [-c] [-b BASE] [OWNER] [RANGE]` | **Yes** | `A..B` becomes `A...B` | |
| `hub create [-p] [-d DESC] [-h URL] [[ORG/]NAME]` | **Yes**, hub flags | `gh repo create --source=.`; **private by default**, `--public` to publish, `--internal` for organisations, `--remote-name`, `-o` | hub 2.x created public repositories by default. |
| `hub fork [--no-remote] [--remote-name NAME] [--org ORG]` | **Yes** | `gh repo fork --remote --remote-name <your login>` then fetches it | The remote is named after you, as in hub 2.x; plain `gh repo fork` would rename `origin` to `upstream`. |
| `hub delete [-y] [OWNER/]NAME` | **Yes** | `gh repo delete [--yes]` | Needs the `delete_repo` scope: `gh auth refresh -s delete_repo`. |
| `hub ci-status [-v] [COMMIT]` | **Yes** | Combines commit statuses and check runs through `gh api`; prints one word; exit 0 success, 1 failure, 2 pending, 3 no status | `-f FORMAT` and `--color` are gone. `gh pr checks` is the richer view for a PR. |
| `hub api …` | **Yes**, gh flags | `gh api`; `-t/--flat` is dropped with a warning (gh's `-t` is `--template`), `--cache N` gains the missing unit | Use `--jq` or `--template` for shell-friendly output. |
| `hub gist create \| show` | **Yes**, gh flags | `--public` → `-p`, `-o` → `-w`; `show ID [FILE]` → `gh gist view --raw` | `-c` is gone. |
| `hub alias [-s] [SHELL]` | **Yes** | bash, zsh, sh, ksh, dash, fish, csh, tcsh | |
| `hub help [COMMAND]`, `hub version`, `hub --noop` | **Yes** | Each module's header is its manual | |
| `-f FORMAT` placeholders (`%I`, `%t`, …) | No | gh's `--json FIELDS --jq EXPR` or `--template` | |
| `hub.protocol`, `hub.host`, `GITHUB_HOST` | **Yes** | Also gh's `git_protocol`, `GH_HOST`, and `GH_REPO` to target another repository | |
| hub's own login and `GITHUB_TOKEN` handling | No, by design | `gh auth login`, `GH_TOKEN` | |

## Configuration

| Setting | Effect |
|---|---|
| `git config --global hub.protocol ssh` | Clone and remote URLs use `git@host:` instead of HTTPS. Without it, gh's `git_protocol` setting is used. |
| `git config --global --add hub.host my.ghe.example` | Treat an Enterprise host's remotes and URLs as GitHub. gh must be logged in to that host. |
| `GH_HOST`, `GITHUB_HOST` | The default host for shorthands such as `owner/repo`. |
| `GH_REPO=[HOST/]OWNER/REPO` | Act on another repository than the one the remotes point at. |
| `HUB_VERBOSE=1` | Log every git and gh command on stderr. |
| `hub --noop …` | Print the commands that would run instead of running them. |

Which remote is "the" repository: `upstream`, then `github`, then `origin`,
then any other GitHub remote, the same order hub 2.x used.

## Development

```sh
make check        # shellcheck + the bats suite
make test         # bats --recursive test
make lint         # shellcheck
make fmt          # shfmt -w (settings live in .editorconfig)
```

Layout:

```
bin/hub              dispatcher: option parsing, fast path, module loading
lib/hub/core.sh      shared helpers (hub::git, hub::gh, repo and URL detection, …)
lib/hub/ext/*.sh     extended git commands (one file per command)
lib/hub/cmd/*.sh     new commands built on gh
completions/         zsh, bash and fish completion
test/                bats tests; test/stubs/gh replaces gh, --noop captures git
Formula/hub.rb       Homebrew formula (this repo is a tap)
script/              bump, release, update-formula
```

Adding a command is one file: `lib/hub/cmd/<name>.sh` (or `ext/`) defining
`hub_cmd_<name>` (or `hub_ext_<name>`), with a comment-block header that becomes
its `hub help <name>` manual, plus `test/cmd/<name>.bats`. Side effects go
through `hub::git`, `hub::gh`, `hub::exec_git` and `hub::exec_gh` so that
`--noop` keeps working; read-only lookups use `hub::git_query` and
`hub::gh_query`.

Releases: `script/release X.Y.Z` runs the checks, bumps `VERSION` and
`CHANGELOG.md`, tags, pushes, creates the GitHub release and updates the
Homebrew formula's URL and checksum. See `script/bump`, `script/release` and
`script/update-formula` for the individual steps.

## Credits

hub 2.x by Mislav Marohnić and contributors defined the commands this project
re-implements. The GitHub CLI does the heavy lifting underneath.
