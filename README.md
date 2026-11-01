# hub

hub brings back the GitHub commands of the classic
[hub](https://github.com/mislav/hub), with the official
[GitHub CLI](https://cli.github.com), gh, doing all the GitHub work. It is a
small bash program: with `alias git=hub`, `git clone rails/rails`, `git
pull-request` and `git sync` work as hub users remember, and every other git
command runs unchanged. hub uses gh's login, hosts and `git_protocol`
setting, and has no token or configuration of its own.

```sh
eval "$(hub alias -s)"                                # git now runs hub
git clone rails/rails                                 # => git clone https://github.com/rails/rails.git
git clone dotfiles                                    # => git clone https://github.com/LOGIN/dotfiles.git
git remote add jingweno                               # => git remote add jingweno https://github.com/jingweno/REPO.git
git fetch alice,bob                                   # adds the missing remotes, then fetches both
git push origin,staging                               # => git push origin HEAD, then git push staging HEAD
git checkout https://github.com/rails/rails/pull/42   # => gh pr checkout https://github.com/rails/rails/pull/42
git merge https://github.com/rails/rails/pull/42      # merges locally, with the merge button's message
git am https://github.com/rails/rails/pull/42         # applies the pull request's commits
git cherry-pick https://github.com/rails/rails/commit/a319d88
git sync                                              # fast-forwards branches, deletes merged ones
git pull-request -p -m 'Fix the bug'                  # pushes the branch, then gh pr create
git pr list                                           # => gh pr list
git browse -- issues                                  # opens https://github.com/OWNER/REPO/issues
git ci-status -v                                      # one line per check of HEAD
git status                                            # plain git
```

## Install

Requirements (macOS and Linux):

- bash 5 or newer (hub is tested with 5.3): every command in the tables below
  refuses an older bash, also without a shorthand or URL (`git push origin
  main`, `git checkout -b topic`). Other git commands reach git on any bash,
  macOS's bash 3.2 included. The formula runs hub with Homebrew's bash; after
  `make install` on macOS, put Homebrew's bash first on `PATH`.
- git 2.24 or newer: hub uses `git switch`, `--end-of-options` and
  for-each-ref's `%(upstream:remotename)`.
- gh 2.40 or newer, logged in with `gh auth login`: hub reads your login from
  gh and uses `gh pr create --fill-first`, `gh repo fork --fork-name` and
  `--json` with `--jq`, which older 2.x releases lack in part.

With Homebrew, from this repository's own tap:

```sh
brew tap brc-dd/hub https://github.com/brc-dd/hub
brew install brc-dd/hub/hub
```

The formula conflicts with Homebrew's own `hub`: `brew uninstall hub` first.

From a checkout, `make install` links `bin/hub` into `PREFIX/bin` (`PREFIX`
is `/usr/local` by default), and `make uninstall` removes the links. Write
the prefix with `$HOME`, as in `make install PREFIX="$HOME/.local"`: make
does not expand a `~`, and `make install` refuses one. The links point into
the checkout, so keep it.

Then add the alias to your shell's startup file, after the lines that set up
`PATH`, so that the shell finds hub:

```sh
eval "$(hub alias -s)"          # ~/.zshrc or ~/.bashrc
hub alias -s fish | source      # ~/.config/fish/config.fish
```

`hub alias` prints the line and the startup file for your shell. Scripts do
not read the alias and keep running plain git. Do not install hub as `git`:
hub refuses to run when the first `git` on `PATH` is hub itself.

Completions for bash, zsh and fish come with the formula. `make install`
links them into `PREFIX/etc/bash_completion.d`,
`PREFIX/share/zsh/site-functions` and `PREFIX/share/fish/vendor_completions.d`
when those directories exist. They add hub's commands to git's completion,
which bash needs to find through bash-completion or Homebrew's git.

## Commands

`hub help COMMAND` prints a command's manual. The git commands hub extends
take git's options and act only on GitHub shorthands and URLs. For them,
`git help NAME` under the alias prints hub's manual, and `git NAME --help`
prints git's:

| Command | What hub adds |
|---|---|
| `clone [-p] [OWNER/]REPO [DIR]` | Clones `OWNER/REPO`, or `REPO` of yours, from GitHub. |
| `remote add [-p] NAME [OWNER[/REPO]]` | Adds a remote by its GitHub name; `remote set-url` too. |
| `fetch USER[,USER...]` | Adds remotes for users' copies of the project, then fetches. |
| `push REMOTE1,REMOTE2[,...]` | Runs `git push` once per remote, stopping at a failure. |
| `checkout PULL-REQUEST-URL [BRANCH]` | Checks the pull request out with `gh pr checkout`. |
| `merge PULL-REQUEST-URL` | Merges the pull request locally, with GitHub's message. |
| `am URL`, `apply URL` | Applies a pull request, commit or comparison. |
| `cherry-pick COMMIT-URL` | Fetches the commit, then cherry-picks it. |

hub's own commands take only the options in their manuals. gh's commands
take gh's options; hub turns `show` into `view` and adds `list` when the
subcommand is missing:

| Command | What it does |
|---|---|
| `pull-request [-p] [-m MESSAGE] [-b BASE]` | Opens a pull request with `gh pr create`. |
| `sync [REMOTE]` | Fast-forwards local branches and deletes merged ones. |
| `browse [REPO] [SUBPAGE]` | Opens a repository page; `-u` prints the URL. |
| `compare [-b BASE] [RANGE]` | Opens a compare page for a branch or a range. |
| `create [--public] [NAME]` | Creates a private repository on GitHub and adds `origin`. |
| `fork [--org ORG]` | Forks the project and adds the fork as a remote. |
| `delete [-y] NAME` | Deletes a repository with `gh repo delete`. |
| `ci-status [-v] [COMMIT]` | Prints the combined CI verdict of a commit; the exit status follows it. |
| `alias`, `help`, `version` | Shell setup, manuals and versions. |
| `pr`, `issue`, `release`, `gist`, `api` | gh's commands of the same name. |

## Configuration

| Setting | Effect |
|---|---|
| `GH_HOST` | The default host, for shorthands; unset, it is the one host gh is logged in to, else github.com. |
| `GITHUB_HOST` | hub 2.x's name for `GH_HOST`, used when `GH_HOST` is not set. |
| `GH_REPO=[HOST/]OWNER/REPO` | The project, instead of the remotes `upstream`, `github`, `origin`, then the rest. |
| `GH_TOKEN`, or gh's other token variables | gh uses the token; hub asks GitHub whose it is instead of reading gh's stored login. |
| `gh config set git_protocol ssh` | ssh URLs for new clones and remotes; `-p` on `clone` and `remote` does it once. |
| `GH_BROWSER`, `BROWSER` | The browser for `browse`, `compare` and `-o`; else `open`, else `xdg-open`. |
| `hub --noop COMMAND` | Prints the git and gh commands that change something instead of running them. |

## How it works

git ignores an alias that hides one of its own commands, so a shell alias is
how hub sees `git clone`. When a command line is not one of its commands, hub
hands the command line to git untouched, without loading anything. For its
own commands, hub runs again through git, so git applies global options such
as `-C` and `-c`. When hub cannot tell what a command line means, it stops
with a message or hands the command line to git untouched. gh does everything
on GitHub.

## More

- [docs/compatibility.md](docs/compatibility.md): hub 2.x's commands and
  options, and what this hub does with each.
- [docs/design.md](docs/design.md): how hub works, and how to add a command.
- [docs/development.md](docs/development.md): tests, linting and releases.
- [CHANGELOG.md](CHANGELOG.md): the changes in each release.

Mislav Marohnić and the contributors of hub 2.x designed these commands; gh
does the work underneath. hub is MIT licensed; see [LICENSE](LICENSE).
