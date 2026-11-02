---
title: Browser and clipboard
description: How hub opens, copies or prints GitHub URLs.
---

# Browser and clipboard

This page is for anyone who wants hub to open a GitHub page in the right
browser, or to copy or print the URL instead. It shows how to pick the browser,
install a clipboard tool and print the URL. hub picks the browser in the same
order as GitHub CLI (gh). The examples use `hub` and run in a clone of
OWNER/REPO, on a branch `feature` that tracks origin/feature. With the
[alias](../getting-started/alias.md), `git` runs the same commands.

## Open or copy a URL

| Command | Opens by default | Open | Copy | Print |
|---|---|---|---|---|
| [`hub browse`](../commands/browse.md) | Yes | | `-c`, `--copy` | `-u`, `--url` |
| [`hub compare`](../commands/compare.md) | Yes | | `-c`, `--copy` | `-u`, `--url` |
| [`hub pull-request`](../commands/pull-request.md) | No | `-o`, `--browse` | `-c`, `--copy` | |
| [`hub create`](../commands/create.md) | No | `-o`, `--browse` | `-c`, `--copy` | |

For `browse` and `compare`, `-c` copies the URL instead of opening it. With
`-u` as well, hub prints the URL and copies it. `pull-request` and `create`
accept `-o` and `-c` in one command. With both, hub copies the URL first and
then opens it. If one of the two fails, hub still does the other.
`pull-request` uses the URL of the new pull request. hub looks up that URL with
`gh api` after `gh pr create` succeeds.

To copy the issues page of cli/cli instead of opening it:

```sh
hub --noop browse -c cli/cli issues
# => copy https://github.com/cli/cli/issues
```

To create ORG/NAME from a new repository with no `origin` remote, then copy
and open its URL:

```sh
hub --noop create -c -o ORG/NAME
# => gh repo create github.com/ORG/NAME --private
# => git remote add -- origin https://github.com/ORG/NAME.git
# => copy https://github.com/ORG/NAME
# => open https://github.com/ORG/NAME
```

## Pick the browser

hub takes the first of these that is set or installed, in the same order as gh.
An empty variable counts as unset.

1. The `GH_BROWSER` environment variable.
2. gh's `browser` setting, set with `gh config set browser CMD`.
3. The `BROWSER` environment variable.
4. The `open` command (macOS).
5. The `xdg-open` command (Linux and other desktops).

hub runs the value as a shell command line with the URL added as the last
argument, so the value can carry its own arguments. Each line below is a
separate way to choose a browser: `GH_BROWSER` for one command, gh's setting
for hub and gh, and `BROWSER` with an argument of its own:

```sh
GH_BROWSER=firefox hub browse rails/rails
gh config set browser firefox
export BROWSER='firefox --new-window'
```

## Install a clipboard tool

hub pipes the URL, without a newline, to the first of these on your `PATH`:
`pbcopy` (macOS), then `wl-copy` (Wayland), then `xclip -selection clipboard`
(X11). hub has no setting for the clipboard tool. To use `-c` on Linux, install
`wl-copy` or `xclip`. macOS includes `pbcopy`.

To see which clipboard tools are on your `PATH`:

```sh
command -v pbcopy wl-copy xclip
```

## Print the URL instead

`hub browse -u` and `hub compare -u` print the URL on standard output and open
nothing, for a machine without a browser or for another program to read.

To print the URL of a page of another project and of a compare range:

```sh
hub browse -u cli/cli releases
# => https://github.com/cli/cli/releases
hub compare -u v1.0..v1.1
# => https://github.com/OWNER/REPO/compare/v1.0...v1.1
```

hub writes the range `START..END` as `START...END`, the form that GitHub's
compare page uses.

## See what would happen with --noop

Under `hub --noop`, hub prints `open URL` or `copy URL` instead of running the
browser or the clipboard tool, and does not read gh's `browser` setting. hub
quotes the URL for the shell, so a backslash comes before each `?` and `&`.
`-u` still prints the plain URL. `pull-request` does not know the URL yet. It
prints the `gh api` command that looks up the URL, then `copy URL` and
`open URL`. The `-f` option skips the check that the current branch is pushed,
so the example works on a branch that is not pushed yet.

For a URL with a query, for `-u -c`, and for a new pull request:

```sh
hub --noop browse rails/rails 'pulls?q=is:open'
# => open https://github.com/rails/rails/pulls\?q=is:open
hub --noop browse -u -c cli/cli
# => https://github.com/cli/cli
# => copy https://github.com/cli/cli
hub --noop pull-request -f -o -c -m 'Fix the bug'
# => gh pr create --repo github.com/OWNER/REPO --head feature --title Fix\ the\ bug --body ''
# => gh api --hostname github.com repos/OWNER/REPO/pulls\?head=OWNER:feature\&state=open --jq .\[0\].html_url
# => copy URL
# => open URL
```

## Handle a missing browser or clipboard tool

If hub finds no browser or no clipboard tool, it prints one of these messages
on standard error and exits with status 1. The prefix names the command. The
first message holds the URL, so you can copy it by hand.

```text
hub browse: no browser found to open https://github.com/cli/cli (set GH_BROWSER or BROWSER)
hub browse: no clipboard tool found (install pbcopy, wl-copy or xclip)
```

When the browser or the clipboard tool runs and fails, hub exits with that
program's status. With `-u -c`, the URL is on standard output even when the
copy fails. `pull-request` and `create` open and copy the URL only after they
create the pull request or the repository. If the browser or the clipboard
tool then fails, the pull request or the repository still exists.

## See also

- [hub browse](../commands/browse.md)
- [hub compare](../commands/compare.md)
- [hub pull-request](../commands/pull-request.md)
- [hub create](../commands/create.md)
- [Configuration](configuration.md)
- [How hub works](how-hub-works.md)
- [Troubleshooting](troubleshooting.md)
- [gh config set](https://cli.github.com/manual/gh_config_set)
