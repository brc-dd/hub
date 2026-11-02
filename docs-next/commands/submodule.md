---
title: hub submodule
description: hub submodule add is not supported. Use git submodule add with the full URL.
kind: not supported
original: https://hub.github.com/hub-submodule.1.html
---

# hub submodule

hub does not support `hub submodule add OWNER/REPO DIR`. hub passes every
`submodule` command to git unchanged, and git does not know GitHub shorthands
such as `OWNER/REPO`. To add a GitHub repository as a submodule, give
`git submodule add` its full URL. With the [alias](../getting-started/alias.md)
that makes git run hub, `git` and `hub` are the same command.

```sh
git submodule add https://github.com/OWNER/REPO.git DIR
```

## What the original hub did

The original hub (mislav/hub 2.x) had `hub submodule add [-p] [OPTIONS]
[USER/]REPOSITORY DESTINATION`. In that synopsis, `USER/REPOSITORY` is the
`OWNER/REPO` shorthand. It replaced `OWNER/REPO`, or `REPO` alone for one of
your own repositories, with the repository's URL. The manual lists `-p` but
does not explain it. It kept the other arguments of git submodule in place. The
URL used https, which anyone can fetch. hub chose https even for your own
repositories, which you can push to.

```sh
hub submodule add mojombo/grit vendor/grit
# => git submodule add https://github.com/mojombo/grit.git vendor/grit
hub submodule add -b foo --name grit mojombo/grit vendor/grit
# => git submodule add -b foo --name grit https://github.com/mojombo/grit.git vendor/grit
```

## What to do instead

Give git the full URL. With an https URL, anyone who clones your repository can
fetch the submodule without an ssh key:

```sh
git submodule add https://github.com/mojombo/grit.git vendor/grit
```

To fetch the submodule over ssh, use the ssh form of the URL:

```sh
git submodule add git@github.com:mojombo/grit.git vendor/grit
```

Put git's own options, such as `-b` and `--name`, before the URL:

```sh
git submodule add -b main --name grit https://github.com/mojombo/grit.git vendor/grit
```

hub ignores the `git_protocol` setting of the GitHub CLI (gh) here. hub uses it
only where hub writes the URL itself, as in `hub clone` and `hub remote add`.
`git submodule add` gets the URL unchanged. To match the form `hub clone` uses,
read the setting, and if gh prints `ssh`, use the ssh form of the URL:

```sh
gh config get git_protocol
# => https
```

A shorthand goes to git unchanged, and git refuses it:

```sh
git submodule add mojombo/grit vendor/grit
```

```text
fatal: repo URL: 'mojombo/grit' must be absolute or begin with ./|../
```

`hub --noop submodule add https://github.com/mojombo/grit.git vendor/grit`
prints `git submodule add https://github.com/mojombo/grit.git vendor/grit` and
does not run it. To clone a repository that has submodules, `hub clone` takes a
shorthand and passes git's `--recurse-submodules` through:
`hub clone --recurse-submodules mislav/top` runs
`git clone --recurse-submodules https://github.com/mislav/top.git`, or
`git clone --recurse-submodules git@github.com:mislav/top.git` when the
`git_protocol` setting is `ssh`.

## Why

hub leaves `submodule add` out on purpose, and
[Everything not supported](../compatibility/not-supported.md) lists it. A
submodule needs its URL only once, when you add it, and plain git does the job
with the full URL. So hub hands `submodule` to git.

## See also

- [hub clone](clone.md): clone a repository by its `OWNER/REPO` shorthand.
- [hub remote](remote.md): add a remote by its shorthand.
- [hub alias](alias.md): make git run hub.
- [Not supported](../compatibility/not-supported.md): everything hub leaves
  out on purpose, with the way to do it.
- [Repositories and URLs](../guide/repositories-and-urls.md): how hub turns a
  shorthand into a URL.
- [Configuration](../guide/configuration.md): the `git_protocol` setting.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-submodule(1)](https://hub.github.com/hub-submodule.1.html)
- gh's manual: [gh config get](https://cli.github.com/manual/gh_config_get)
- git's manual: [git submodule](https://git-scm.com/docs/git-submodule)
