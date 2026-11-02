---
title: hub commands
description: Every hub command, by kind, with its one-line summary and a link to its page.
---

# hub commands

This page lists every hub command by kind, with a link to its page. Each
summary is the Summary line of the command's manual. Each command page names
its kind at the top. If you made git run hub (see
[Make git run hub](../getting-started/alias.md)), `git browse` and `hub browse`
do the same thing. Several commands act on the project, the GitHub repository
that hub picks from your remotes.
[Project and remotes](../guide/project-and-remotes.md) explains how hub picks
it. The [hub](hub.md) page covers the `hub` command itself: `--noop`, git's
global options, `--help` and `--version`.

To read a manual in the terminal, run `hub help` with the command's name.
Without a name, `hub help` prints git's help and then the list of hub's
commands with their summaries. The same text is on the
[manuals website](https://brc-dd.github.io/hub/).

```sh
hub help pull-request
```

```text
Summary: Open a pull request for the current branch.
Usage: hub pull-request [-fpdoc] [-b [OWNER[/REPO]:]BASE] [-h [OWNER:]HEAD] [-m MESSAGE]...
...
```

## hub's own commands

These are commands that git does not have. They take only the options in their
manual. Any other option is a usage error, and hub prints the usage. The
exception is `hub help`, which passes any other arguments to `git help`.

| Command | What it does |
|---|---|
| [alias](alias.md) | Show how to make git run hub. |
| [browse](browse.md) | Open a GitHub repository in the web browser. |
| [ci-status](ci-status.md) | Show the CI status of a commit. |
| [compare](compare.md) | Open a GitHub compare page for a branch or a range. |
| [create](create.md) | Create a GitHub repository for this repository and add it as a remote. |
| [delete](delete.md) | Delete a repository on GitHub. |
| [fork](fork.md) | Fork the project on GitHub and add the fork as a remote. |
| [help](help.md) | Show git's help and hub's commands. |
| [pull-request](pull-request.md) | Open a pull request for the current branch. |
| [sync](sync.md) | Fetch and fast-forward or delete local branches to match the remotes. |
| [version](version.md) | Show the versions of hub, git and gh. |

## git commands hub extends

These git commands also accept GitHub shorthands such as `OWNER/REPO`, GitHub
URLs, a GitHub login or a comma-separated list of logins for `fetch`, or a
comma-separated list of remotes for `push`.
[Repositories and URLs](../guide/repositories-and-urls.md) lists every
shorthand and URL that hub accepts. A command line that holds nothing for hub
to act on goes to git unchanged. git's own options stay as they are.
`hub NAME --help` prints git's help, and `hub help NAME` prints hub's manual.

| Command | What it does |
|---|---|
| [am](am.md) | Apply the commits of a GitHub pull request, commit or comparison. |
| [apply](apply.md) | Apply the changes of a GitHub pull request, commit or comparison. |
| [checkout](checkout.md) | Check out a pull request, or run git checkout. |
| [cherry-pick](cherry-pick.md) | Cherry-pick a commit from its GitHub URL. |
| [clone](clone.md) | Clone a GitHub repository by its [OWNER/]REPO name. |
| [fetch](fetch.md) | Fetch from GitHub users' copies of the project, adding their remotes. |
| [merge](merge.md) | Merge a pull request locally, with the message GitHub's merge button uses. |
| [push](push.md) | Push to several remotes at once. |
| [remote](remote.md) | Add or change a remote by its GitHub OWNER[/REPO] name. |

## gh commands

hub hands the command line to the command of the same name in the GitHub CLI
(gh), such as `gh pr` for `hub pr`. gh's options and output stay as they are.
For `gist`, `issue`, `pr` and `release`, hub first renames the `show`
subcommand to `view`, and it runs `list` when you give no subcommand. `hub api`
passes every argument to `gh api` unchanged. `-h` or `--help` before the
subcommand, or as the first argument of `hub api`, prints hub's manual.

| Command | What it does |
|---|---|
| [api](api.md) | Make an authenticated GitHub API request (gh api). |
| [gist](gist.md) | List, view, create and edit gists (gh gist). |
| [issue](issue.md) | List, view, create and edit issues (gh issue). |
| [pr](pr.md) | List, view and check out pull requests (gh pr). |
| [release](release.md) | List, view, create, edit, upload and download releases (gh release). |

## Not supported

The original hub (mislav/hub 2.x) extended these two git commands. hub does
not extend them: `hub init` and `hub submodule` run git's own commands
unchanged. Each page shows the git and gh command lines that do what the
original extensions did. The
[list of everything not supported](../compatibility/not-supported.md) has the
rest.

| Command | What to use instead |
|---|---|
| [init](init.md) | `hub init -g`: use `git init`, then `gh repo create --source=.`. |
| [submodule](submodule.md) | `hub submodule add OWNER/REPO`: use `git submodule add` with the repository's URL. |

## Which command do I need?

| To do this | Use |
|---|---|
| Open a pull request for the current branch | [pull-request](pull-request.md) |
| List, view or check out pull requests | [pr](pr.md) |
| Check out a pull request from its URL | [checkout](checkout.md) |
| Clone a repository by its `OWNER/REPO` name | [clone](clone.md) |
| Fork the project and add your fork as a remote | [fork](fork.md) |
| Put a local repository on GitHub | [create](create.md) |
| Bring your local branches up to date with the remotes | [sync](sync.md) |
| Fetch a contributor's copy of the project | [fetch](fetch.md) |
| Push a branch to two remotes with one command | [push](push.md) |
| Apply a commit from its GitHub URL | [cherry-pick](cherry-pick.md) |
| Open the repository or one of its pages in the browser | [browse](browse.md) |
| See whether CI passed for a commit | [ci-status](ci-status.md) |
| List, view or create issues | [issue](issue.md) |
| List, create or download releases | [release](release.md) |
| Merge a pull request locally | [merge](merge.md) |
| Open a compare page for a branch | [compare](compare.md) |
| Call the GitHub API | [api](api.md) |
| List, view or create gists | [gist](gist.md) |
| Add a remote by its GitHub `OWNER/REPO` name | [remote](remote.md) |
| Apply a pull request's commits or changes from its URL | [am](am.md), [apply](apply.md) |
| Delete a repository on GitHub | [delete](delete.md) |
| Make `git` run hub | [alias](alias.md) |
| Read a command's manual | [help](help.md) |
| Check the installed versions of hub, git and gh | [version](version.md) |
