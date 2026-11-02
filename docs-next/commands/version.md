---
title: hub version
description: Show the versions of hub, git and gh.
kind: hub's own command
---

# hub version

`hub version` prints the version of hub, then the version of git, then the
version of the GitHub CLI (gh) when gh is installed. hub runs `git --version`
and `gh --version` for the last two. Use it, also outside a repository, to
check an install or to put all three versions in a bug report. The most common
use is `hub --version` right after you install or upgrade hub.

```sh
hub --version
```

## Usage

```text
hub version [--build-options]
hub --version [--build-options]
```

The command takes no operands. `hub --version` and `hub -v` are the same
command as `hub version`.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git version` and `git --version` are the same command and print the same
lines. Each text block is what the command prints.

Show the three versions, for example after an install:

```sh
hub version
```

```text
hub 0.3.0 (brc-dd/hub)
git version 2.54.0 (Apple Git-157)
gh version 2.103.3 (2026-10-26)
```

The first line is hub's version and the project it comes from. The second
line is the output of `git --version`, unchanged, and the third is the first
line of `gh --version`, without gh's second line, a link to its release notes.
Compare the git and gh lines with the requirements: git 2.30 or newer and gh
2.55 or newer. hub's own commands also need bash 5 or newer, and
[Install hub](../getting-started/install.md) has the full list.

Use the option form, as with git:

```sh
hub --version
hub -v
```

Both print the same three lines as `hub version`. hub treats `--version` and
`-v` as the command only in the command's place, the first word after hub's and
git's global options such as `-C DIR`. So `hub -C . --version` prints the same
three lines. See [How hub works](../guide/how-hub-works.md) for how hub reads
the command line.

Add git's build options:

```sh
hub version --build-options
```

```text
hub 0.3.0 (brc-dd/hub)
git version 2.54.0 (Apple Git-157)
cpu: arm64
no commit associated with this build
sizeof-long: 8
sizeof-size_t: 8
shell-path: /bin/sh
...
default-hash: sha1
gh version 2.103.3 (2026-10-26)
```

hub runs `git --version --build-options` in place of `git --version`. The lines
git prints depend on how your git was built. `hub --version --build-options`
prints the same output. So does `hub version --build-options --build-options`,
because hub reads the option once.

Run it on a machine without gh:

```sh
hub version
```

```text
hub 0.3.0 (brc-dd/hub)
git version 2.54.0 (Apple Git-157)
```

When gh is not on `PATH`, hub prints two lines and exits with status 0. The
commands that call gh, such as `hub pull-request` and `hub fork`, fail without
it. See [Install hub](../getting-started/install.md).

Read the manual:

```sh
hub version --help
```

```text
Summary: Show the versions of hub, git and gh.
Usage: hub version [--build-options]
       hub --version [--build-options]
...
```

`hub version -h` and `hub version --build-options --help` print the same
manual. So does `hub help version`.

Give an argument the command does not take:

```sh
hub version extra
```

```text
hub version: unexpected argument: extra
Usage: hub version [--build-options]
       hub --version [--build-options]
```

hub prints the message and the usage on stderr and exits with status 1. It
prints no version line and does not run gh.

Give an option the command does not have:

```sh
hub version -x
```

```text
hub version: unknown option: -x
Usage: hub version [--build-options]
       hub --version [--build-options]
```

hub prints the message and the usage on stderr and exits with status 1.
`--build-options` takes no value, so `hub version --build-options=1` is an
unknown option too. hub shows an empty argument as `''`. For example,
`hub version ''` prints `hub version: unexpected argument: ''`.

## Options

| Option | What it does |
|---|---|
| `--build-options` | Also print git's build options: hub runs `git --version --build-options`. Default: off. |
| `-h`, `--help` | Print this command's manual and exit. |

These are all the options. Any other option or argument is a usage error,
and `-h` or `--help` prints the manual.

## How it works

hub applies these rules in order:

1. hub reads the arguments in order. `-h` or `--help` prints the manual and
   stops, so hub never checks an argument after it. If hub first reaches an
   argument other than `--build-options`, it prints an error message and the
   usage on stderr. Then hub exits with status 1.
2. hub prints `hub VERSION (brc-dd/hub)`. `VERSION` is the release you
   installed. If hub cannot read its own version, it prints `unknown`.
3. hub runs `git --version`, with `--build-options` when you gave it. git
   prints its own lines. If git fails, hub stops there with git's status.
4. If `gh` is on `PATH`, hub runs `gh --version` and prints its first line.

`hub --noop version` prints the same lines, because the command changes
nothing.

If git cannot read the repository's configuration, `hub version` fails with
git's message and status before the command runs. For example, a bad line in
`.git/config` makes it print `fatal: bad config line 8 in file .git/config` and
exit with status 128. [How hub works](../guide/how-hub-works.md) explains
`--noop` and exit status.

## Exit status

`hub version` exits with one of these statuses:

| Status | When |
|---|---|
| 0 | hub prints the versions, with or without the gh line. |
| 1 | An unknown option or an unexpected argument, or bash is older than 5. |
| git's status | `git --version` failed, or git cannot read the repository's configuration. |

hub's own refusals print one of these messages on stderr and exit with
status 1:

```text
hub version: unknown option: OPTION
hub version: unexpected argument: ARGUMENT
hub: bash 5 or newer is required for hub's commands (this is bash VERSION; on macOS: brew install bash)
```

## Differences from the original hub

`hub version` and `hub --version` exist in both this hub and the original hub
(mislav/hub 2.x). The original command lines work as before. The output
differs.

| Original hub | This hub |
|---|---|
| Printed `git version 2.25.0` first, then `hub version 2.14.2`. | Prints hub's line first, then git's: `hub 0.3.0 (brc-dd/hub)`, `git version 2.54.0`. |
| hub's line was `hub version VERSION`. | hub's line is `hub VERSION (brc-dd/hub)`, which names this project. |
| No gh line. | Adds gh's first version line when gh is installed. |
| Had no options. | Takes `--build-options`, passed to `git --version`. |
| Had no manual page of its own. The usage text was "Shows git version and hub client version." | `hub help version` and `hub version --help` print a manual. |
| The README said to check `hub version` after you install a community package, which can lag behind. | Same. Compare the line with the latest release of brc-dd/hub. |

A script that reads the original hub's second line as its version must read the
first line now, and match `hub VERSION (brc-dd/hub)`.

## See also

- [hub](hub.md): the `hub` command, its `--version` and `--help` forms.
- [hub help](help.md): print the manual of any command.
- [Install hub](../getting-started/install.md): requirements, upgrading.
- [Troubleshooting](../guide/troubleshooting.md): messages hub prints and
  what to do.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manuals: [hub.github.com](https://hub.github.com/). They
  have no page for `version`.
- gh's manual: [gh](https://cli.github.com/manual/gh), for `gh --version`.
- This hub's manual: [hub version](https://brc-dd.github.io/hub/version.html)
