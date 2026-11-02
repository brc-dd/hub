---
title: Hosts and login
description: github.com, GitHub Enterprise, GH_HOST and GITHUB_HOST, gh auth, tokens and your login.
---

# Hosts and login

This page is for anyone who uses hub with more than one GitHub account or host,
or with a token. It explains which host a shorthand such as `rails/rails` goes
to, how hub learns your login, and how to work with GitHub Enterprise. hub has
no login, token or host list of its own: it uses those of GitHub CLI (gh). The
examples use `hub` and run in a clone of OWNER/REPO. With the
[alias](../getting-started/alias.md), `git` runs the same commands.

## Log in with gh

Log in to each host once with `gh auth login`. Add `-h HOST` for a GitHub
Enterprise host. gh stores the token, and hub reads the hosts and your login
from gh. hub writes no token, login or host to any file, and it reads no
setting of the original hub (mislav/hub 2.x) such as `hub.host`: use
`gh auth login -h HOST` and `GH_HOST` instead. See
[Configuration](configuration.md) for the original hub's settings.

```sh
gh auth login
gh auth login -h ghe.example.com
gh auth status
```

`gh auth status` shows each host and its account. If hub cannot learn your
login for a host, it stops and names the command to run:

```text
hub clone: could not determine your GitHub login for github.com (run: gh auth login -h github.com)
```

## Choose the default host

A shorthand is a repository name without a host, such as `OWNER/REPO` or
`REPO` (see [Repositories and URLs](repositories-and-urls.md)). hub sends a
shorthand to the default host. `hub remote` and `hub fetch` are the exception:
they use the project's host, and the default host only when there is no
project. See [Project and remotes](project-and-remotes.md#find-the-project).
To pick the default host, hub takes the first of these that applies:

1. `GH_HOST`, when it is set.
2. `GITHUB_HOST`, the original hub's name, when `GH_HOST` is not set. hub
   exports it as `GH_HOST`, so the gh commands that hub starts see it too.
3. The one host gh is logged in to, when there is exactly one.
4. github.com in every other case, including when gh is logged in to two or
   more hosts.

`hub --noop` prints the git and gh commands that change something instead of
running them. With gh logged in to github.com only, or to no host:

```sh
hub --noop clone rails/rails
# => git clone https://github.com/rails/rails.git
GH_HOST=ghe.example.com hub --noop clone OWNER/REPO
# => git clone https://ghe.example.com/OWNER/REPO.git
GITHUB_HOST=ghe.example.com hub --noop clone OWNER/REPO
# => git clone https://ghe.example.com/OWNER/REPO.git
```

If gh is logged in only to ghe.example.com, hub uses that host:

```sh
hub --noop clone OWNER/REPO
# => git clone https://ghe.example.com/OWNER/REPO.git
```

hub writes the host in lowercase:

```sh
GH_HOST=GHE.Example.com hub --noop clone OWNER/REPO
# => git clone https://ghe.example.com/OWNER/REPO.git
```

A `GH_HOST` that is not a host name is an error:

```sh
GH_HOST='a b' hub --noop clone OWNER/REPO
# hub clone: not a host name: a\ b
```

The default host applies only to shorthands. A remote URL or a repository URL
names its own host. hub treats a remote as a GitHub remote only when its host
is github.com, `GH_HOST` or a host gh is logged in to. hub ignores other
remotes when it looks for the project or your fork. In a repository whose only
remote is `origin` at `https://gitlab.com/OWNER/REPO.git`:

```sh
hub --noop browse -u
# hub browse: no GitHub remote found (looked for upstream, github, origin)
```

See [Repositories and URLs](repositories-and-urls.md) for every form hub
accepts.

## Use a token

gh reads a token from these variables:

| Host | Variables |
|---|---|
| github.com and `*.ghe.com` | `GH_TOKEN`, `GITHUB_TOKEN` |
| GitHub Enterprise Server | `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN` |

A token in these variables takes precedence over the account that gh stored.
See `gh help environment` for gh's rules.

When any of the four variables is set, hub asks GitHub whose token it is
(`gh api --hostname HOST user --jq .login`) and does not read gh's stored
login. The token can belong to a different account from the one that gh
stored. When no variable is set, hub reads the stored login with
`gh config get user -h HOST`. hub never falls back from one way to the other.

With a token for github.com set:

```sh
GH_TOKEN=TOKEN hub --noop clone REPO
# => git clone https://github.com/LOGIN/REPO.git
```

hub learns LOGIN from `gh api --hostname github.com user --jq .login`. The
query runs under `--noop` because it changes nothing.

## Work with GitHub Enterprise

Log in with `gh auth login -h HOST`, then pick one of these:

- Set `GH_HOST` so that shorthands go to the host.
- Put the host in front: `HOST/OWNER/REPO` works where hub reads a repository
  name, for example in `browse`, `delete` and `GH_REPO`.
- Give a URL, such as `https://ghe.example.com/OWNER/REPO.git`.

With the host in front of the name:

```sh
hub --noop browse -u ghe.example.com/OWNER/REPO
# => https://ghe.example.com/OWNER/REPO
GH_REPO=ghe.example.com/OWNER/REPO hub --noop fork
# => gh api --hostname ghe.example.com --method POST repos/OWNER/REPO/forks --jq .full_name
# => git remote add -- LOGIN https://ghe.example.com/LOGIN/REPO.git
```

hub passes `hub clone HOST/OWNER/REPO` to git unchanged, because git can read
that word as a path. Set `GH_HOST` or give the URL instead:

```sh
GH_HOST=ghe.example.com hub --noop clone OWNER/REPO
# => git clone https://ghe.example.com/OWNER/REPO.git
```

hub uses gh's `git_protocol` for the host, else https. To use ssh, run:

```sh
gh config set git_protocol ssh -h HOST
```

On a GitHub Enterprise Cloud host (a host under `ghe.com`, such as
`acme.ghe.com`), the ssh user is the first part of the host name, not `git`.
With `git_protocol` set to `ssh` for acme.ghe.com:

```sh
GH_HOST=acme.ghe.com hub --noop clone OWNER/REPO
# => git clone acme@acme.ghe.com:OWNER/REPO.git
```

## Know when hub needs your login

hub asks gh for your login on the host only when a command needs it:

- `REPO` alone in `clone`, `browse`, `create` and `delete`.
- `hub remote add origin`.
- The name of the remote that `hub fork` adds.
- Your fork as the remote a branch pushes to in `pull-request`, `compare` and
  `browse`.

With gh logged in as LOGIN on github.com:

```sh
hub --noop clone REPO
# => git clone https://github.com/LOGIN/REPO.git
hub --noop remote add origin
# => git remote add origin https://github.com/LOGIN/REPO.git
hub --noop fork
# => gh api --hostname github.com --method POST repos/OWNER/REPO/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/REPO.git
```

hub looks for your fork by your login when no git setting names the push
remote, the branch has no upstream of its own name, and there is more than one
remote. On a branch `feature`, with your fork as the remote `LOGIN`,
`-p` pushes the branch first:

```sh
hub --noop pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- LOGIN HEAD:refs/heads/feature
# => gh pr create --repo github.com/OWNER/REPO --head LOGIN:feature --title Fix\ the\ bug --body ''
```

See [Project and remotes](project-and-remotes.md#find-where-a-branch-pushes)
for the full order.

## See also

- [hub clone](../commands/clone.md)
- [hub fork](../commands/fork.md)
- [hub pull-request](../commands/pull-request.md)
- [Repositories and URLs](repositories-and-urls.md)
- [Project and remotes](project-and-remotes.md)
- [Configuration](configuration.md)
- [Coming from the original hub](../compatibility/README.md)
- [gh auth login](https://cli.github.com/manual/gh_auth_login)
- [gh help environment](https://cli.github.com/manual/gh_help_environment)
