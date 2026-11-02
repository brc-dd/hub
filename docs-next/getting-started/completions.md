---
title: Shell completion
description: Complete hub's commands and options in bash, zsh and fish.
---

# Shell completion

This page is for people who use bash, zsh or fish and want the shell to
complete hub's commands and options when they press Tab. After you install one
file, `hub pu<Tab>` offers `pull`, `pull-request` and `push`, for `hub` and
for `git` when you [make git run hub](alias.md). If hub is not installed yet,
start with [Install hub](install.md). In the examples, `<Tab>` marks where you
press Tab, and `# =>` the candidates the shell offers.

## Install the completion files

hub ships one completion file each for bash, zsh and fish. Each file adds
hub's commands and the options of hub's own commands to git's completion.
Every other word comes from git's own completion. The Homebrew formula installs
all three files. In a clone of hub's repository, `make install` links each file
into its directory under `PREFIX` (`/usr/local` by default), but only when that
directory already exists. It prints one line per link:

```sh
make install PREFIX="$HOME/.local"
```

```text
ln -s HUB_DIR/bin/hub /home/USER/.local/bin/hub
ln -s HUB_DIR/completions/hub.fish /home/USER/.local/share/fish/vendor_completions.d/hub.fish
```

Here only the fish directory exists under `PREFIX`, so `make install` skips
the bash and zsh files. It creates the `bin` directory when it is missing.

| Shell | Homebrew and `make install` put it at | `make install` setting |
|---|---|---|
| bash | `PREFIX/etc/bash_completion.d/hub` | `BASH_COMPLETION_DIR` |
| zsh | `PREFIX/share/zsh/site-functions/_hub` | `ZSH_COMPLETION_DIR` |
| fish | `PREFIX/share/fish/vendor_completions.d/hub.fish` | `FISH_COMPLETION_DIR` |

Set the variable on the `make install` line to use another directory. If a file
at that place is not a link to hub's file, `make install` stops and prints
`make install: DEST exists and is not a link to SOURCE`. Remove or move that
file, then run `make install` again.

Known limits: of the gh commands (api, gist, issue, pr and release), hub
completes only the names. For their options, type the line as `gh pr ...` and
use the completion of the GitHub CLI (gh).

## Set up completion in bash

To install by hand, source the file from `~/.bashrc`. It runs on any bash,
including macOS's bash 3.2. The file needs git's `git-completion.bash`. It
finds that file through bash-completion or Homebrew's git. If neither provides
it, source `git-completion.bash` first. Add these lines to `~/.bashrc`:

```sh
. DIR/git-completion.bash
. HUB_DIR/completions/hub.bash
```

bash completes hub's command names in the command position. That position can
also come after git's global options, such as `-C DIR`, or after `--noop`. For
hub's own commands you get their long options, with a trailing `=` on an option
that takes a value:

```sh
hub pu<Tab>                          # => pull  pull-request  push
hub -C DIR pull-request --dr<Tab>    # => --draft
hub fork --<Tab>                     # => --no-remote  --remote-name=  --org=  --fork-name=  --default-branch-only
```

Plain git keeps git's own completion:

```sh
git ch<Tab>     # => checkout  cherry  cherry-pick
```

After `alias git=hub`, git also offers hub's commands:

```sh
git ci<Tab>     # => citool  ci-status
```

Known limits: bash shows no descriptions, and only the long form of an option
that has one. Without git's completion, bash completes hub's command names as
the first word and file names after it. If you registered your own git
completion with `complete -F`, hub keeps it for plain git. If you registered it
with `complete -W` or `complete -C`, hub does not touch it. Then git gets no hub
commands.

## Set up completion in zsh

To install by hand, link the file as `_hub` into a directory:

```sh
mkdir -p ~/.zfunc && ln -s HUB_DIR/completions/hub.zsh ~/.zfunc/_hub
```

Add the directory to `fpath` in `~/.zshrc`, before the line that runs
`compinit`:

```sh
fpath=(~/.zfunc $fpath)
```

To load the file without `fpath`, source it in `~/.zshrc` after the line that
runs `compinit`.

You get hub's commands with a one-line description each, and the short and long
options of hub's own commands. The file builds on the git completion you already
use, either zsh's `_git` or git's `git-completion.zsh`. It completes both `hub`
and `git`. If you set `setopt complete_aliases` and alias git to hub, `git`
still offers hub's commands.

```sh
hub browse -<Tab>                    # => -u  --url  -c  --copy
hub -C DIR pull-request --dra<Tab>   # => --draft
```

Known limits: zsh leaves the commands git has too (am, apply, checkout,
cherry-pick, clone, fetch, help, merge, push, remote, version) to git's own
completion. So zsh does not offer `hub version --build-options`.

## Set up completion in fish

To install by hand, link the file as `hub.fish` into a `vendor_completions.d`
directory that fish reads:

```sh
mkdir -p ~/.local/share/fish/vendor_completions.d
ln -s HUB_DIR/completions/hub.fish ~/.local/share/fish/vendor_completions.d/hub.fish
```

The file tells fish that `hub` wraps `git`. You get git's completion, hub's
commands with descriptions, and the short and long options of hub's own
commands.

```sh
hub ci-<Tab>             # => ci-status  (Show the CI status of a commit)
hub compare -<Tab>       # => -b  --base  -u  --url  -c  --copy
```

To give `git` the same completion, make git run hub. This line makes `git` a
fish function that runs hub:

```sh
hub alias -s fish | source
```

## Check that completion works

Open a new terminal, so that the shell reads its startup file and the new
completion file. Then type a hub command and press Tab:

```sh
hub pull-<Tab>          # => pull-request
hub browse --<Tab>      # => --url  --copy
```

If Tab offers none of hub's commands, check that the file is in the directory
of the table above, or that your shell's startup file sources it.

## Differences from the original hub

Completion of hub's commands for `hub`, and for `git` after the alias, is the
same as in the original hub (mislav/hub 2.x). The rest changed:

| Original hub | This hub |
|---|---|
| bash: you source `hub.bash_completion` from `~/.bashrc` on Linux or `~/.bash_profile` on macOS. | bash: you source `hub.bash` from `~/.bashrc`. |
| bash offers the short options of `pull-request`, such as `-F -b -f -h`. | bash offers only the long form of an option that has one. |
| zsh: you copy `hub.zsh_completion` to `~/.zsh/completions/_hub` and add that directory to `fpath`. | zsh: you link `hub.zsh` as `_hub` into any directory on `fpath`, or source it after `compinit`. |
| fish: you copy `hub.fish_completion` to `~/.config/fish/completions/hub.fish`. | fish: you link `hub.fish` into a `vendor_completions.d` directory. |

See the original hub's
[completion instructions](https://github.com/mislav/hub/blob/master/etc/README.md).

## See also

- [Install hub](install.md): the Homebrew formula and `make install`, which
  install the completion files.
- [Make git run hub](alias.md): the alias that gives `git` hub's completion.
- [Working on hub](../developers/development.md): how the completion files
  are tested.
