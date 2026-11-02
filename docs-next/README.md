---
title: hub
description: The GitHub commands of the original hub, on top of the GitHub CLI.
---

# hub

hub is a small bash program that brings back the GitHub commands of the
original hub (mislav/hub 2.x) on top of the GitHub CLI (gh). gh does all the
work on GitHub. hub uses gh's login, its hosts and its choice of https or ssh
URLs. hub has no token or settings of its own. After you
[make git run hub](getting-started/alias.md), `git clone rails/rails`,
`git pull-request` and `git sync` work. Every other git command runs
unchanged.

## The 60-second tour

After the first line, `git` runs hub, so `git` and `hub` are the same command.
A comment that starts with `=>` is the command hub runs. Any other comment
describes the effect. URLs are https unless gh's `git_protocol` is ssh.
`OWNER/REPO` is the current repository on GitHub, and `LOGIN` is your GitHub
login.

```sh
eval "$(hub alias -s)"                                # git now runs hub
git clone rails/rails                                 # => git clone https://github.com/rails/rails.git
git clone dotfiles                                    # => git clone https://github.com/LOGIN/dotfiles.git
git remote add jingweno                               # => git remote add jingweno https://github.com/jingweno/REPO.git
git fetch alice                                       # adds alice's copy of the project as the remote alice, then fetches it
git push origin,staging                               # => git push origin HEAD, then git push staging HEAD
git checkout https://github.com/rails/rails/pull/42   # => gh pr checkout https://github.com/rails/rails/pull/42
git merge https://github.com/jingweno/gh/pull/73      # merges the pull request locally, with the commit message GitHub's merge button uses
git cherry-pick https://github.com/jingweno/gh/commit/04a7985   # fetches the commit, then cherry-picks it
git sync                                              # fast-forwards local branches, deletes merged ones whose upstream is gone
git pull-request -p -m 'Fix the bug'                  # pushes the branch, then gh pr create
git fork                                              # forks OWNER/REPO and adds your fork as the remote LOGIN
git pr list                                           # => gh pr list
git browse -- issues                                  # opens https://github.com/OWNER/REPO/issues
git ci-status -v                                      # one line per check of HEAD
git status                                            # plain git
```

To see what a command would change without changing anything, put `--noop`
first. hub then prints the git and gh commands that change something instead
of running them. It still runs the ones that only read, such as its lookups
through gh:

```sh
hub --noop fork
# => gh api --hostname github.com --method POST repos/OWNER/REPO/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/REPO.git
```

OWNER/REPO is the repository you fork. LOGIN/REPO is your fork.

## Requirements

- bash 5 or newer for every command in [hub commands](commands/README.md)
  that hub supports, also without a shorthand or URL (`git push origin main`,
  `git checkout -b topic`). Other git commands, such as `git status`, run on
  any bash, macOS's bash 3.2 included.
- git 2.30 or newer.
- gh 2.55 or newer, logged in with `gh auth login`.

[Install hub](getting-started/install.md) has the reasons and the steps.

## Where to go next

### Getting started

| Page | What it covers |
|---|---|
| [Install hub](getting-started/install.md) | Requirements, Homebrew, `make install`, `gh auth login`, upgrading, uninstalling. |
| [Make git run hub](getting-started/alias.md) | `hub alias` per shell, how the alias works, caveats. |
| [Shell completion](getting-started/completions.md) | Shell completion for bash, zsh and fish: install, what they complete. |
| [First steps with hub](getting-started/first-steps.md) | A guided tour: clone, fork, pull request, ci-status, checkout, fetch, browse and compare, sync, `--noop`. |

### Guide

| Page | What it covers |
|---|---|
| [How hub works](guide/how-hub-works.md) | Which command lines hub handles, which go to git or gh, `--noop`, exit status. |
| [Repositories and URLs](guide/repositories-and-urls.md) | The shorthands and URLs hub accepts: `OWNER/REPO`, `REPO`, `USER`, `HOST/OWNER/REPO`, URLs. |
| [Project and remotes](guide/project-and-remotes.md) | Which remote is the project, which remote a branch pushes to, `GH_REPO`, the default branch, and common fork setups. |
| [Hosts and login](guide/hosts-and-login.md) | GitHub.com, GitHub Enterprise, `GH_HOST` and `GITHUB_HOST`, gh's login, tokens. |
| [Configuration](guide/configuration.md) | Every setting hub reads: environment variables, gh settings, git config. |
| [Browser and clipboard](guide/browser-and-clipboard.md) | How `browse`, `compare`, `-o`, `-c` and `-u` open, copy or print URLs. |
| [Troubleshooting](guide/troubleshooting.md) | The messages hub prints and what to do, common mistakes, getting more detail. |

### Commands

hub has three kinds of command. hub's own commands are new commands such as
`fork`. Git commands hub extends are git commands that also accept GitHub
names and URLs. gh commands pass to gh. See [hub commands](commands/README.md)
for the full index and [hub](commands/hub.md) for the `hub` command itself.

| Page | Kind | What it does |
|---|---|---|
| [hub alias](commands/alias.md) | hub's own command | Show how to make git run hub. |
| [hub am](commands/am.md) | git command hub extends | Apply the commits of a GitHub pull request, commit or comparison. |
| [hub api](commands/api.md) | gh command | Make an authenticated GitHub API request (`gh api`). |
| [hub apply](commands/apply.md) | git command hub extends | Apply the changes of a GitHub pull request, commit or comparison. |
| [hub browse](commands/browse.md) | hub's own command | Open a GitHub repository in the web browser. |
| [hub checkout](commands/checkout.md) | git command hub extends | Check out a pull request, or run `git checkout`. |
| [hub cherry-pick](commands/cherry-pick.md) | git command hub extends | Cherry-pick a commit from its GitHub URL. |
| [hub ci-status](commands/ci-status.md) | hub's own command | Show the CI status of a commit. |
| [hub clone](commands/clone.md) | git command hub extends | Clone a GitHub repository by its `[OWNER/]REPO` name. |
| [hub compare](commands/compare.md) | hub's own command | Open a GitHub compare page for a branch or a range. |
| [hub create](commands/create.md) | hub's own command | Create a GitHub repository for this repository and add it as a remote. |
| [hub delete](commands/delete.md) | hub's own command | Delete a repository on GitHub. |
| [hub fetch](commands/fetch.md) | git command hub extends | Fetch from GitHub users' copies of the project, adding their remotes. |
| [hub fork](commands/fork.md) | hub's own command | Fork the project on GitHub and add the fork as a remote. |
| [hub gist](commands/gist.md) | gh command | List, view, create and edit gists (`gh gist`). |
| [hub help](commands/help.md) | hub's own command | Show git's help and hub's commands. |
| [hub issue](commands/issue.md) | gh command | List, view, create and edit issues (`gh issue`). |
| [hub merge](commands/merge.md) | git command hub extends | Merge a pull request locally, with the message GitHub's merge button uses. |
| [hub pr](commands/pr.md) | gh command | List, view and check out pull requests (`gh pr`). |
| [hub pull-request](commands/pull-request.md) | hub's own command | Open a pull request for the current branch. |
| [hub push](commands/push.md) | git command hub extends | Push to several remotes at once. |
| [hub release](commands/release.md) | gh command | List, view, create, edit, upload and download releases (`gh release`). |
| [hub remote](commands/remote.md) | git command hub extends | Add or change a remote by its GitHub `OWNER[/REPO]` name. |
| [hub sync](commands/sync.md) | hub's own command | Fetch and fast-forward or delete local branches to match the remotes. |
| [hub version](commands/version.md) | hub's own command | Show the versions of hub, git and gh. |
| [hub init](commands/init.md) | not supported | `hub init -g` and what to do instead. |
| [hub submodule](commands/submodule.md) | not supported | `hub submodule add` and what to do instead. |

### Compatibility

| Page | What it covers |
|---|---|
| [Coming from the original hub](compatibility/README.md) | The original hub's commands, one by one, and what this hub does with each. |
| [Not supported](compatibility/not-supported.md) | Everything deliberately left out, each with the way to do it. |
| [hub and gh](compatibility/hub-vs-gh.md) | When to use hub and when gh, and which gh command each hub command maps to. |

### For developers

| Page | What it covers |
|---|---|
| [How hub is built](developers/design.md) | Principles, dispatch and re-entry, the module contract, operands, push remotes, tests and limits. |
| [Working on hub](developers/development.md) | Tests, lint, make targets, adding a command, releases, workflows, the manuals website. |

## The manuals

Every command has a manual. To print it, run `hub help NAME`:

```sh
hub help pull-request
```

For hub's own commands and gh commands, `hub NAME --help` prints the same
manual. For the git commands hub extends, `--help` prints git's manual. Run
`hub help NAME` for hub's manual, or `git help NAME` under the alias. The
manuals are also a website, one page per command, at
[brc-dd.github.io/hub](https://brc-dd.github.io/hub/).

## Coming from the original hub

Most commands from the original hub (mislav/hub 2.x) work as before. The git
commands hub extends keep git's options and act on GitHub shorthands and URLs.
`pr`, `issue`, `release`, `gist` and `api` are gh's commands, with gh's flags
and output. A few things changed: `create` makes a private repository unless
you pass `--public` or `--internal`, `init -g` and `submodule add` are not
supported, and some options of the original hub are gone, each with a way to
do it in [Not supported](compatibility/not-supported.md). Read
[Coming from the original hub](compatibility/README.md) for the table, command
by command, and the [original hub's manuals](https://hub.github.com/) for the
other side.

Mislav Marohnić and the contributors of the original hub designed these
commands, and gh does the work underneath. hub is MIT licensed: see
[LICENSE](../LICENSE).
