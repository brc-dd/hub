---
title: Repositories and URLs
description: The shorthands and GitHub URLs hub accepts, and where.
---

# Repositories and URLs

This page is for anyone who names GitHub repositories, pull requests or
commits on the command line. It shows how to write each form hub reads, where
hub reads it, and what hub leaves to git. The examples use `hub` and run in a
clone of OWNER/REPO, with the default https protocol of GitHub CLI (gh). With
the [alias](../getting-started/alias.md), `git` runs the same commands.
`LOGIN` stands for your GitHub login, and `USER` for another user.

## Name a repository with OWNER/REPO or REPO

`OWNER/REPO` names a repository on the default host (see
[Choose the default host](hosts-and-login.md#choose-the-default-host)). In
`remote`, `OWNER/REPO` names a repository on the project's host, else on the
default host. `REPO` alone names one of your own repositories, and hub asks gh
for your login. hub drops a `.git` suffix.

An owner is letters, digits and hyphens, and does not start with a hyphen. A
user of an Enterprise Managed Users account is also an owner, written
`NAME_SHORTCODE`, such as `octo_admin`. A repository name is letters, digits,
`_`, `.` and `-`, but never `.` or `..`. hub reads a word that starts with `-`
as an option, not as `REPO`. In `clone`, `REPO.wiki` is the repository's wiki.

`hub --noop` prints the git and gh commands that change something instead of
running them. Read-only lookups still run. Each form runs like this:

```sh
hub --noop clone rails/rails
# => git clone https://github.com/rails/rails.git
hub --noop clone REPO
# => git clone https://github.com/LOGIN/REPO.git
hub browse -u cli/cli.git
# => https://github.com/cli/cli
hub --noop clone rails/rails.wiki
# => git clone https://github.com/rails/rails.wiki.git
hub --noop clone octo_admin/site
# => git clone https://github.com/octo_admin/site.git
```

## Name a user with USER alone

The project is the GitHub repository of the current clone. In `fetch` and
`remote add`, one word without a slash names a GitHub user's copy of the
project. See [Project and remotes](project-and-remotes.md).

- `remote add USER` adds USER's copy of the project as a remote named USER.
- `remote add origin` adds your own copy.
- `remote add NAME OWNER[/REPO]` uses the project's repository name when REPO
  is missing. `remote set-url NAME OWNER[/REPO]` takes the same form.
- `fetch USER` checks with gh that the copy exists, adds it and fetches it.
  `fetch` also takes a comma-separated list of users and remotes.
- `compare OWNER RANGE` opens the comparison on OWNER's copy.
- In `pull-request`, `-b OWNER:BASE` names the base branch in OWNER's copy,
  and `-h OWNER:HEAD` names the branch with the changes.

In `remote`, a single word adds a copy of the project:

```sh
hub --noop remote add USER
# => git remote add USER https://github.com/USER/REPO.git
hub --noop remote add origin
# => git remote add origin https://github.com/LOGIN/REPO.git
hub --noop remote add upstream rails/rails
# => git remote add upstream https://github.com/rails/rails.git
hub --noop remote set-url upstream rails/rails
# => git remote set-url upstream https://github.com/rails/rails.git
```

When USER has a copy of the project, `fetch` adds it first:

```sh
hub --noop fetch --prune USER,origin
# => git remote add USER https://github.com/USER/REPO.git
# => git fetch --multiple --prune USER origin
```

If gh finds no USER/REPO, hub runs no git command and stops with this message:

```text
hub fetch: USER is not a remote, and github.com/USER/REPO does not exist
```

`compare` turns git's two-dot range into GitHub's three-dot range, so the
page shows the commits that v2 adds. In `pull-request`, `-b` and `-h` take an
owner before the branch:

```sh
hub compare -u USER v1..v2
# => https://github.com/USER/REPO/compare/v1...v2
hub --noop pull-request -b OWNER:main -h USER:feature -m 'Fix the bug'
# => gh pr create --repo github.com/OWNER/REPO --base main --head USER:feature --title Fix\ the\ bug --body ''
```

## Use HOST/OWNER/REPO and GitHub Enterprise

`HOST/OWNER/REPO` names a repository on another host. The first part counts
as a host when it has a dot, or when it is `GH_HOST` or a host gh is logged in
to. Otherwise hub does not read the word as a repository. hub writes the host
in lowercase. `browse`, `create` and `delete` take this form. So does the
`GH_REPO` environment variable, which names the repository that hub uses
instead of the project. See [Configuration](configuration.md).

For `hub browse cli/cli/issues`, `cli` is not a host, so hub stops with this
message:

```text
hub browse: not a repository: cli/cli/issues (use REPO, OWNER/REPO, HOST/OWNER/REPO or a repository URL)
```

`clone` hands `HOST/OWNER/REPO` to git as a path, so set `GH_HOST` or give the
URL. On a GitHub Enterprise Cloud host such as `acme.ghe.com`, the ssh user is
the first part of the host name (`acme`), not `git`. `-p` clones over ssh
instead of https:

```sh
hub browse -u GHE.Example.com/octo-org/site
# => https://ghe.example.com/octo-org/site
GH_HOST=ghe.example.com hub --noop clone octo-org/site
# => git clone https://ghe.example.com/octo-org/site.git
GH_HOST=acme.ghe.com hub --noop clone -p octo-org/site
# => git clone acme@acme.ghe.com:octo-org/site.git
```

## Give a repository URL

Where a command takes `HOST/OWNER/REPO`, it also takes a repository URL. hub
reads the same URLs in your remotes to find the project. The schemes are
`https`, `http`, `git`, `ssh`, `git+ssh` and `ssh+git`, plus the scp-like
`git@github.com:cli/cli.git`, with no `/` before the first colon.

hub reads the host, the owner and the repository name. It writes the host in
lowercase, and drops the user, the password, the port, a trailing `/` and
`.git`. The host must be github.com, `GH_HOST` or a host gh is logged in to.
Over ssh, `ssh.github.com` is github.com. For any other ssh host, hub asks
`ssh -G` once for its `HostName`, so an ssh alias for github.com works.

Each command reads the URL's repository:

```sh
hub browse -u git@github.com:cli/cli.git issues
# => https://github.com/cli/cli/issues
hub --noop create --remote-name site https://github.com/octo-org/site.git
# => gh repo create github.com/octo-org/site --private
# => git remote add -- site https://github.com/octo-org/site.git
GH_HOST=ghe.example.com hub browse -u https://ghe.example.com:8443/octo-org/site
# => https://ghe.example.com/octo-org/site
```

`hub create` makes a private repository unless you pass `--public` or
`--internal`. `--remote-name site` names the new remote `site`. Because hub
drops the port, web and API URLs of a GitHub Enterprise host always use the
standard port.

A URL with a query, a fragment or more path is not a repository URL, nor is
`file://`, another host such as gitlab.com, or `https://ssh.github.com`.

## Give a pull request, commit or compare URL

Five git commands hub extends take the `http` or `https` web URL of a pull
request, a commit or a comparison, on a known host. hub never reads a word
with a space or a control character as a URL. In the table, `SHA` is a commit
id of 4 to 64 hex digits and `N` is the pull request number.

| URL | checkout | merge | am, apply | cherry-pick |
|---|---|---|---|---|
| `.../pull/N`, `.../pull/N/files`, `.../pull/N/commits` | yes | yes | yes | no |
| `.../pull/N.patch`, `.../pull/N.diff` | yes | no | yes | no |
| `.../pull/N/commits/SHA` | yes | no | yes | yes |
| `.../pull/N/files/SHA` | yes | no | no | no |
| `.../commit/SHA` | no | no | yes | yes |
| `.../compare/BASE...HEAD` | no | no | yes | no |

`checkout` takes any page of a pull request. `merge` takes only the whole
pull request. hub passes any other URL to git unchanged, and git then refuses
it because the URL is not a branch or commit. `am` and `apply` download the
patch through `gh api`, with or without a `.patch` or `.diff` suffix. hub does
not read a two-dot `compare/A..B` URL. It passes the URL to git unchanged.

Each command turns the URL into gh and git commands:

```sh
hub --noop checkout https://github.com/rails/rails/pull/42 review
# => gh pr checkout https://github.com/rails/rails/pull/42 -b review
hub --noop am -3 https://github.com/cli/cli/pull/55
# => git am -3 TMPDIR/hub-am.XXXXXX/1.patch
hub --noop cherry-pick https://github.com/cli/cli/commit/9490d20
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/cli/cli.git FULL-SHA
# => git cherry-pick FULL-SHA
hub --noop merge https://github.com/rails/rails/pull/42/commits/abc1234
# => git merge https://github.com/rails/rails/pull/42/commits/abc1234
```

For `am`, hub downloads the patch with `gh api` to a temporary file under
`TMPDIR`, and runs `git am` on it. For a commit URL, hub asks gh for the full
commit id (`FULL-SHA`), fetches that commit and cherry-picks it. Both `gh api`
calls run even under `--noop`, which prints only the git lines.

hub does not read gist URLs. Clone the gist with gh, then run `hub am` or
`hub apply` on the file:

```sh
gh gist clone ID
hub am ID/FILE
```

hub does not read the `USER@SHA` form of the original hub (mislav/hub 2.x).
Give the commit's URL instead.

## Know what hub leaves to git

In the git commands hub extends, hub passes any other word to git unchanged.
A path, or a name git reads as a local repository, is not a shorthand. Write
`./NAME` to clone a local repository named like one. In `remote` and `fetch`,
hub passes a word unchanged when git rewrites it through
`url.BASE.insteadOf`. A `pushInsteadOf` rule does not count. hub also passes
a URL or `host:path` word unchanged in `clone`, `remote` and `fetch`.

A path, a rewritten word and a URL reach git as typed:

```sh
hub --noop clone ./rails
# => git clone ./rails
git config url.https://github.com/rails/rails.git.insteadOf rails-upstream
hub --noop remote add up rails-upstream
# => git remote add up rails-upstream
hub --noop fetch git@github.com:rails/rails.git
# => git fetch git@github.com:rails/rails.git
```

`hub push REMOTE,REMOTE BRANCH` pushes the branch to each remote in turn, and
a remote, path or URL that contains a comma stays one destination. See
[hub push](../commands/push.md).

```sh
hub --noop push origin,staging feature
# => git push origin feature
# => git push staging feature
```

## Look up the forms a command accepts

| Command | Forms |
|---|---|
| [clone](../commands/clone.md) | `OWNER/REPO`, `REPO` (yours), `.wiki` and `.git` suffixes |
| [remote](../commands/remote.md) | `add NAME OWNER[/REPO]`, `add USER`, `add origin`, `set-url NAME OWNER[/REPO]` |
| [fetch](../commands/fetch.md) | `USER`, `USER,USER...` (users and remotes) |
| [push](../commands/push.md) | `REMOTE,REMOTE...` |
| [browse](../commands/browse.md) | `REPO` (yours), `OWNER/REPO`, `HOST/OWNER/REPO`, repository URL |
| [create](../commands/create.md) | `NAME` (yours), `OWNER/NAME`, `HOST/OWNER/NAME`, repository URL |
| [delete](../commands/delete.md) | `NAME` (yours), `OWNER/NAME`, `HOST/OWNER/NAME`, repository URL |
| [compare](../commands/compare.md) | `OWNER` before the range |
| [pull-request](../commands/pull-request.md) | `-b [OWNER[/REPO]:]BASE`, `-h [OWNER:]HEAD` |
| [checkout](../commands/checkout.md) | pull request URL, any page |
| [merge](../commands/merge.md) | pull request URL, the pull request as a whole |
| [am](../commands/am.md), [apply](../commands/apply.md) | pull request, commit and three-dot compare URLs |
| [cherry-pick](../commands/cherry-pick.md) | `.../commit/SHA`, `.../pull/N/commits/SHA` |
| `GH_REPO` | `OWNER/REPO`, `HOST/OWNER/REPO`, repository URL |

## See also

- [hub clone](../commands/clone.md)
- [hub fetch](../commands/fetch.md)
- [hub push](../commands/push.md)
- [Project and remotes](project-and-remotes.md)
- [Hosts and login](hosts-and-login.md)
- [Configuration](configuration.md)
- [Coming from the original hub](../compatibility/README.md)
