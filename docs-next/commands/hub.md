---
title: hub
description: Run git, with the GitHub commands of hub on top of the GitHub CLI.
kind: hub's own command
original: https://hub.github.com/hub.1.html
---

# hub

`hub` runs git, and adds GitHub commands that the GitHub CLI (gh) carries out.
hub reads the first word after its options, the command word. If that word
names a hub command, hub runs the command, and otherwise the whole command line
goes to git unchanged. Use it to make `git clone rails/rails` or
`git pull-request` work. The most common use is `hub clone rails/rails`, which
clones a GitHub repository by its short name.

```sh
hub clone rails/rails
# => git clone https://github.com/rails/rails.git
```

## Usage

```text
hub [--noop] [GIT-OPTIONS...] COMMAND [ARGS...]
```

`GIT-OPTIONS` are git's global options, such as `-C DIR`, `-c NAME=VALUE`,
`--git-dir=DIR` and `--no-pager`. `COMMAND` is a hub command, a git command or
a git alias. A git alias runs as plain git. `ARGS` are the command's arguments.
The [command index](README.md) lists hub's commands.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md), write
`git` in place of `hub`: the command is the same. Each `# =>` line is what
`hub --noop` prints: the git or gh command that hub runs. The examples run in a
clone whose `origin` is `https://github.com/OWNER/REPO.git`, and `LOGIN`
stands for your GitHub login.

Run a git command that hub does not handle:

```sh
hub status -sb
# runs: git status -sb
```

It runs as plain git, with git's output and exit status.

Pass git's global options before the command word:

```sh
hub --noop -c core.pager=cat log --oneline
# => git -c core.pager=cat log --oneline
```

Open the issues page of the current repository in the web browser:

```sh
hub --noop browse -- issues
# => open https://github.com/OWNER/REPO/issues
```

With `--` in place of a repository, browse reads the current repository's
remotes. `--noop` prints `open URL` in place of opening the browser.

Run a hub command in another repository with `-C`, as you would with git:

```sh
hub --noop -C repo browse -- pulls
# => open https://github.com/OWNER/REPO/pulls
```

This runs from the parent directory of `repo`, a clone whose `origin` is the
same repository.

Clone a repository by its `OWNER/REPO` shorthand:

```sh
hub --noop clone rails/rails
# => git clone https://github.com/rails/rails.git
```

A git command that hub extends turns the shorthand into a URL, here with gh's
`git_protocol` setting at its default, `https`. See
[repositories and URLs](../guide/repositories-and-urls.md).

Run a gh command:

```sh
hub --noop pr
# => gh pr list
hub --noop issue show 1
# => gh issue view 1
```

For gist, issue, pr and release, hub turns `show` into `view`, and adds `list`
when no subcommand is given. api hands every argument to `gh api` unchanged.

Preview a command that writes to GitHub:

```sh
hub --noop fork
# => gh api --hostname github.com --method POST repos/OWNER/REPO/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/REPO.git
```

`--noop` prints the commands that change something on GitHub or in the
repository. Read-only lookups still run.

Print a plain git command line with `--noop`, which can stand anywhere before
the command word:

```sh
hub -C . --noop tag v1
# => git -C . tag v1
hub --noop tag 'two words' '*' '' -m "it's"
# => git tag two\ words \* '' -m it\'s
```

`--noop` prints the command line with its global options, quoted so that you
can paste it back.

Print the versions of hub, git and gh:

```sh
hub version
```

```text
hub 0.3.0 (brc-dd/hub)
git version 2.54.0 (Apple Git-157)
gh version 2.103.3 (2026-10-26)
```

`hub --version` and `hub -v` do the same.

Print git's help and then the list of hub's commands, each with its summary,
or name a command to read its manual:

```sh
hub help
hub help pull-request
```

`hub --help` and `hub -h` print the list too.

Run `git help` with its own options:

```sh
hub --noop help -a
# => git help -a
```

Any other `help` command line is plain `git help`.

Pass an option that git does not know:

```sh
hub --bogus status
```

```text
unknown option: --bogus
usage: git [-v | --version] [-h | --help] [-C <path>] [-c <name>=<value>]
...
```

git prints its message and exits with status 129.

## Options

hub reads the options before the command word. `--noop` is hub's own option.
`--version`, `-v`, `--help` and `-h` run hub version and hub help. git applies
every other option.

| Option | What it does |
|---|---|
| `--noop` | Print the git and gh commands that change something, and `open URL` or `copy URL` for the browser and clipboard, in place of running them. Read-only lookups still run. It can stand anywhere before the command word. |
| `-C DIR`, `-c NAME=VALUE`, `--config-env NAME=ENVVAR`, `--git-dir DIR`, `--work-tree DIR`, `--namespace NAME`, `--attr-source TREE`, `--super-prefix PATH`, `--shallow-file FILE` | git's global options that take a value. Each takes the next word as its value, whatever that word is. |
| `--git-dir=DIR`, `--bare`, `--no-pager`, and every other word that starts with `-` | git's other global options, passed to git in the order given. |
| `--version`, `-v` | Run [hub version](version.md). |
| `--help`, `-h` | Run [hub help](help.md). |

## How it works

hub applies these rules in order:

1. hub takes `--noop` out of the global options.
2. The first word that is neither an option nor an option's value is the
   command word. `--version` and `-v` count as `version`, and `--help` and
   `-h` count as `help`.
3. If the command word is not one of hub's commands, hub loads nothing and
   the command line goes to git unchanged. This includes `hub` with no
   arguments, which is `git` with no arguments, and a command line with only
   global options, such as `hub --exec-path`.
4. If the command word is one of hub's commands, hub starts git with your
   global options and the hub command. git applies `-C`, `-c`, `--git-dir` and
   the rest in git's order, then starts the hub command.

So a hub command sees the repository and the configuration that git would
see. `-C` follows git's rules: `CDPATH` and symbolic links play no part. If you
run a hub command from a subdirectory, the command works in that directory, so
relative paths keep their meaning. Every git that hub or gh starts sees your
`-c` values. A git alias named like a hub command, such as `alias.pr`, never
runs: hub's command wins.

If the first `git` on `PATH` is hub itself, hub stops, because it would start
itself forever. Every hub command, of any of the
[three kinds](../guide/how-hub-works.md#tell-the-three-kinds-of-command-apart),
needs bash 5 or newer, whatever its arguments. Plain git command lines run on
any bash, macOS's bash 3.2 included. hub also needs git 2.30 or newer and
gh 2.55 or newer, logged in with `gh auth login`.

### Three kinds of command

hub has three kinds of command: hub's own commands, git commands hub extends
and gh commands.
[How hub works](../guide/how-hub-works.md#tell-the-three-kinds-of-command-apart)
explains each kind, and the [command index](README.md) lists them.

`hub NAME --help` prints hub's manual for the command. For a git command hub
extends, `--help` and `-h` belong to git, so `hub clone --help` prints git's
manual. Run `hub help clone` for hub's.

## Exit status

| Status | When |
|---|---|
| The command's own status | git or gh ran: hub returns what it returned. For example, 129 for an option git does not know, 1 for `hub` with no arguments. |
| 0 | `--noop` printed the commands, or the hub command succeeded. |
| 1 | hub refused the command line: a usage error of a hub command, an old bash, or git on `PATH` that is hub itself. |
| Other values | Commands that say so in their manual, such as [ci-status](ci-status.md) (2 pending, 3 no status). |

hub prints its own messages on standard error as `hub NAME: MESSAGE`, or
`hub: MESSAGE` before a command runs. For git on `PATH` that is hub itself, and
for an old bash, it prints messages such as:

```text
hub: git on PATH is hub itself: DIR/git (install hub under its own name and alias git to it)
hub: bash 5 or newer is required for hub's commands (this is bash 3.2.57(1)-release; on macOS: brew install bash)
```

For the first, install hub under its own name and alias `git` to it. See
[install hub](../getting-started/install.md). A hub command that needs gh and
does not find it prints
`hub NAME: this command needs the GitHub CLI, gh (https://cli.github.com)`.
A usage error adds the command's `Usage:` lines:

```text
hub version: unknown option: -x
Usage: hub version [--build-options]
       hub --version [--build-options]
```

git's and gh's messages reach you unchanged. See
[troubleshooting](../guide/troubleshooting.md).

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub [--noop] COMMAND [OPTIONS]` | `hub [--noop] [GIT-OPTIONS...] COMMAND [ARGS...]`. git applies its global options to hub's commands too. |
| `--noop` printed the git commands hub would run. | Same. It prints the gh commands too. A plain git command is printed with its global options. For hub's commands, the global options are not printed: hub prints the commands as it runs them, after git applied the options. |
| A git alias such as `alias.c "clone --bare"` was expanded first, so `hub c OWNER/REPO` got hub's shorthand. | A git alias runs as plain git: git expands it, and hub's shorthands and URLs do not apply. Type the command's own name, such as `hub clone --bare OWNER/REPO`. |
| Asked for a username and password, and kept a token in `~/.config/hub` (or `HUB_CONFIG`). | No login or configuration file of its own. Log in with `gh auth login`. gh reads `GH_TOKEN` and `GITHUB_TOKEN`. |
| `GITHUB_USER`, `GITHUB_PASSWORD`, `HUB_CONFIG` | Not read. hub uses gh's login. |
| `HUB_PROTOCOL`, `git config hub.protocol` | Not read. Use `gh config set git_protocol ssh`. |
| `git config hub.host` | Not read. Use `gh auth login -h HOST` and `GH_HOST`. |
| `GITHUB_HOST` | Still read: hub passes it to gh as `GH_HOST` when `GH_HOST` is not set. |
| `HUB_VERBOSE` logged API requests. | Not read. Use `hub --noop COMMAND` to see the commands. |
| `init` and `submodule` were extended git commands. | Not supported: see [init](init.md) and [submodule](submodule.md). |
| `hub --list-cmds=others` added hub's commands to git's list. | hub hands the command line to git, and git lists only its own commands. |
| `hub help` listed the commands that hub provided. | Same. It lists the git commands hub extends too, under `GitHub commands provided or extended by hub`. |
| `hub version` printed git's version, then `hub version 2.14.2`. | Prints hub's version first, then git's and gh's. |
| A Go program that called the GitHub API itself. | A bash program. It runs on bash 5, git 2.30 and gh 2.55 or newer. gh does all the GitHub work. |

See [Coming from the original hub](../compatibility/README.md) for each
command.

## See also

- [hub alias](alias.md): make `git` run hub.
- [hub help](help.md): print the list of commands or a command's manual.
- [hub version](version.md): print the versions of hub, git and gh.
- [All commands](README.md): every command with its summary.
- [How hub works](../guide/how-hub-works.md) and
  [configuration](../guide/configuration.md).
- [Make git run hub](../getting-started/alias.md) and
  [install hub](../getting-started/install.md).
- [How hub is built](../developers/design.md): dispatch and re-entry in detail.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual: [hub(1)](https://hub.github.com/hub.1.html)
- This hub's manual: [hub](https://brc-dd.github.io/hub/)
