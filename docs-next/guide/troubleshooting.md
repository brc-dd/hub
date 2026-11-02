---
title: Troubleshooting
description: The messages hub prints, what causes each one, and how to fix it.
---

# Troubleshooting

This page is for anyone who ran a hub command and got a message instead of a
result. It shows how to read the message, lists the common ones with their
cause and fix, and shows how to see what hub would do before it does it.
hub runs git, and the GitHub CLI (gh) for GitHub. The examples use `hub`.
With the [alias](../getting-started/alias.md), `git` runs the same commands.
`LOGIN` stands for your GitHub login.

## Read a message

hub prints its messages on standard error in one shape, and exits with
status 1:

```text
hub NAME: message (way out)
```

`NAME` is the command that refused. If hub refuses before it starts a
command, the message begins with `hub:` and no name. The message names the
offending value first or after a colon. The text in parentheses at the end is
the way out: the command or option that gets past the refusal. hub quotes a
word you typed when it holds a space or a control character. For example,
`bad name` shows as `bad\ name`. An empty word shows as `''`.

```sh
hub fork --remote-name origin
# hub fork: remote already exists: origin (name another with --remote-name NAME)
```

A usage error comes from one of hub's own commands, or from checkout or
merge, when an option or argument is wrong. hub prints the message, then the
command's Usage lines:

```sh
hub version -x
# hub version: unknown option: -x
# Usage: hub version [--build-options]
#        hub --version [--build-options]
```

A line with `warning:` after the name is not a refusal. The command goes on.
For example, `hub sync` warns about a branch that it leaves alone:

```text
hub sync: warning: ahead seems to contain unpushed commits
```

hub leaves the branch `ahead` as it is and updates the other branches.

## Fix a common message

In the messages, `BRANCH`, `REMOTE`, `HOST`, `KEY`, `N`, `VALUE` and `DIR`
stand for the values hub prints. In the parentheses, hub prints words such as
`REMOTE`, `NAME` and `SHELL` as they are: put your own value there. Messages
from git and gh themselves reach you unchanged, with their own exit status.

### Log in to gh

| Message | Cause | Fix |
|---|---|---|
| `could not determine your GitHub login for HOST (run: gh auth login -h HOST)` | gh is not logged in to `HOST`, or the token in `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN` or `GITHUB_ENTERPRISE_TOKEN` gives no login. | Run `gh auth login -h HOST`, or set a valid token. See [Hosts and login](hosts-and-login.md). |

### Tell hub where a branch pushes

| Message | Cause | Fix |
|---|---|---|
| `cannot tell where BRANCH pushes (git push -u REMOTE BRANCH first, ...)` | No rule names the remote the branch pushes to: no pushRemote, pushDefault or upstream of the branch's own name, and more than one remote with none of them your fork and none named `origin`. hub also says this when there are several remotes and it cannot get your login. pull-request says this also when pushRemote or pushDefault names no remote. | Push with `-u` once, or set `branch.BRANCH.pushRemote`. For `hub pull-request`, name the branch on GitHub with `-h`. |
| `KEY names no remote (set it to a remote, or name a range)` | compare: `KEY` is `branch.BRANCH.pushRemote` or `remote.pushDefault`, and it names something that is not a remote. | Set it to a remote, or give a range. |
| `BRANCH is not pushed to REMOTE (use -p to push it, or -f to skip the check)` | pull-request found no remote-tracking branch for the branch. | Add `-p` to push first, or `-f` to skip the check. |
| `N commits of BRANCH are not pushed to REMOTE/BRANCH (...)` | The remote-tracking branch is behind the local one. | Add `-p`, or push the commits yourself. |
| `BRANCH is not pushed to REMOTE (push it first, or name a range)` | compare found no pushed branch to compare. | Push the branch, or give a range: `hub compare main...topic`. |
| `REMOTE does not push to a GitHub repository (...)` | The URL of the remote that the branch pushes to is not a GitHub repository. See [Project and remotes](project-and-remotes.md). | Name the branch with `-h` (pull-request), or a range (compare). |

### Fix a remote name

| Message | Cause | Fix |
|---|---|---|
| `remote already exists: REMOTE (name another with --remote-name NAME)` | fork or create wants to add a remote with a name you already use. Case does not count: `Mislav` and `mislav` clash. | Pass `--remote-name NAME`, or add `--no-remote` to fork. |
| `not a remote: REMOTE` | sync got a name that is not a remote, or a push to a list of remotes (`hub push origin,work`) names one that is not a remote. hub passes a single name to git unchanged. | Check the name with `git remote -v`. |

### Point hub at the repository

| Message | Cause | Fix |
|---|---|---|
| `no GitHub remote found (looked for upstream, github, origin)` | No remote points at a GitHub repository. | Add one, or set `GH_REPO=OWNER/REPO`. See [Project and remotes](project-and-remotes.md). |
| `not a repository: bad\ name (use REPO, OWNER/REPO, HOST/OWNER/REPO or a repository URL)` | browse, create or delete got a word that is not a repository name hub accepts. create and delete say `NAME` instead of `REPO`. | Use one of the forms in parentheses. See [Repositories and URLs](repositories-and-urls.md). |
| `GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL` | `GH_REPO` holds another value. | Fix or unset `GH_REPO`. |
| `not a host name: VALUE` | `GH_HOST` (or `GITHUB_HOST`) is not a host name. | Set it to a host such as `github.com`. |

### Install or upgrade gh

| Message | Cause | Fix |
|---|---|---|
| `this command needs the GitHub CLI, gh (https://cli.github.com)` | gh is not on `PATH`. | Install gh 2.55 or newer and run `gh auth login`. |
| gh's own error for an unknown flag or a failed request | hub does not check gh's version. An older gh lacks flags that hub passes. | Run `hub version`, then upgrade gh to 2.55 or newer. |
| gh's own error from `hub delete` | The token lacks the `delete_repo` scope. | Run `gh auth refresh -s delete_repo` once. |

### Open or copy a URL

| Message | Cause | Fix |
|---|---|---|
| `no browser found to open URL (set GH_BROWSER or BROWSER)` | `GH_BROWSER`, gh's `browser` setting and `BROWSER` are not set, and neither `open` nor `xdg-open` is installed. | Set `GH_BROWSER` or `BROWSER`. With browse or compare, `-u` prints the URL. See [Browser and clipboard](browser-and-clipboard.md). |
| `no clipboard tool found (install pbcopy, wl-copy or xclip)` | hub tries `pbcopy`, then `wl-copy`, then `xclip`, and finds none. | Install one of them. |

### Run hub itself

| Message | Cause | Fix |
|---|---|---|
| `hub: bash 5 or newer is required for hub's commands (...)` | The `bash` first on `PATH` is older, such as macOS's bash 3.2. | On macOS, run `brew install bash` and put Homebrew's bash first on `PATH`. |
| `hub: git on PATH is hub itself: DIR/git (install hub under its own name and alias git to it)` | hub is installed as `git`. | Install it as `hub` and use [hub alias](../commands/alias.md). |
| `hub alias: cannot tell your shell from SHELL (name it: hub alias SHELL)` | `SHELL` is empty. | Name the shell: `hub alias zsh`. |

Some refusals come from git, and hub shows them as they are. For example,
`hub remote add origin bob` in a repository that has `origin` prints git's
`error: remote origin already exists.` and exits with git's status 3. For a
command line that is not one of hub's commands, hub hands the line to git
untouched, so an unknown command or option gets git's own message.

## See what hub would do

`hub --noop` prints the git and gh commands that change something instead of
running them. Instead of opening or copying a URL, hub prints `open URL` or
`copy URL`. Read-only lookups still run, so `--noop` also shows the same
refusals as a real run.

In a clone of `OWNER/REPO`, on the branch `topic` that is not pushed yet:

```sh
hub --noop pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- origin HEAD:refs/heads/topic
# => gh pr create --repo github.com/OWNER/REPO --head topic --title Fix\ the\ bug --body ''
```

Use `--noop` to try a fix before you change anything. In this example, the
repository has two remotes, `upstream` (`OWNER/REPO`) and `work`
(`LOGIN/REPO`), and neither is `origin`. hub cannot tell where `main` pushes,
and `hub compare` stops with `cannot tell where main pushes`. Git's `-c`
option sets `branch.main.pushRemote` for this one command. hub now knows the
push remote and stops for the next reason: the branch is not pushed yet.

```sh
hub --noop -c branch.main.pushRemote=work compare
# hub compare: main is not pushed to work (push it first, or name a range)
```

Name the branch on GitHub with `-h`. hub then skips the push check:

```sh
hub --noop pull-request -h LOGIN:main -m 'Fix the bug'
# => gh pr create --repo github.com/OWNER/REPO --head LOGIN:main --title Fix\ the\ bug --body ''
```

hub quotes the lines so that you can paste them back into the shell. See
[How hub works](how-hub-works.md) for more on `--noop`.

## Check the versions

Run `hub version` (or `hub --version`). It prints hub's version, then git's,
then gh's first version line, or no gh line when gh is not on `PATH`:

```sh
hub version
# hub 0.3.0 (brc-dd/hub)
# git version 2.54.0
# gh version 2.103.3 (2026-10-26)
```

hub needs bash 5, git 2.30 and gh 2.55 or newer. See
[Install hub](../getting-started/install.md) for the reasons and the upgrade.

## Check where hub reads settings

hub has no configuration file and no token of its own. It reads environment
variables, gh's settings and login, and git config. It ignores the settings
of the original hub (mislav/hub 2.x), such as `hub.host` and `HUB_VERBOSE`.
See [Configuration](configuration.md) for every setting and its replacement.
To see the values hub gets, run these:

```sh
env | grep -E '^(GH_REPO|GH_HOST|GITHUB_HOST|GH_BROWSER|BROWSER)='
gh auth status
git config --get-regexp '^(remote|branch)\.'
```

## Report a problem

Open an issue on [brc-dd/hub](https://github.com/brc-dd/hub/issues).
Include these:

1. The output of `hub version`, and your operating system and shell.
2. The command line you ran, and the full message, copied as printed.
3. The output of the same command line with `--noop` after `hub`.
4. The output of `git remote -v`, with private names replaced.
5. What you expected instead. For a command you knew from the original hub,
   say how it behaved there. First check
   [Coming from the original hub](../compatibility/README.md).

Never paste a token.

## See also

- [hub alias](../commands/alias.md)
- [hub compare](../commands/compare.md)
- [hub pull-request](../commands/pull-request.md)
- [hub version](../commands/version.md)
- [How hub works](how-hub-works.md)
- [Hosts and login](hosts-and-login.md)
- [Project and remotes](project-and-remotes.md)
- [Repositories and URLs](repositories-and-urls.md)
- [Browser and clipboard](browser-and-clipboard.md)
- [Configuration](configuration.md)
- [Coming from the original hub](../compatibility/README.md)
