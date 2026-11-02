---
title: hub and gh
description: When to use hub and when to use gh, and what each hub command runs.
---

# hub and gh

This page is for people who use hub, the GitHub CLI (gh), or both, and want
to know which one to reach for. It says which tool to use for a task and what
each hub command runs. hub keeps the commands of the original hub
(mislav/hub 2.x) for work in a git repository, and gh does all the work on
GitHub. The examples use `hub`. With [the alias](../getting-started/alias.md),
`git` runs the same commands.

## Who does what

hub does the work in your local repository. It clones by name and adds
remotes for other users' forks. It fetches from several users and pushes to
several remotes. It merges or applies a pull request locally and keeps local
branches up to date.

gh does the work on GitHub: pull requests, issues, releases, gists, Actions
and the rest. hub never talks to GitHub itself. Every request to GitHub is a
`gh` command that hub runs, with gh's login (see
[Install hub](../getting-started/install.md) and
[Hosts and login](../guide/hosts-and-login.md)).

Run a command under `--noop` to see the git and gh commands that change
something. In a clone of OWNER/REPO, `hub --noop fork` prints the gh request
and the remote it adds.

```sh
hub --noop fork
# => gh api --hostname github.com --method POST repos/OWNER/REPO/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/REPO.git
```

## What each hub command runs

The [three kinds of command](../guide/how-hub-works.md) hand their work to gh
and git as follows. A command that is not in the table is plain git.

| Command | Kind | What runs underneath |
|---|---|---|
| [`alias`](../commands/alias.md), [`help`](../commands/help.md), [`version`](../commands/version.md) | hub's own command | Nothing on GitHub. `alias` prints the shell line that makes git run hub. `help` shows a manual or `git help`. `version` runs `git --version` and `gh --version`. |
| [`browse`](../commands/browse.md), [`compare`](../commands/compare.md) | hub's own command | Your browser, or the clipboard with `-c`. Nothing else, except your login: with a token variable set, gh asks GitHub's API for it. |
| [`ci-status`](../commands/ci-status.md) | hub's own command | `gh api graphql` for the checks and statuses of the commit. |
| [`create`](../commands/create.md) | hub's own command | `gh repo create`, `git remote add`, and `git push --set-upstream` with `--push`. |
| [`delete`](../commands/delete.md) | hub's own command | `gh repo delete`. |
| [`fork`](../commands/fork.md) | hub's own command | `gh api --method POST repos/OWNER/REPO/forks`, then `git remote add`. |
| [`pull-request`](../commands/pull-request.md) | hub's own command | `git push` with `-p`, then `gh pr create`. |
| [`sync`](../commands/sync.md) | hub's own command | `git fetch --prune`, then git commands that fast-forward or delete local branches. `gh repo view` when git does not know the default branch. |
| [`am`](../commands/am.md), [`apply`](../commands/apply.md) | git command hub extends | `gh api` downloads the patch or diff, then `git am` or `git apply`. |
| [`checkout`](../commands/checkout.md) | git command hub extends | `gh pr checkout` for a pull request URL, else `git checkout`. |
| [`cherry-pick`](../commands/cherry-pick.md) | git command hub extends | `gh api` expands a short commit id, then `git fetch` and `git cherry-pick`. |
| [`clone`](../commands/clone.md), [`remote`](../commands/remote.md) | git command hub extends | `git clone` or `git remote` with the URL. Only your login and gh's `git_protocol` setting (https or ssh) come from gh. |
| [`fetch`](../commands/fetch.md) | git command hub extends | `gh repo view` checks each user's fork, then `git remote add` and `git fetch`. |
| [`merge`](../commands/merge.md) | git command hub extends | `gh pr view` reads the pull request, then `git fetch` and `git merge --no-ff`. |
| [`push`](../commands/push.md) | git command hub extends | `git push` once per remote. |
| [`api`](../commands/api.md), [`gist`](../commands/gist.md), [`issue`](../commands/issue.md), [`pr`](../commands/pr.md), [`release`](../commands/release.md) | gh command | The gh command of the same name, with every argument. For `gist`, `issue`, `pr` and `release`, hub renames `show` to `view` and runs `list` when no subcommand or an option comes first. `hub api` passes every argument to `gh api` unchanged. |

## Original hub commands that are gh commands now

The original hub had its own subcommands for some GitHub tasks. hub renames
only `show` to `view` and hands every other argument to gh unchanged, so type
gh's subcommand after `hub`. Run `gh label list` and `gh repo create` as gh.
Flags that only changed their letters are in
[Renamed or moved flags](README.md#renamed-or-moved-flags).

| Original hub | gh command now |
|---|---|
| `hub pr show 12` (opened the browser) | `hub pr view 12 --web` |
| `hub issue update 7 -l bug` | `hub issue edit 7 --add-label bug` (the original replaced the labels: remove the others with `--remove-label`) |
| `hub issue labels` | `gh label list` |
| `hub release edit -a FILE` | `hub release upload TAG FILE` |
| `hub gist show ID FILE` | `hub gist view ID --raw -f FILE` |
| `hub init -g` | `git init && gh repo create --source=.` |

```sh
hub --noop pr view 12 --web                # => gh pr view 12 --web
hub --noop issue edit 7 --add-label bug    # => gh issue edit 7 --add-label bug
hub --noop release upload TAG FILE         # => gh release upload TAG FILE
```

## What gh does that hub leaves to it

`hub pr show` and `hub pr merge` reach gh, because `pr` is a gh command.

Other gh commands, such as `run`, are not hub's. hub hands `hub run list` to
git, and git rejects it. Run these commands with gh.

The table lists common GitHub tasks that hub has no command of its own for,
with the gh command for each. The `pr` and `issue` rows also work as
`hub pr ...` and `hub issue ...`. The others, such as `run`, `workflow` and
`codespace`, need gh.

| Task | gh command |
|---|---|
| Merge a pull request on GitHub | `gh pr merge 12 --squash` |
| Review a pull request | `gh pr review 12 --approve` |
| Wait for the checks of a pull request | `gh pr checks 12 --watch` |
| Move an issue to another repository | `gh issue transfer 7 OWNER/REPO` |
| List or watch GitHub Actions runs | `gh run list`, `gh run watch RUN-ID` |
| Start a workflow | `gh workflow run WORKFLOW` |
| Create a codespace | `gh codespace create -R OWNER/REPO` |
| Update a fork's branch on GitHub | `gh repo sync OWNER/FORK` |
| Log in, or add a scope | `gh auth login`, `gh auth refresh -s delete_repo` |

```sh
hub --noop pr show 12                # => gh pr view 12
hub --noop pr merge 12 --squash      # => gh pr merge 12 --squash
hub --noop run list                  # => git run list
gh run list
```

> [!WARNING]
> `hub merge PULL-REQUEST-URL` and `gh pr merge` are different commands.
> `hub merge` merges the pull request into your current branch locally and
> pushes nothing. `gh pr merge` merges it on GitHub.

## If you already use gh

hub uses gh's login, hosts and settings, so there is nothing to set up twice.
`GH_HOST`, `GH_REPO`, `GH_BROWSER` and `gh config set git_protocol ssh` apply
to hub too (see [Configuration](../guide/configuration.md)). hub's own
commands, `fetch` and `remote` do not read `gh repo set-default`. They work on
`GH_REPO` if it is set, else on a GitHub remote (see
[The project and its remotes](../guide/project-and-remotes.md)).

If git runs hub through [the alias](../getting-started/alias.md), hub's
commands win over git aliases of the same name. For example, `git pr` runs
hub's `pr`, not your `alias.pr`. Scripts do not load the shell alias, so
`git` in a script runs plain git.

hub adds what gh does not try to do:

- [Shorthands](../guide/repositories-and-urls.md) for git commands, so that
  `git clone OWNER/REPO` and `git remote add USER` work.
- Git-side commands for GitHub URLs: merge, apply or cherry-pick a pull
  request or commit locally, and push to several remotes.
- `sync`, which fast-forwards local branches and deletes merged ones.
  `gh repo sync` updates one branch.
- `pull-request` with the original hub's options, such as `-p` to push first.
- `browse -u` and `compare -u`, which build a URL from your remotes and print
  it.
- `ci-status` for any commit, with an exit status that scripts can test (see
  [hub ci-status](../commands/ci-status.md#exit-status)).
- `--noop`, which prints the git and gh commands that change something
  instead of running them.

```sh
hub --noop clone OWNER/REPO          # => git clone https://github.com/OWNER/REPO.git
hub --noop push origin,staging
# => git push origin HEAD
# => git push staging HEAD
hub compare -u v1.0..v1.1            # https://github.com/OWNER/REPO/compare/v1.0...v1.1
```

## See also

- [Coming from the original hub](README.md)
- [Not supported](not-supported.md)
- [How hub works](../guide/how-hub-works.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [The project and its remotes](../guide/project-and-remotes.md)
- [hub's manuals](https://brc-dd.github.io/hub/)
- [the original hub's manuals](https://hub.github.com/)
- [gh's manual](https://cli.github.com/manual/)
