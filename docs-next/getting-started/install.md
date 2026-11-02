---
title: Install hub
description: Install hub, log gh in to GitHub, and upgrade or uninstall hub.
---

# Install hub

This page is for anyone who wants to install hub on macOS or Linux and log the
GitHub CLI (gh) in to GitHub. After it, `hub version` runs, and hub's commands
reach GitHub through gh. Next, [make git run hub](alias.md).

## Check the requirements

| Program | Version | Why this version |
|---|---|---|
| bash | 5 or newer (tested with 5.3) | hub's commands use bash 5 features and refuse an older bash. If you [make git run hub](alias.md), a git command that hub extends, such as `git push`, also needs bash 5. Other git commands run on any bash, including macOS's bash 3.2. |
| git | 2.30 or newer | hub uses `git switch`, `--end-of-options` (also with `git rev-parse`), for-each-ref's `%(upstream:remotename)` and, in `cherry-pick`, `git fetch --no-write-fetch-head`. |
| gh | 2.55 or newer, logged in | hub reads your login from gh and uses `gh pr create --fill-first` and `--editor`, and `--json` with `--jq`. |

Check the versions you have:

```sh
bash --version | head -n 1
git --version
gh --version | head -n 1
```

With an older bash, hub's commands stop with exit status 1:

```text
hub: bash 5 or newer is required for hub's commands (this is bash 3.2.57(1)-release; on macOS: brew install bash)
```

## Install with Homebrew

The hub repository is its own Homebrew tap. Its formula conflicts with
Homebrew's own `hub` formula, which installs the original hub (mislav/hub
2.x). Both formulas install a `hub` command. If you installed Homebrew's `hub`
formula, uninstall it first:

```sh
brew uninstall hub
```

Add the tap, then install the formula by its full name:

```sh
brew tap brc-dd/hub https://github.com/brc-dd/hub
brew install brc-dd/hub/hub
```

The formula installs Homebrew's bash and gh, runs hub with that bash, and
installs the completions for bash, zsh and fish. After the install, Homebrew
prints the alias lines for each shell:

```text
To make git run hub, add the line for your shell to its startup file:
  ~/.zshrc:                     eval "$(hub alias -s zsh)"
  ~/.bashrc:                    eval "$(hub alias -s bash)"
  ~/.config/fish/config.fish:   hub alias -s fish | source
```

## Install from a clone

On macOS, `/bin/bash` is bash 3.2. hub runs with the first `bash` on `PATH`.
Install Homebrew's bash first:

```sh
brew install bash
command -v bash    # must print Homebrew's bash, such as /opt/homebrew/bin/bash
```

If `command -v bash` prints `/bin/bash`, put Homebrew's `bin` directory first
on `PATH` in your shell's startup file.

`make install` links `bin/hub` into `PREFIX/bin`. `PREFIX` is `/usr/local` by
default. The links point into the clone. Do not move or delete the clone.

```sh
git clone https://github.com/brc-dd/hub.git
cd hub
make install                          # links into /usr/local/bin
```

To link into your home directory instead, set `PREFIX`:

```sh
make install PREFIX="$HOME/.local"    # links into ~/.local/bin
```

Write the prefix with `$HOME`, not `~`. make does not expand a `~`, and
`make install` refuses one:

```text
make: ~/.local/bin starts with a literal ~; write PREFIX="$HOME/..."
```

`make install` creates the `bin` directory when it is missing, prints an `ln -s`
line for each link, and stops if a destination exists and is not a link into
this clone. The links made before the refusal stay in place. It also links the
completion files. See
[Shell completion](completions.md#install-the-completion-files).

To stage the links under another root, as a package build does, set
`DESTDIR`. To change one directory, set `BINDIR`, `BASH_COMPLETION_DIR`,
`ZSH_COMPLETION_DIR` or `FISH_COMPLETION_DIR`.

```sh
make install DESTDIR=/tmp/stage    # links into /tmp/stage/usr/local/bin
make install BINDIR="$HOME/bin"    # links the command into ~/bin
```

## Log in to GitHub

hub uses gh's login, hosts and `git_protocol` setting. Log gh in once:

```sh
gh auth login                         # github.com
gh auth login -h ghe.example.com      # a GitHub Enterprise host
gh auth status                        # shows the accounts gh is logged in to
```

To use a token instead, set `GH_TOKEN` or `GITHUB_TOKEN` for github.com and
GitHub Enterprise Cloud (`*.ghe.com`). For a GitHub Enterprise Server host, set
`GH_ENTERPRISE_TOKEN` or `GITHUB_ENTERPRISE_TOKEN`. gh then uses the token, and
hub asks GitHub whose token it is instead of reading gh's stored login.

```sh
export GH_TOKEN=TOKEN
```

If hub cannot find your login, it stops with this message:

```text
hub COMMAND: could not determine your GitHub login for HOST (run: gh auth login -h HOST)
```

More on hosts and tokens is in [Hosts and login](../guide/hosts-and-login.md).

## Check the install

`hub version` prints hub's version, then git's, then the first line of gh's.
Without gh, it prints the first two lines only.

```sh
hub version
```

```text
hub 0.3.0 (brc-dd/hub)
git version 2.54.0
gh version 2.103.3 (2026-10-26)
```

`hub help` prints git's help, then lists hub's own commands, the git commands
hub extends and the gh commands. `hub help COMMAND` prints one command's
manual. The same manuals are on the
[manuals website](https://brc-dd.github.io/hub/).

```sh
hub help
hub help pull-request
```

## Upgrade and uninstall

With Homebrew, upgrade or remove the formula by its full name:

```sh
brew upgrade brc-dd/hub/hub
brew uninstall brc-dd/hub/hub
brew untap brc-dd/hub
```

In the clone, `git pull` upgrades hub, because the links point into the clone.
`make uninstall` removes the links for the command and each completion. It
removes only links that point into this clone, and it prints an `rm` line for
each one. Pass the same `PREFIX` and `DESTDIR` you installed with.

```sh
git pull
make uninstall PREFIX="$HOME/.local"
```

If you added the `hub alias` line to your shell's startup file, remove it. See
[Make git run hub](alias.md).

## See also

- [Make git run hub](alias.md): the line that makes git run hub, per shell.
- [Shell completion](completions.md): completion of hub's commands in bash, zsh
  and fish.
- [First steps with hub](first-steps.md): a tour of hub's commands, from clone
  to a merged pull request.
- [Hosts and login](../guide/hosts-and-login.md): GitHub Enterprise hosts,
  tokens and how hub finds your login.
- [hub version](../commands/version.md): the version lines and what each one
  shows.
- [hub help](../commands/help.md): the command list and the manual of each
  command.
- [hub manuals](https://brc-dd.github.io/hub/): every command's manual on the
  web.
