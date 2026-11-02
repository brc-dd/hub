---
title: hub sync
description: Fetch and fast-forward or delete local branches to match the remotes.
kind: hub's own command
original: https://hub.github.com/hub-sync.1.html
---

# hub sync

`hub sync` fetches the project's remote and every remote that a local branch
tracks, then brings your local branches in line with them. hub runs
`git fetch --prune --quiet`, fast-forwards each branch that is behind, deletes
each branch whose upstream is gone and that the default branch contains, and
warns about the rest. Use it after GitHub merges your pull requests. The most
common use is `hub sync`, which updates the default branch and removes
finished branches.

```sh
hub sync
```

## Usage

```text
hub sync [REMOTE]
```

`REMOTE` is the name of a remote to sync, such as `origin` or `upstream`.
Without it, hub uses the project's remote, as
[Project and remotes](../guide/project-and-remotes.md) describes.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git sync` is the same command. Each `# =>` line is what `hub --noop` prints:
the git command that hub runs. The examples run in a clone of OWNER/dotfiles
whose default branch is `main`. `GIT_DIR` stands for the absolute path of your
git directory.

Bring every branch up to date. Here `main` is behind and the remote branch
`fix-typo` is gone after its merge:

```sh
hub sync
```

```text
Deleted branch fix-typo (was 5d6e7f8).
Updated branch main (was 1a2b3c4).
```

hub prints one line per branch it changes and nothing when every branch is up
to date. The current branch comes after the others.

Preview a sync. Here `feature` and `main` are behind, and the current branch
`topic` was merged and deleted on `origin`:

```sh
hub --noop sync
# => git fetch --prune --quiet -- origin
# => git fetch --quiet --no-recurse-submodules GIT_DIR refs/remotes/origin/feature:refs/heads/feature
# => git fetch --quiet --no-recurse-submodules GIT_DIR refs/remotes/origin/main:refs/heads/main
# => git switch --quiet --no-guess main
# => git branch -D -- topic
```

hub fast-forwards `feature` and `main` with a fetch from your own repository,
which does not change the work tree. Because `topic` is the current branch,
hub switches to `main` before it deletes `topic`.

Preview the same sync with `main` as the current branch:

```sh
hub --noop sync
# => git fetch --prune --quiet -- origin
# => git fetch --quiet --no-recurse-submodules GIT_DIR refs/remotes/origin/feature:refs/heads/feature
# => git branch -D -- topic
# => git merge --quiet --ff-only --no-squash refs/remotes/origin/main
```

hub fast-forwards the current branch last, with a merge instead of a fetch.

Keep local work. Here `feature` is ahead of `origin/feature` and `experiment`
has diverged from `origin/experiment`:

```sh
hub sync
```

```text
hub sync: warning: experiment seems to contain unpushed commits
hub sync: warning: feature seems to contain unpushed commits
```

hub leaves both branches as they are and exits 0.

Clean up after GitHub merges the pull request of the current branch. Here you
are on `topic`, and GitHub merged its pull request and deleted the remote
branch:

```sh
hub sync
```

```text
Updated branch main (was 1a2b3c4).
Deleted branch topic (was 9f8e7d6).
```

hub fast-forwards `main`, switches to it and deletes `topic`.

Keep a squash-merged branch. A squash merge makes new commits, so the branch
is not part of the default branch:

```sh
hub sync
```

```text
hub sync: warning: topic was deleted on origin, but is not merged into origin/main
```

hub keeps the branch and its `branch.topic.*` settings.

Sync a fork's clone, where `origin` points to your fork LOGIN/dotfiles and
`upstream` to OWNER/dotfiles:

```sh
hub --noop sync
# => git fetch --prune --quiet -- upstream
# => git fetch --prune --quiet -- origin
```

hub syncs `upstream` and also fetches `origin`, because your branches track
it. `main` moves to `upstream/main`, even when it tracks `origin/main`.

Sync a named remote. Here every branch tracks `origin`:

```sh
hub --noop sync origin
# => git fetch --prune --quiet -- origin
```

hub also fetches every remote that a local branch tracks, here none other.

Sync the remote that points to the repository in `GH_REPO`. With every branch
up to date, hub prints only the fetch:

```sh
GH_REPO=OWNER/dotfiles hub --noop sync
# => git fetch --prune --quiet -- origin
```

`GH_REPO` names a repository as `OWNER/REPO`, `HOST/OWNER/REPO` or a URL (see
[Configuration](../guide/configuration.md)).

Sync a remote that is not on GitHub, such as `mirror` on another host. If your
git is older than 2.48, create `refs/remotes/mirror/HEAD` once:

```sh
git remote set-head mirror --auto
hub sync mirror
```

hub reads the default branch from that reference. Without it, hub deletes no
branch and warns, but it still fast-forwards the branches that are behind.

Sync while a branch is checked out in another work tree (from
`git worktree add`):

```sh
hub sync
```

```text
hub sync: warning: busy is checked out in another work tree; leaving it alone
Updated branch feature (was 4c5d6e7).
```

hub goes on with the other branches. Because `busy` is behind and hub cannot
move it, `hub sync` exits 1.

Name a remote that does not exist:

```sh
hub sync nope
```

```text
hub sync: not a remote: nope
```

Name a repository in `GH_REPO` that no remote points to:

```sh
GH_REPO=octo/other hub sync
```

```text
hub sync: no remote points to GH_REPO: octo/other (name the remote to sync)
```

## Options

| Option | What it does |
|---|---|
| `-h`, `--help` | Print the manual, the same text as `hub help sync`. |

These are all the options. Any other option is a usage error, and `-h` or
`--help` prints the manual.

## How it works

hub applies these rules in order:

1. hub picks the remote: `REMOTE` when you name it, else the remote that points
   to `GH_REPO`, else the project's remote (see
   [Project and remotes](../guide/project-and-remotes.md)). Without a GitHub
   remote, hub stops.
2. hub runs `git fetch --prune --quiet -- REMOTE`, then the same for every
   other remote that a local branch tracks. Your fetch settings apply, for
   example `fetch.recurseSubmodules`.
3. hub learns the default branch from `refs/remotes/REMOTE/HEAD`, which
   `git fetch` creates from git 2.48 on. For a GitHub remote without that
   reference, hub runs
   `gh repo view HOST/OWNER/REPO --json defaultBranchRef --jq .defaultBranchRef.name`
   with the GitHub CLI (gh). If neither knows the default branch, for example
   without gh, hub deletes no branch.
4. hub goes through the local branches. The current branch comes after the
   others. A branch that tracks a local branch comes at the end, after the
   branch it tracks, so a chain of local upstreams moves in one run.
5. For each branch, hub applies the first row of the table below that fits.

| Branch | What hub does |
|---|---|
| The default branch, behind `REMOTE`'s copy | Fast-forwards it from `REMOTE`, whatever it tracks |
| Behind its upstream | Fast-forwards it |
| Ahead of its upstream, or diverged | Leaves it alone, with a warning |
| Upstream deleted, merged into `REMOTE`'s default branch | Deletes it and its `branch.NAME.*` settings |
| Upstream deleted, not merged | Leaves it alone, with a warning |
| No upstream (other than the default branch), or a symbolic ref (a branch that points to another branch) | Leaves it alone, silently |

hub holds the default branch against its own upstream only when it has
commits that `REMOTE`'s copy lacks. In a fork's clone, when `main` is ahead of
`origin/main`, hub warns that it seems to contain unpushed commits.

hub never deletes these branches: a branch whose upstream is a local branch, a
branch whose remote hub could not fetch, and the default branch. A branch made
by `gh pr checkout` for a fork's pull request tracks a URL, not a remote, so
hub leaves it alone.

hub never discards local commits. git refuses a fast-forward that is not
possible and prints its own message. If local changes are in the way of the
current branch, git's message shows and the branch stays where it was. On a
detached HEAD, hub updates the branches and leaves HEAD alone. hub
fast-forwards a branch that is not checked out with a fetch from your own
repository. That fetch works even when `protocol.file.allow` or
`GIT_ALLOW_PROTOCOL` blocks local paths.

## Exit status

`hub sync` exits with git's status when the fetch of `REMOTE` fails, and stops
there. It exits with status 0 when every fetch, update and deletion works.
Warnings do not change it. It exits with status 1 when a fetch of another
tracked remote, an update or a deletion fails, or when a branch that is behind
is checked out in another work tree. hub still tries every branch.

hub's own refusals exit with status 1 before hub fetches anything: a usage
error, an unknown remote, no GitHub remote, an invalid `GH_REPO` or one that no
remote points to, or a directory outside a repository. The usage errors also
print the `Usage:` line. These are the messages and the warnings:

| Message | What to do |
|---|---|
| `hub sync: not a remote: nope` | Name a remote that `git remote` lists. |
| `hub sync: unexpected argument: upstream` | Name one remote. |
| `hub sync: unknown option: --prune` | Leave out the option. `hub sync` takes none. |
| `hub sync: no remote points to GH_REPO: octo/other (name the remote to sync)` | Name the remote to sync. |
| `hub sync: no GitHub remote found (name the remote to sync)` | Name the remote to sync. |
| `hub sync: warning: feature seems to contain unpushed commits` | Push the branch, or leave it. |
| `hub sync: warning: topic is ahead of main` | The upstream is the local branch `main`. Nothing to do. |
| `hub sync: warning: topic was deleted on origin, but is not merged into origin/main` | If the pull request is merged, run `git branch -D topic`. |
| `hub sync: warning: topic is merged and deleted on origin (switch to another branch to delete it)` | Switch to another branch, then run `hub sync` again. |
| `hub sync: warning: topic was deleted on mirror, but the default branch of mirror is not known; leaving it alone` | Run `git remote set-head mirror --auto` once. |
| `hub sync: warning: busy is checked out in another work tree; leaving it alone` | Update `busy` in its own work tree. |

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub sync [--color]` | `hub sync [REMOTE]`. `--color` is not supported. hub prints plain text. |
| Had no remote operand. | `REMOTE` picks the remote to sync. |
| Fetched `origin` with `git fetch --prune --quiet --progress origin`. | Fetches the project's remote (`upstream`, `github`, `origin`, then the others) and every remote a local branch tracks, with `--prune --quiet`. |
| Used the remote branch of the same name as the upstream of a branch without upstream configuration. | A branch without an upstream is left alone. Only the default branch is updated without one. |
| Fast-forwarded branches that were behind. | Same. The default branch follows the project's remote, also in a fork's clone. |
| Warned about unpushed commits and exited 0. | Same, exit 0. The message is `hub sync: warning: feature seems to contain unpushed commits`, without quotes around the name. |
| Deleted a branch whose upstream was deleted and that was merged into the default branch, the checked-out branch too. | Same. hub first switches to the default branch, and keeps the branch with a warning when the default branch is not a local branch. |
| Warned `'feature' was deleted on origin, but appears not merged into 'master'`. | Warns `feature was deleted on origin, but is not merged into origin/main`. A squash-merged branch counts as not merged and is kept. |
| Did not handle work trees. | A branch checked out in another work tree is left alone, with a warning, and sync exits 1. |
| Did not handle a missing default branch. | With git older than 2.48, run `git remote set-head REMOTE --auto` once so that sync knows a non-GitHub remote's default branch. Without it, no branch is deleted. |

## See also

- [hub fetch](fetch.md): to fetch from GitHub users' copies of the project.
- [hub fork](fork.md): to make a fork and add it as a remote.
- [Project and remotes](../guide/project-and-remotes.md)
- [How hub works](../guide/how-hub-works.md), for `--noop`
- [Configuration](../guide/configuration.md), for `GH_REPO`
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-sync(1)](https://hub.github.com/hub-sync.1.html)
- gh's manual: [gh repo sync](https://cli.github.com/manual/gh_repo_sync)
