# hub

**git + GitHub, powered by gh.** A small bash wrapper around git that adds the
GitHub commands of the classic [`hub`](https://github.com/mislav/hub), with all
GitHub work done by the official [GitHub CLI](https://cli.github.com) (`gh`).

```sh
eval "$(hub alias -s)"          # git is now hub; everything git did still works

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

hub only acts on its own commands and on GitHub shorthands and URLs; every
other git command runs unchanged, without loading anything or touching the
network. `hub --noop <command>` shows what would run.

## Install

Requirements, each with the reason for its floor (macOS and Linux):

- **bash 5.3 or newer**: the version hub is developed and tested with; `bin/hub`
  refuses to run on bash 4 and older. macOS ships 3.2; the Homebrew formula
  brings its own.
- **git 2.41 or newer**: hub relies on `%(push:remoteref)` in for-each-ref,
  `--end-of-options`, `git switch` and `--config-env`.
- **gh 2.40 or newer**, logged in (`gh auth login`): hub uses `gh repo create
  --source --remote --push`, `gh repo fork --remote --remote-name`, `gh pr
  create --head/--fill-first`, `gh pr checkout -b/--detach`, `--json` output and
  `gh api -F/--jq`, which older 2.x releases lack in part.

```sh
brew tap brc-dd/hub https://github.com/brc-dd/hub
brew install brc-dd/hub/hub
```

Or from a checkout: `make install PREFIX="$HOME/.local"` symlinks `bin/hub` and
the completions into the prefix (write it with `$HOME`, not `~`: zsh and sh
pass a `~` inside a `PREFIX=` argument on literally, and make does not expand
it). Then add to `~/.zshrc`, `~/.bashrc` or `~/.config/fish/config.fish`, after
the lines that set up your `PATH` (Homebrew's, for instance):

```sh
eval "$(hub alias -s)"
```

`hub alias` with no `-s` prints the instructions for your shell. Completion for
zsh, bash and fish comes with the install, and `git <TAB>` keeps working with
hub's commands added. Do not install the wrapper under the name `git`; the alias
only exists in interactive shells, so scripts keep calling plain git.

## Commands

Extended git commands, triggered by a GitHub shorthand or URL:

| Command | What hub adds |
|---|---|
| `clone [-p] [OWNER/]REPO [DIR]` | expands `owner/repo`, `repo` (yours) and `repo.wiki` to a clone URL; existing paths stay git's |
| `remote add [-p] [NAME] USER[/REPO]`, `remote set-url` | adds a remote by GitHub name; `remote add origin` alone means your fork |
| `fetch USER[,USER2…]` | adds missing remotes for those users' forks, then fetches |
| `push REMOTE1,REMOTE2 [ARGS…]` | one `git push` per remote, stops at the first failure |
| `checkout PR-URL [BRANCH]` | `gh pr checkout` |
| `merge PR-URL` | merges the PR locally with GitHub's merge-button message (never merges on GitHub) |
| `am URL`, `apply URL` | fetches a PR, commit or compare URL (also `.patch`/`.diff`) as a patch and applies it |
| `cherry-pick COMMIT-URL`, `USER@SHA` | fetches the commit, then cherry-picks it |
| `sync [--color] [REMOTE]` | fast-forwards branches that are behind, deletes merged ones, warns about the rest; never touches a branch that moved meanwhile |

New commands:

| Command | What it does |
|---|---|
| `pull-request [-m MSG] [-b BASE] [-h HEAD] [-p] [-d] …` | `gh pr create` with hub's flags; `-p` pushes first, `-i ISSUE` converts an issue |
| `pr`, `issue`, `release`, `api`, `gist` | `gh` with the same name and flags; hub maps only the old subcommand names: `show` → `view`, none → `list` |
| `browse [-u] [REPO] [SUBPAGE]`, `compare [-u] [-b BASE] [RANGE]` | open repository pages; `-u` prints the URL |
| `create [-p] [-d DESC] [NAME]`, `fork`, `delete NAME` | `gh repo create --source=TOP` (private by default), `gh repo fork --remote` with a remote named after you, delete |
| `ci-status [-v] [COMMIT]` | one word for a commit's CI state; exit 0 success, 1 failure, 2 pending, 3 no status |
| `alias [-s] [SHELL]`, `help [COMMAND]`, `version` | shell setup, manuals, versions |

`hub help <command>` prints each command's manual. Commands that gh also has use
gh's flags and output; commands only hub has use hub's flags.

## Configuration

| Setting | Effect |
|---|---|
| `HUB_PROTOCOL=ssh`, `git config --global hub.protocol ssh` | SSH instead of HTTPS for new clone and remote URLs; otherwise gh's `git_protocol` applies |
| `GH_HOST`, `GITHUB_HOST` | the default host for shorthands such as `owner/repo`; hosts gh is logged in to are recognized automatically, `git config --add hub.host HOST` adds others |
| `GH_REPO=[HOST/]OWNER/REPO` | act on another repository than the one the remotes point at |
| `GH_BROWSER`, `BROWSER` | the browser for `browse`, `compare` and `-o` |
| `hub --noop …` | print the git and gh commands instead of running them |
| `HUB_VERBOSE=1` | log every git and gh command on stderr |

Which remote is "the" repository: `upstream`, then `github`, then `origin`,
then any other GitHub remote. Authentication is gh's; `gh auth login` once per host.

**SSH aliases and certificates.** A remote whose host is an alias from
`~/.ssh/config` (`git@gh-work:org/repo.git`, `ssh://gh-work/org/repo.git`) is a
GitHub remote for hub when the alias resolves to a GitHub host: hub asks the ssh
git would use (`ssh -G`, with the URL's user and port, so `Match` rules apply).
The alias has to resolve; one whose `HostName` is missing or points elsewhere
makes the remote an ordinary git remote that hub leaves alone. Shorthands such as
`owner/repo` always expand to `git@HOST:owner/repo.git` (with `hub.protocol
ssh`). An organization that requires SSH certificates needs its
repository-specific URL instead, shown under the repository's Code → SSH menu
(it carries the organization ID): clone or `git remote add` with that URL as
given, or point an alias at it (`HostName github.com` and that URL's `User`) and
use the alias in the URL. hub never rewrites a full URL, and recognizes the
remote either way.

## More

- [docs/compatibility.md](docs/compatibility.md): command by command, what hub 2.x did and what this hub does instead.
- [docs/design.md](docs/design.md): how the wrapper works and how to add a command.
- [docs/development.md](docs/development.md): tests, linting, releases.
- [CHANGELOG.md](CHANGELOG.md).

hub 2.x by Mislav Marohnić and contributors defined these commands; the GitHub
CLI does the work underneath. MIT licensed, see [LICENSE](LICENSE).
