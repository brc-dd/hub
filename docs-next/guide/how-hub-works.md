---
title: How hub works
description: How hub reads a command line, its three kinds of command, --noop and exit status.
---

# How hub works

This page is for anyone who uses git and GitHub and wants to know what hub
changes in a command line. It shows how to tell which lines hub acts on and
which it hands to git untouched, how to preview any command with `--noop` and
how to read hub's exit status. The examples use `hub`. With the
[alias](../getting-started/alias.md), `git` runs the same commands.

## Know which lines hub acts on

hub reads the line as `hub [--noop] [GIT-OPTIONS...] COMMAND [ARGS...]`. It
removes `--noop`, skips git's global options, and takes the first other word
as the command word. Then it decides in this order:

1. If the command word names one of hub's commands, hub runs that command. If
   that command cannot read the line with certainty, it stops with a message
   or hands the line to git untouched. It never guesses.
2. Otherwise hub hands the line to git untouched. This includes a line with
   no command word at all, so `hub` alone is `git` alone.

`--version` and `-v` run `version`. `--help` and `-h` run `help`.

The first line below is not hub's, so hub hands the line to git untouched.
The second is hub's, and hub turns the shorthand into a URL:

```sh
hub --noop status -sb
# => git status -sb
hub --noop clone rails/rails
# => git clone https://github.com/rails/rails.git
```

If the `git_protocol` setting of GitHub CLI (gh) is `ssh`, hub uses
`git@github.com:rails/rails.git` instead. See
[Configuration](configuration.md). A line hub cannot carry out stops with a
message and status 1:

```sh
hub delete
# hub delete: name the repository to delete
# Usage: hub delete [-y] [[HOST/]OWNER/]NAME
```

## Tell the three kinds of command apart

The [command index](../commands/README.md) lists every command with a link.

| Kind | Commands | What hub does |
|---|---|---|
| hub's own commands | alias, browse, ci-status, compare, create, delete, fork, help, pull-request, sync, version | Runs the command. Any option not in its manual is a usage error, except for help, which hands other arguments to `git help`. |
| git commands hub extends | am, apply, checkout, cherry-pick, clone, fetch, merge, push, remote | Converts shorthands and GitHub URLs, then runs git (checkout runs `gh pr checkout` for a pull request URL). git's own options apply. |
| gh commands | api, gist, issue, pr, release | Maps the subcommand names of the original hub (mislav/hub 2.x), except for api, then runs gh. |

A git command hub extends acts only when the line holds something to convert:

```sh
hub --noop push origin HEAD
# => git push origin HEAD
hub --noop remote add rails rails/rails
# => git remote add rails https://github.com/rails/rails.git
hub --noop checkout https://github.com/OWNER/REPO/pull/12
# => gh pr checkout https://github.com/OWNER/REPO/pull/12
```

For gist, issue, pr and release, hub turns `show` into `view`. A line with no
subcommand gets `list`. api's arguments go to gh unchanged. gh does everything
else:

```sh
hub --noop issue show 12
# => gh issue view 12
hub --noop issue
# => gh issue list
```

hub's own commands stop at an option they do not have and print the usage
lines:

```sh
hub version -x
# hub version: unknown option: -x
# Usage: hub version [--build-options]
#        hub --version [--build-options]
```

`hub NAME --help` prints hub's manual for NAME. For a git command hub
extends, `--help` and `-h` belong to git. To read hub's manual for push, run
the first line. To read git's, run the second.

```sh
hub help push
git push --help
```

## Use git's global options with hub's commands

hub runs every command it handles through git. git applies `-C`, `-c`,
`--config-env`, `--git-dir`, `--work-tree`, `--bare` and the rest, exactly as
it does for its own commands. A global option that takes a value takes the
next word, as in `-C dotfiles`.

```sh
cd ~/src
hub --noop -C dotfiles browse -- issues
# => open https://github.com/OWNER/REPO/issues
hub --noop --git-dir=dotfiles/.git remote add rails rails/rails
# => git remote add rails https://github.com/rails/rails.git
```

Both lines run in the parent directory of `dotfiles`, a clone of OWNER/REPO.
With `--noop`, hub prints `open URL` instead of opening the browser. The `--`
in `browse -- issues` separates the subpage from the repository. See
[hub browse](../commands/browse.md). The printed git line has no global
options, because git already applied them.

## Know when hub hands the line to git untouched

Untouched means that git gets your arguments in your order, minus `--noop`,
and prints its own output and messages. For a command word that is not hub's,
hub loads nothing and runs `git` with the whole line, global options included.
For an extended git command, hub reads the line first and then runs `git NAME`
with your arguments. By then git has already applied the global options. hub
does this in three cases:

- The command word is not one of hub's commands, such as `status`, `log` or
  `tag`. Your own git aliases work as usual.
- An extended git command has nothing hub converts, as in `push origin HEAD`.
- An extended git command has a line that hub cannot read with certainty.
  Examples are an abbreviated option such as `--dep 1` and several short
  options in one word such as `checkout -qb main`. Two more are an option
  that takes a value with no value after it, such as `clone --depth`, and
  `--help`.

```sh
hub --noop clone --dep 1 rails/rails
# => git clone --dep 1 rails/rails
```

git then reads `rails/rails` as a path. Spell options in full, for
example `--depth 1`, so hub can find the shorthand.

## Preview a command with --noop

`hub --noop` prints the git and gh commands that change something instead of
running them. hub quotes each line, so you can paste it back into the shell.
Read-only lookups, such as the queries for your login, still run. Opening and
copying a URL print `open URL` and `copy URL`.

```sh
hub --noop tag 'two words' '*' '' -m "it's"
# => git tag two\ words \* '' -m it\'s
hub -C . --noop tag v1
# => git -C . tag v1
hub --noop browse
# => open https://github.com/OWNER/REPO
```

A plain git line keeps its global options. hub's commands print their lines
without them. Only the `--noop` flag turns preview on. Setting the `HUB_NOOP`
environment variable does not.

## Read hub's exit status

| Situation | Exit status |
|---|---|
| hub handed the line to git or gh | That program's status, for example 129 for git's `unknown option` |
| hub stops with a message, or a usage error | 1 |
| `--noop` with a plain git line | 0 |
| `hub ci-status` | 0 success, 1 failure or error, 2 pending, 3 no status |
| `hub sync` when a fetch of another tracked remote, an update or a deletion fails, or a branch that is behind is checked out in another work tree | 1 (a failed fetch of REMOTE: git's status) |

For example, `hub --definitely-not-an-option status` gets git's message and
status 129. See [hub ci-status](../commands/ci-status.md) and
[hub sync](../commands/sync.md) for those two commands.

## Know hub's limits

- Every command in the [command index](../commands/README.md), gh commands
  included, needs bash 5. On an older bash hub stops with this message:

  ```text
  hub: bash 5 or newer is required for hub's commands (this is bash 3.2.57(1)-release; on macOS: brew install bash)
  ```

  A plain git line runs on any bash, macOS's bash 3.2 included.
- If the first `git` on `PATH` is hub itself, hub stops with this message,
  where DIR is the directory on `PATH` that holds it:

  ```text
  hub: git on PATH is hub itself: DIR/git (install hub under its own name and alias git to it)
  ```

  Use the shell alias, not a file named `git`.
- A git alias named like a hub command, such as `alias.pr`, never runs.
- In a repository whose configuration git cannot read, hub's own commands,
  `version`, `alias` and `help` included, get git's fatal message.
- The commands that work on the current repository must run inside the work
  tree: create, sync, compare without a range, pull-request without `-h`, fork
  unless `--no-remote` and `GH_REPO` are given, and am, cherry-pick and merge
  when they convert something. With `--work-tree` or `GIT_WORK_TREE` and a
  current directory outside it, they stop.
- hub starts bash once before git runs, which takes about 15 ms. For each
  command it handles, hub starts one more bash and one more git.

## See also

- [hub commands](../commands/README.md)
- [hub browse](../commands/browse.md)
- [hub ci-status](../commands/ci-status.md)
- [hub sync](../commands/sync.md)
- [Configuration](configuration.md)
- [Troubleshooting](troubleshooting.md)
- [How hub is built](../developers/design.md)
- [Coming from the original hub](../compatibility/README.md)
