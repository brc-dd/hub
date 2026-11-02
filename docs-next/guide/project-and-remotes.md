---
title: Project and remotes
description: Which remote is the project, and which remote a branch pushes to.
---

# Project and remotes

This page is for anyone who works in a repository with more than one remote,
such as a fork next to its parent. It shows how to predict and change where
hub's commands point. The examples use `hub`. With the
[alias](../getting-started/alias.md), `git` runs the same commands. `LOGIN`
stands for your GitHub login, and `USER` for another user's login.

## Find the project

The project is the GitHub repository that browse, ci-status, compare, fork,
pull-request and sync act on. `hub fetch` and `hub remote` take its host and
repository name for a user's copy. hub reads the fetch URL of each remote. It
checks `upstream`, `github` and `origin` first, in that order. Then it checks
the other remotes in the order that `git remote` lists them. The first GitHub
remote is the project. A GitHub remote has a repository URL on github.com, on
`GH_HOST`, or on a host that GitHub CLI (gh) is logged in to, as
[Repositories and URLs](repositories-and-urls.md) and
[Hosts and login](hosts-and-login.md) explain. If `origin` is your fork and
you add the parent as `upstream`, the project is the parent:

```sh
git remote add upstream https://github.com/OWNER/REPO.git
hub browse -u -- issues
# => https://github.com/OWNER/REPO/issues
```

`-u` prints the URL instead of opening it. Without a GitHub remote, hub stops
with this message:

```text
hub browse: no GitHub remote found (looked for upstream, github, origin)
```

## Point hub at another repository

Set `GH_REPO` to `OWNER/REPO`, `HOST/OWNER/REPO` or a repository URL, and hub
takes it as the project instead of the remotes:

```sh
GH_REPO=rails/rails hub browse -u
# => https://github.com/rails/rails
```

For any other value, hub stops with this message:

```text
hub browse: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL
```

`GH_REPO` changes only the project. `hub pull-request` still pushes to the
remote that the rules in
[Find where a branch pushes](#find-where-a-branch-pushes) pick. `hub sync`
syncs the remote whose repository is `GH_REPO`. With your fork as `origin` and
the parent as `upstream`:

```sh
GH_REPO=LOGIN/REPO hub --noop sync
# => git fetch --prune --quiet -- origin
```

## Find where a branch pushes

`hub pull-request`, `hub compare` and `hub browse` need the remote the current
branch pushes to, the push remote. hub takes the first of these that applies.
Each example starts from the layout that `hub fork` leaves: a clone of
OWNER/REPO as `origin`, your fork as the remote `LOGIN`, and the branch
`feature`.

1. `branch.BRANCH.pushRemote`, when it is set. It must name a remote:

   ```sh
   git config branch.feature.pushRemote origin
   hub --noop pull-request -p -m 'Fix the bug'
   # => git push --set-upstream -- origin HEAD:refs/heads/feature
   # => gh pr create --repo github.com/OWNER/REPO --head feature --title Fix\ the\ bug --body ''
   ```

2. `remote.pushDefault`, when it names a remote. With
   `git config remote.pushDefault origin`, hub runs the same commands.
3. The remote of the branch's upstream, when the upstream has the branch's own
   name, as after `git push -u origin feature`. hub keeps that upstream, so the
   push has no `--set-upstream`:

   ```sh
   git config branch.feature.remote origin
   git config branch.feature.merge refs/heads/feature
   hub --noop pull-request -p -m 'Fix the bug'
   # => git push -- origin HEAD:refs/heads/feature
   ```

   hub skips an upstream with another name on purpose. After
   `git checkout -b fix origin/main`, `origin/main` is only where `fix`
   started.
4. The only remote, when the repository has exactly one. See
   [Push to your own repository](#push-to-your-own-repository).
5. Your fork: the one remote whose push URL is a repository of your login. hub
   asks gh for your login, as [Hosts and login](hosts-and-login.md) says.

   ```sh
   git checkout -b fix origin/main
   hub --noop pull-request -p -m 'Fix the bug'
   # => git push --set-upstream -- LOGIN HEAD:refs/heads/fix
   # => gh pr create --repo github.com/OWNER/REPO --head LOGIN:fix --title Fix\ the\ bug --body ''
   ```

6. `origin`, when it exists. hub also uses this rule when the push URLs of two
   remotes are repositories of your login. See
   [Fork a project](#fork-a-project).

hub pushes the branch under its own name. If the push remote's repository is
not the project, hub passes `--head OWNER:BRANCH` to gh, as in rule 5.
`hub compare` writes `OWNER:BRANCH` only when that repository has another
owner. Some setups give no answer: a `pushRemote` or `pushDefault` that is
empty or names no remote, such as a URL or a misspelled name, a login that hub
cannot read, or no rule that applies. A `pushRemote` that names no remote stops
hub even when `pushDefault` names one. hub does not guess, because a guess
could push into the parent repository. hub stops with a message that names the
way out, such as:

```text
hub pull-request: cannot tell where feature pushes (git push -u REMOTE feature first, or name the head with -h)
hub compare: branch.feature.pushRemote names no remote (set it to a remote, or name a range)
```

## Work with a fork as origin

In a triangular workflow, you fetch from the parent and push to your fork. With
your fork as `origin` and the parent as `upstream`, the project is `upstream`,
and your branch pushes to `origin` by rule 5:

```sh
git clone https://github.com/LOGIN/REPO.git && cd REPO
git remote add upstream https://github.com/OWNER/REPO.git
git checkout -b feature
hub --noop pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- origin HEAD:refs/heads/feature
# => gh pr create --repo github.com/OWNER/REPO --head LOGIN:feature --title Fix\ the\ bug --body ''
```

`hub sync` first fetches `upstream`, which is the project's remote. Then it
fetches every other remote that a local branch tracks. With `feature` pushed
to `origin`:

```sh
hub --noop sync
# => git fetch --prune --quiet -- upstream
# => git fetch --prune --quiet -- origin
```

In the layout that `hub fork` leaves, `hub sync` first fetches `origin`, which
is the parent, then the remotes that local branches track, such as `LOGIN`.

## Tell hub the default branch

hub reads a remote's default branch from `refs/remotes/REMOTE/HEAD`, when that
symbolic ref and its branch both exist. `git fetch` creates it from git 2.48
on. With an older git, or after a rename of the default branch, set it once:

```sh
git remote set-head origin --auto
git symbolic-ref refs/remotes/origin/HEAD
# => refs/remotes/origin/main
```

If the ref is missing, `hub sync` asks gh for the default branch. If gh cannot
tell either, `hub sync` deletes no branch. `hub pull-request` without `-b` lets
gh pick the base. `hub browse` reads only the ref of the project's remote.
With the ref, on the default branch it opens the front page, and on another
pushed branch a page such as `https://github.com/LOGIN/REPO/tree/feature`.
Without it, every pushed branch counts as another branch, so on `main` it opens
`https://github.com/LOGIN/REPO/tree/main`.

## Set up common cases

### Push to your own repository

Your repository is the one remote, `origin`: the project and, by rule 4, the
push remote.

```sh
hub --noop pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- origin HEAD:refs/heads/feature
# => gh pr create --repo github.com/LOGIN/REPO --head feature --title Fix\ the\ bug --body ''
```

### Fork a project

Clone your fork and add the parent as `upstream`, as in
[Work with a fork as origin](#work-with-a-fork-as-origin). In a clone of the
parent, run [hub fork](../commands/fork.md) instead. It adds your fork as the
remote `LOGIN`. The remote URL uses gh's `git_protocol` setting (ssh or
https).

```sh
hub --noop fork
# => gh api --hostname github.com --method POST repos/OWNER/REPO/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/REPO.git
```

With `gh config set git_protocol ssh`, the URL is
`git@github.com:LOGIN/REPO.git`. If `origin` is another user's fork, such as
USER/REPO, and the parent is `upstream`, rule 6 pushes to `origin`. hub then
passes `--head USER:feature` to gh:

```sh
hub --noop pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- origin HEAD:refs/heads/feature
# => gh pr create --repo github.com/OWNER/REPO --head USER:feature --title Fix\ the\ bug --body ''
```

### Push to an organization repository

`origin` is the organization's OWNER/REPO, and you push branches to it. With
only `origin`, rule 4 picks it. With your fork as `LOGIN` too, rule 5 picks
the fork. Set `remote.pushDefault` to keep pushing to the organization:

```sh
git config remote.pushDefault origin
hub --noop pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- origin HEAD:refs/heads/feature
# => gh pr create --repo github.com/OWNER/REPO --head feature --title Fix\ the\ bug --body ''
```

## See also

- [hub browse](../commands/browse.md)
- [hub compare](../commands/compare.md)
- [hub fork](../commands/fork.md)
- [hub pull-request](../commands/pull-request.md)
- [hub sync](../commands/sync.md)
- [Repositories and URLs](repositories-and-urls.md)
- [Hosts and login](hosts-and-login.md)
- [Configuration](configuration.md)
- [Coming from the original hub](../compatibility/README.md)
- [git push](https://git-scm.com/docs/git-push), for `branch.BRANCH.pushRemote`
  and `remote.pushDefault`
