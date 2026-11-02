---
title: hub help
description: Show git's help and hub's commands.
kind: hub's own command
original: https://hub.github.com/hub-help.1.html
---

# hub help

`hub help` prints git's help followed by the list of commands that hub provides
or extends. With the name of one of those commands, it prints that command's
manual, a short plain-text page with its summary, usage and examples. Every
other command line goes to `git help` unchanged. The most common use is
`hub help NAME`, which shows a manual before you run the command.

```sh
hub help pull-request
# => Summary: Open a pull request for the current branch.
```

## Usage

```text
hub help [COMMAND]
hub help GIT-HELP-ARGS...
```

`COMMAND` is one of hub's commands: hub's own commands, the git commands hub
extends, or the GitHub CLI (gh) commands. `GIT-HELP-ARGS` is any other command
line, which goes to `git help` unchanged.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git help` is the same command. Each `# =>` line is what `hub --noop` prints:
the git command that hub runs. A manual goes in a separate block.

List hub's commands after git's own help:

```sh
hub help
```

```text
usage: git [-v | --version] [-h | --help] [-C <path>] [-c <name>=<value>]
...
GitHub commands provided or extended by hub (hub help COMMAND for details):

   alias          Show how to make git run hub.
   am             Apply the commits of a GitHub pull request, commit or comparison.
   api            Make an authenticated GitHub API request (gh api).
   ...
   version        Show the versions of hub, git and gh.
```

The output starts with git's usage text. Then hub prints a heading and one line
per command, with its summary.

Read the manual of one command:

```sh
hub help version
```

```text
Summary: Show the versions of hub, git and gh.
Usage: hub version [--build-options]
...
```

Read hub's manual of a git command that hub extends:

```sh
hub help push
```

```text
Summary: Push to several remotes at once.
...
```

For these commands, `--help` belongs to git, so `hub help NAME` is the way to
reach hub's manual.

Read git's manual of a git command that hub extends:

```sh
hub push --help
# => git push --help
```

Read the manual of one of hub's own commands with `--help`:

```sh
hub fork --help
```

```text
Summary: Fork the project on GitHub and add the fork as a remote.
...
```

For hub's own commands and the gh commands, `hub NAME --help` and
`hub help NAME` print the same manual.

Read git's manual of a git command that hub does not touch:

```sh
hub help log
# => git help log
```

List all of git's commands:

```sh
hub help -a
# => git help -a
```

Every option except a first `-h` or `--help` goes to `git help`.

Run hub with only `--help` or `-h`:

```sh
hub --help
hub -h
```

hub treats both as `hub help`. It prints git's help and the list of hub's
commands.

Print the manual of `hub help` itself:

```sh
hub help --help
```

```text
Summary: Show git's help and hub's commands.
...
```

Pass git's global options before `help`, here to print the name of the man
page instead of opening it:

```sh
hub -c man.viewer=print -c man.print.cmd=echo help log
```

```text
git-log
```

git applies its global options to `git help` too.

Pass more than one word:

```sh
hub help version extra
# => git help version extra
```

hub runs `git help` even when the first word is one of hub's commands.

Write a command name in another case:

```sh
hub help Version
# => git help Version
```

hub matches the name exactly, so a different case goes to git. Write the name
in lowercase to read hub's manual.

Preview the `git help` command line:

```sh
hub --noop help -w fork
# => git help -w fork
```

Under `--noop`, hub prints the `git help` command line instead of running it.

## Options

| Option | What it does |
|---|---|
| `-h`, `--help` | Print the manual of `hub help` itself and exit with status 0. |

Every other option, such as `-a`, `-w` or `-m`, goes to `git help` with the
rest of the command line. For git's own options, read git's manual of
[git help](https://git-scm.com/docs/git-help).

## How it works

hub applies these rules in order:

1. If the first argument is `-h` or `--help`, hub prints the manual of
   `hub help` and exits with status 0.
2. If there is exactly one argument and it names one of hub's commands, hub
   prints that command's manual and exits with status 0. A name matches when
   it starts with a lowercase letter, contains only lowercase letters, digits
   and dashes, and hub has a command of that name. The list printed by
   `hub help` shows every such name.
3. If there is any other argument, hub runs `git help` with all the arguments.
   The output and the exit status are git's. For example, an option that
   `git help` does not know prints git's message and exits with status 129.
4. Without arguments, hub runs `git help`, then prints the list of its
   commands with their summaries, in alphabetical order.

The manuals website at [brc-dd.github.io/hub](https://brc-dd.github.io/hub/)
shows the same manuals, one page per command.

`hub --noop` prints the `git help` command line of rule 3 instead of running
it. Rules 1, 2 and 4 print the same text with or without `--noop`.

hub starts each of its commands through git. If git cannot read the
configuration of the current repository, for example because `.git/config` has
a syntax error, `hub help` prints git's `fatal:` message and stops. git's own
`git help` without arguments, run without hub, still prints git's help there.
Fix the configuration, or run `hub help` outside the repository. See
[How hub works](../guide/how-hub-works.md).

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub help` printed git's help, then `These GitHub commands are provided by hub:` and a table of hub's new commands. | Prints git's help, then `GitHub commands provided or extended by hub (hub help COMMAND for details):` and every command hub has: its own, the git commands it extends and the gh commands. |
| `hub help COMMAND` opened the man page, for example `man hub-fork`. Without `man`, it showed the text page with `less -R`. | Prints the manual as plain text on standard output. hub has no man pages. |
| `hub help hub` showed the hub(1) manual. | Runs `git help hub`. The page [hub](hub.md) describes the command itself. |
| `hub help hub-COMMAND` showed hub's manual of an extended git command. | Runs `git help hub-COMMAND`. Use `hub help COMMAND`, for example `hub help push`. |
| `--plain-text` skipped the man page and printed the raw text. | Not supported. The manual is always plain text, and the option goes to `git help`. |
| `-w` or `help.format` set to `html` or `web` opened hub's HTML manual in the browser. `-m` forced the man page. | `-w` and `-m` go to `git help` and show git's manuals. Read hub's manuals on [brc-dd.github.io/hub](https://brc-dd.github.io/hub/). |
| `hub help -a` printed git's list, then `hub custom commands` and hub's command names. | Runs `git help -a`. Run `hub help` for hub's commands. |
| `hub help GITCMD` for a command hub did not handle ran `git help`. | Same. |
| `hub CMD --help` printed hub's manual for hub's own commands. | Same for hub's own commands and the gh commands. For a git command hub extends, `--help` is git's, so use `hub help CMD`. |
| Manuals were on [hub.github.com](https://hub.github.com/). | Manuals are on [brc-dd.github.io/hub](https://brc-dd.github.io/hub/). |

## See also

- [hub](hub.md): `hub --help`, `hub --version` and `--noop`.
- [hub version](version.md): the versions of hub, git and gh.
- [hub alias](alias.md): the alias that makes `git help` show hub's commands.
- [The command index](README.md): every command with its kind and summary.
- [How hub works](../guide/how-hub-works.md): the three kinds of command.
- [Make git run hub](../getting-started/alias.md): set up the alias.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-help(1)](https://hub.github.com/hub-help.1.html)
- git's manual: [git help](https://git-scm.com/docs/git-help)
- This hub's manual: [hub help](https://brc-dd.github.io/hub/help.html)
