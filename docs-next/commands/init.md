---
title: hub init
description: Not supported. Create the GitHub repository with gh repo create or hub create instead.
kind: not supported
original: https://hub.github.com/hub-init.1.html
---

# hub init

hub does not support `hub init -g`. hub has no `init` command of its own, so
`hub init` is plain `git init`, and git refuses the `-g` flag with status 129
and creates nothing. With the [alias](../getting-started/alias.md),
`git init -g` fails the same way. To start a project on GitHub, run `git init`
and then let the GitHub CLI (gh) or [`hub create`](create.md) create the
repository and add the remote.

```sh
hub init -g
```

```text
error: unknown switch `g'
usage: git init [-q | --quiet] [--bare] [--template=<template-directory>]
...
```

## What the original hub did

In the original hub (mislav/hub 2.x), `hub init -g` ran `git init` and then
added the remote `origin` pointing to `LOGIN/REPO` on GitHub. `LOGIN` is your
GitHub login and `REPO` was the name of the directory, with spaces turned into
dashes. It did not create the repository on GitHub. Without `-g`, it was plain
`git init`. Other `git init` arguments, a directory included, went to
`git init` unchanged. With a directory, the original hub ran `git remote add`
inside that directory. The remote used https unless `HUB_PROTOCOL` or the
`hub.protocol` git setting was `git` or `ssh`, which gave
`git@github.com:LOGIN/REPO.git`.

```sh
hub init -g
# => git init
# => git remote add origin https://github.com/LOGIN/REPO.git

hub init -g new_dir
# => git init new_dir
# => git remote add origin https://github.com/LOGIN/new_dir.git

GITHUB_HOST=git.my.org hub init -g
# => git init
# => git remote add origin https://git.my.org/LOGIN/REPO.git
```

## What to do instead

To start a new project as a public GitHub repository, let gh create it:

```sh
git init my-project
cd my-project
git add .
git commit -m "Initial commit"
gh repo create --public --source=. --remote=origin --push
```

gh creates the repository from the current directory, adds it as `origin` and
pushes your commits. gh names the repository after the directory.

To start a new project as a private repository, use `--private` with gh:

```sh
gh repo create --private --source=. --remote=origin --push
```

Or run `hub create`, which creates a private repository by default. With
`--noop`, hub prints the commands and runs none of them:

```sh
hub --noop create --push my-project
# => gh repo create github.com/LOGIN/my-project --private
# => git remote add -- origin https://github.com/LOGIN/my-project.git
# => git push --set-upstream origin HEAD
```

The remote URL follows gh's `git_protocol` setting (see
[gh settings](../guide/configuration.md#change-settings-through-gh)).

To put an existing repository with commits on GitHub, name the new repository
and push the commits to it:

```sh
cd ~/code/dotfiles
gh repo create LOGIN/dotfiles --private --source=. --remote=origin --push
```

If the repository already has an `origin` remote, give the new one another
name:

```sh
gh repo create LOGIN/dotfiles --private --source=. --remote=github --push
hub create --remote-name github --push dotfiles
```

To add only the remote, as the original `-g` did, use git. This works when the
GitHub repository already exists, or when you create it later:

```sh
git init
git remote add origin https://github.com/LOGIN/REPO.git
```

## Why

hub keeps only what gh and git do not already do well.
`gh repo create --source=.` creates the repository on GitHub and adds the
remote. With `--push`, it also pushes the commits. It does more than
`hub init -g` did. A separate `init` command would add code to hub and give the
user nothing new.

## See also

- [hub create](create.md): create a GitHub repository for the current
  repository and add it as a remote.
- [Not supported](../compatibility/not-supported.md): everything hub leaves
  out on purpose, with the way to do it.
- [How hub works](../guide/how-hub-works.md): which words hub hands to git.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-init(1)](https://hub.github.com/hub-init.1.html)
- gh's manual: [gh repo create](https://cli.github.com/manual/gh_repo_create)
