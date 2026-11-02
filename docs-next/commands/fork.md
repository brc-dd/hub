---
title: hub fork
description: Fork the project on GitHub and add the fork as a remote.
kind: hub's own command
original: https://hub.github.com/hub-fork.1.html
---

# hub fork

`hub fork` forks the current project on GitHub, under your account or an
organization, and adds the fork as a remote. hub runs `gh api` against
GitHub's fork API, then `git remote add`. Use it in a clone of a project that
you want to change but cannot push to. The most common use is `hub fork` in a
fresh clone, which forks the project under your login and adds the remote
`LOGIN`:

```sh
hub fork
# => gh api --hostname github.com --method POST repos/rails/rails/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/rails.git
```

## Usage

```text
hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME]
         [--default-branch-only] [ORG]
```

`ORG` is an organization to fork into. It means the same as `--org ORG`.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md), `git fork`
is the same command. Each `# =>` line is what `hub --noop` prints: the git or
gh command that hub runs. The examples run in a clone whose `origin` points at
rails/rails, and `LOGIN` stands for your GitHub login. When it succeeds,
`hub fork` prints nothing, except with `--no-remote`, which prints the fork's
`OWNER/NAME`.

Fork the project that `origin` points at:

```sh
hub fork
# => gh api --hostname github.com --method POST repos/rails/rails/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/rails.git
```

Fetch the fork, then push a branch to it and open a pull request:

```sh
hub fork
git fetch LOGIN
git push -u LOGIN BRANCH
hub pull-request
```

hub does not fetch the fork. GitHub makes the fork in the background, which can
take a few seconds. If `git fetch LOGIN` fails because the fork does not exist
yet, wait and run it again.

Fork into an organization. The operand and the option do the same thing, and
the remote is named after the organization:

```sh
hub fork acme
hub fork --org acme
# => gh api --hostname github.com --method POST repos/rails/rails/forks -f organization=acme --jq .full_name
# => git remote add -- acme https://github.com/acme/rails.git
```

Choose the remote name:

```sh
hub fork --remote-name mine
# => gh api --hostname github.com --method POST repos/rails/rails/forks --jq .full_name
# => git remote add -- mine https://github.com/LOGIN/rails.git
```

Give the fork another name on GitHub and copy only the default branch:

```sh
hub fork --fork-name rails-docs --default-branch-only
# => gh api --hostname github.com --method POST repos/rails/rails/forks -f name=rails-docs -F default_branch_only=true --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/rails-docs.git
```

Combine the options. The remote name comes from `--remote-name`, not from the
organization:

```sh
hub fork --org acme --fork-name rails-ci --remote-name ci
# => gh api --hostname github.com --method POST repos/rails/rails/forks -f organization=acme -f name=rails-ci --jq .full_name
# => git remote add -- ci https://github.com/acme/rails-ci.git
```

Fork without adding a remote. hub hands the call to gh, which prints the
fork's `OWNER/NAME`:

```sh
hub fork --no-remote
# => gh api --hostname github.com --method POST repos/rails/rails/forks --jq .full_name
```

```text
LOGIN/rails
```

Fork the project that `upstream` points at. In a clone where `origin` is
OWNER/rails and `upstream` is rails/rails, hub forks rails/rails:

```sh
hub fork
# => gh api --hostname github.com --method POST repos/rails/rails/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/rails.git
```

Fork a project from outside any clone. Set `GH_REPO` to the project, as
[Configuration](../guide/configuration.md) describes, and pass `--no-remote`.
This forks cli/cli into the organization acme and prints the fork's
`OWNER/NAME`:

```sh
GH_REPO=cli/cli hub fork --no-remote acme
# => gh api --hostname github.com --method POST repos/cli/cli/forks -f organization=acme --jq .full_name
```

Fork a project on GitHub Enterprise. Set `GH_REPO` to `HOST/OWNER/REPO`, as
[Repositories and URLs](../guide/repositories-and-urls.md) describes:

```sh
GH_REPO=ghe.example.com/corp/app hub fork
# => gh api --hostname ghe.example.com --method POST repos/corp/app/forks --jq .full_name
# => git remote add -- LOGIN https://ghe.example.com/LOGIN/app.git
```

Get an ssh remote. The URL follows gh's `git_protocol` setting for the host:

```sh
gh config set git_protocol ssh
hub fork
# => gh api --hostname github.com --method POST repos/rails/rails/forks --jq .full_name
# => git remote add -- LOGIN git@github.com:LOGIN/rails.git
```

Reuse a fork that already exists. Suppose that you forked rails/rails earlier
and named the fork `rails-1`. GitHub answers with that fork even when you pass
`--fork-name`:

```sh
hub fork --fork-name rails-docs
# => gh api --hostname github.com --method POST repos/rails/rails/forks -f name=rails-docs --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/rails-docs.git
```

A real run adds `https://github.com/LOGIN/rails-1.git`, the fork GitHub
answered with. Under `--noop`, hub does not ask GitHub, so the remote URL uses
the name that you gave or the project's name.

If a remote already has the name, hub stops before it forks:

```sh
hub fork --remote-name origin
```

```text
hub fork: remote already exists: origin (name another with --remote-name NAME)
```

Run the command again with a free name, for example `--remote-name mine`.

## Options

| Option | What it does |
|---|---|
| `--no-remote` | Fork without adding a remote, and print the fork's `OWNER/NAME`. Cannot go with `--remote-name`. |
| `--remote-name NAME` | Name the new remote `NAME`. Default: the organization, else your login. |
| `--org ORG` | Fork into the organization `ORG`. An `ORG` operand means the same. Default: your account. |
| `--fork-name NAME` | Name the fork `NAME` on GitHub. Default: the project's name. |
| `--default-branch-only` | Copy only the default branch into the fork. |

These are all the options. Any other option is a usage error, and `-h` or
`--help` prints the manual. An option that takes a value also accepts the
`--option=VALUE` form, for example `--org=acme`.

## How it works

hub applies these rules in order:

1. hub checks the command line. An empty `--org`, `--fork-name` or `ORG`, a
   second operand, or an `ORG` operand that differs from `--org` (ignoring
   case) is a usage error.
2. hub needs gh on `PATH`. hub also needs a git repository, unless you pass
   `--no-remote` and set `GH_REPO`.
3. hub finds the project: `GH_REPO`, else the first GitHub remote among
   `upstream`, `github` and `origin`, then the others. See
   [The project and its remotes](../guide/project-and-remotes.md).
4. With `--no-remote`, hub hands the API call to gh and stops there.
5. hub picks the remote name: `--remote-name`, else the organization, else
   your login from gh. See [Hosts and login](../guide/hosts-and-login.md).
6. hub checks the remote name before gh forks. The name must be a valid remote
   name that does not start with `-`. No existing remote may have the same
   name, even in other letter case. On a case-insensitive file system, remotes
   that differ only in case share their refs.
7. hub sends `POST repos/OWNER/REPO/forks` with `gh api`, adding the fields
   `organization`, `name` and `default_branch_only` for the options you gave.
   hub does not check organization or fork names. GitHub judges them, and gh
   reports what GitHub says.
8. hub reads the fork's `OWNER/NAME` from GitHub's answer, new or existing,
   and runs `git remote add` with that fork's URL. The URL is https, or ssh
   when gh's `git_protocol` is `ssh` for the host. hub fetches nothing.

## Exit status

`hub fork` exits 0 when it succeeds. When gh fails, hub prints gh's message,
exits with gh's status and adds no remote. A usage error exits with status 1.
hub's own refusals exit with status 1 and stop `hub fork` before it changes
anything:

| Message | What to do |
|---|---|
| `hub fork: remote already exists: NAME (name another with --remote-name NAME)` | Pass `--remote-name` with a free name. |
| `hub fork: not a remote name: NAME` | Pass a valid remote name with `--remote-name`. If the organization's name is not a valid remote name, pass `--remote-name` too. |
| `hub fork: --no-remote adds no remote to name (drop --remote-name)` | Leave out one of the two options. |
| `hub fork: two organizations: --org acme and other (name one)` | Give the organization once. |
| `hub fork: no GitHub remote found (looked for upstream, github, origin)` | Add a GitHub remote, or set `GH_REPO`. |
| `hub fork: could not determine your GitHub login for github.com (run: gh auth login -h github.com)` | Log in to gh for the host. |
| `hub fork: this command needs the GitHub CLI, gh (https://cli.github.com)` | Install gh. |

If GitHub answers without a fork name, hub adds no remote. It stops with
`GitHub did not name the fork`, and the message says to add the remote with
`git remote add`.

## Differences from the original hub

The original hub (mislav/hub 2.x) had three options, and they keep their names
and meanings.

| Original hub | This hub |
|---|---|
| `hub fork [--no-remote] [--remote-name REMOTE] [--org ORGANIZATION]` | Same options, plus `--fork-name`, `--default-branch-only` and an `ORG` operand. |
| Added the remote with the parent's URL and fetched it (`git remote add -f`), then set the URL to the fork. | Adds the fork's URL and fetches nothing. Run `git fetch NAME` once the fork exists. |
| Printed `new remote: NAME`. | Prints nothing on success. |
| `--no-remote` printed nothing. | `--no-remote` prints the fork's `OWNER/NAME`. |
| `--remote-name origin` renamed the existing `origin` to `upstream`. | Refuses: `remote already exists: origin`. Run `git remote rename origin upstream` first. |
| If you already had a fork, it sent no fork request and added the remote. If the remote existed too, it printed `existing remote: NAME` and exited 0. | hub sends the fork request, and GitHub answers with the existing fork under its own name. If the remote exists, hub stops before the fork request and exits 1. |
| Left a remote name taken by another URL to git, which printed `remote NAME already exists.` | hub refuses before the fork request, also for a name that differs only in case. |
| Printed API errors as `Error creating fork: ... (HTTP 500)`. | gh's message and exit status, unchanged. |
| Took the URL protocol from `hub.protocol` or `HUB_PROTOCOL`. | Not read. The URL follows gh's `git_protocol`. Run `gh config set git_protocol ssh`. |
| Took the project from the `upstream`, `github` or `origin` remote. | Same, and `GH_REPO` can name the project. `--no-remote` with `GH_REPO` works outside a repository. |
| `--noop` skipped the fork request. | `--noop` prints the `gh api` and `git remote add` lines. |
| Used its own login and token for the API. | gh's login. Run `gh auth login`, or set `GH_TOKEN`. |

## See also

- [hub create](create.md): to make a new repository and add it as `origin`.
- [hub fetch](fetch.md), [hub push](push.md) and [hub remote](remote.md): to
  work with the fork's remote.
- [hub pull-request](pull-request.md): to open a pull request from the fork.
- [The project and its remotes](../guide/project-and-remotes.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [Configuration](../guide/configuration.md), for `GH_REPO` and `GH_HOST`
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-fork(1)](https://hub.github.com/hub-fork.1.html)
- gh's manual: [gh repo fork](https://cli.github.com/manual/gh_repo_fork), for
  gh's own fork options
- This hub's manual: [hub fork](https://brc-dd.github.io/hub/fork.html)
