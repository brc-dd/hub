---
title: hub ci-status
description: Show the CI status of a commit.
kind: hub's own command
original: https://hub.github.com/hub-ci-status.1.html
---

# hub ci-status

`hub ci-status` prints GitHub's combined verdict on the checks and commit
statuses of a commit in the current [project](../guide/project-and-remotes.md):
`success`, `failure`, `error`, `pending` or `no status`. hub runs
`gh api graphql` of the GitHub CLI (gh), and its exit status follows the
verdict. Use it before you open a pull request, after you push, or in a script
that waits for CI. The most common use is `hub ci-status`, which checks the
current commit.

```sh
hub ci-status
# => success
```

## Usage

```text
hub ci-status [-v] [COMMIT]
```

`COMMIT` is the commit to ask about, `HEAD` by default: a name that git
resolves, such as a branch, a tag or `HEAD~2`, or a name that only GitHub has.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git ci-status` is the same command. Each `# =>` line is what hub prints, also
under `hub --noop`, which runs the query because it changes nothing. Each
`# runs:` line is the query that hub sends through gh, shortened with `...`.
The examples run in a clone of OWNER/REPO on github.com.

Check the current commit:

```sh
hub ci-status
# runs: gh api graphql --hostname github.com -f query=... -f owner=OWNER -f name=REPO -f expr=SHA --jq ...
# => success
```

git resolves `HEAD` to its SHA, and hub runs one GraphQL query. The exit
status is 0.

Wait for CI in a script, while the exit status is 2 for pending:

```sh
while hub ci-status >/dev/null; [ $? -eq 2 ]; do sleep 30; done
hub ci-status
# => failure
```

The loop ends at the first verdict that is not pending. The last command
prints it and exits 0 for `success`, 1 for `failure` or `error`, and 3 for
`no status`.

List every check, with its state, name and URL separated by tabs:

```sh
hub ci-status -v main
# => failure	lint	https://github.com/OWNER/REPO/actions/runs/1/job/2
# => success	build	https://github.com/OWNER/REPO/actions/runs/1/job/3
```

Failures come first, then pending checks, then the rest, each group sorted by
name byte by byte, so capital letters come first. A check without a URL ends
with an empty field. A commit with no check prints nothing, and the exit status
is still the verdict's.

Check a branch or a tag:

```sh
hub ci-status topic
hub ci-status v1.0
```

git resolves the name to a commit, and follows a tag to the commit it names.

Check a branch that only GitHub has:

```sh
hub ci-status feature/only-on-github
# runs: gh api graphql ... -f expr=feature/only-on-github --jq ...
# => pending
```

A name that git cannot resolve goes to GitHub unchanged.

Check a commit name that starts with a dash, after `--`:

```sh
hub ci-status -- --all
# runs: gh api graphql ... -f expr=--all --jq ...
```

Check a repository you have not cloned, outside a repository:

```sh
GH_REPO=cli/cli hub ci-status
# runs: gh api graphql --hostname github.com -f query=... -f owner=cli -f name=cli -f expr=HEAD --jq ...
```

`HEAD` goes to GitHub unchanged, and GitHub reads it as the default branch.

Check a GitHub Enterprise repository, here in a clone of
`https://ghe.example.test/acme/tools.git`:

```sh
GH_HOST=ghe.example.test hub ci-status
# runs: gh api graphql --hostname ghe.example.test -f query=... -f owner=acme -f name=tools ...
# => success
```

hub asks the host of the project's remote. Set `GH_HOST` when gh is not logged
in to that host.

Ask about a commit that GitHub does not have:

```sh
hub ci-status nosuch
```

```text
hub ci-status: nosuch is not a commit of github.com/OWNER/REPO
```

A commit that is not pushed gets the same message, as does a tree name such as
`main:docs`.

Ask about a `HEAD` name that does not resolve:

```sh
hub ci-status HEAD~1
hub ci-status '@{upstream}'
```

```text
hub ci-status: HEAD~1 is not a commit in this repository
hub ci-status: @{upstream} is not a commit in this repository
```

GitHub would read such a name as its default branch, so hub refuses it and
does not ask GitHub. A name such as `HEADLESS` goes to GitHub unchanged.

## Options

| Option | What it does |
|---|---|
| `-v`, `--verbose` | Print the state, name and URL of every check (the first 100) instead of the verdict: failures first, then pending ones, then the rest. Print nothing when there is no check. |

These are all the options. Any other option is a usage error, and `-h` or
`--help` prints the manual.

## How it works

hub applies these rules in order:

1. hub reads the options and at most one `COMMIT`. A second commit or an empty
   one is a usage error.
2. hub finds the project: `GH_REPO` when it is set, else the GitHub repository
   of a remote. See
   [The project and its remotes](../guide/project-and-remotes.md).
3. hub needs gh, logged in to the project's host. See
   [Hosts and login](../guide/hosts-and-login.md).
4. git resolves `COMMIT` to a commit SHA. If git cannot, and the name is `HEAD`
   or `@`, alone or followed by `~`, `^`, `@`, `{` or `:`, hub refuses it
   inside a repository. This covers `HEAD~1`, `@{upstream}` and `HEAD` on a new
   branch with no commit yet. hub sends any other name to GitHub unchanged.
5. hub sends one GraphQL query through `gh api graphql` for the commit's status
   check rollup: GitHub's combined state and the first 100 checks and commit
   statuses.
6. hub prints GitHub's state in lowercase. GitHub's `EXPECTED` state prints as
   `pending`, and a commit with no checks and no statuses prints `no status`.
7. With `-v`, hub prints the checks instead. A finished check shows its
   conclusion (`success`, `neutral`, `skipped`, `cancelled` and others), an
   unfinished one its status (`queued`, `in_progress` and others).

In the `-v` list, hub ranks `failure`, `error`, `cancelled`, `timed_out`,
`action_required`, `startup_failure` and `stale` as failures. It ranks
`pending`, `expected`, `queued`, `in_progress`, `waiting` and `requested` as
pending. The verdict itself is always GitHub's.

`hub --noop ci-status` runs the query too, because it changes nothing. See
[How hub works](../guide/how-hub-works.md).

## Exit status

| Status | When |
|---|---|
| 0 | `success` |
| 1 | `failure` or `error`. Also a refusal of hub's or a failed gh call. |
| 2 | `pending` |
| 3 | `no status` |

hub's own refusals exit with status 1. If gh fails, for example because the
repository does not exist or the token cannot read check runs, gh's own message
reaches you and hub exits 1. The first three messages are followed by the line
`Usage: hub ci-status [-v] [COMMIT]`.

| Message | What to do |
|---|---|
| `hub ci-status: unknown option: --verbose=1` | Use `-v` or `--verbose`, without a value. |
| `hub ci-status: unexpected argument: topic` | Name one commit. |
| `hub ci-status: empty commit` | Name a commit, or leave `COMMIT` out. |
| `hub ci-status: no GitHub remote found (looked for upstream, github, origin)` | Add a GitHub remote, or set `GH_REPO`. |
| `hub ci-status: this command needs the GitHub CLI, gh (https://cli.github.com)` | Install gh. |
| `hub ci-status: HEAD~1 is not a commit in this repository` | Name a commit that exists here. On a new branch, commit first. |
| `hub ci-status: nosuch is not a commit of github.com/OWNER/REPO` | Push the commit, or check its name. |

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub ci-status [-v] [COMMIT]` | Same. |
| hub ranked the states itself: `neutral` counted as success, and `action_required`, `cancelled` and `timed_out` as failure. | hub prints GitHub's combined verdict and does not rank the states itself. |
| Exit 0 success, 1 failure or error, 2 pending, 3 no status. | Same. 1 also covers a failed gh call, a missing remote or gh, and a commit that git or GitHub does not have. |
| `-v` printed an icon (✔︎, ✖︎, ●), the name padded to the longest name, and the URL. | `-v` prints the state word, the name and the URL, separated by tabs, for the first 100 checks. Within each group the lines are in name order. |
| `-f`, `--format FORMAT` took `%U`, `%S`, `%sC` and `%t`. | Not supported. Use `gh pr checks` with `--json` and `--jq` for a pull request's checks. |
| `--color[=WHEN]` colored the output. | Not supported. Use `gh pr checks` for a colored view. |
| hub read statuses and check runs in two lookups, and statuses only on an older GitHub Enterprise without checks. | One GraphQL query. A token that cannot read check runs gets gh's error. |
| An unknown name stopped with `Aborted: no revision could be determined from 'NAME'`. | A name git does not know goes to GitHub, except a `HEAD` or `@` name inside a repository: `hub ci-status: NAME is not a commit in this repository`. If GitHub has no such commit: `hub ci-status: NAME is not a commit of HOST/OWNER/REPO`. |
| No GitHub remote stopped with `Aborted: could not find any git remote pointing to a GitHub repository`. | `hub ci-status: no GitHub remote found (looked for upstream, github, origin)`. |
| hub ignored a git alias named `ci-status`. | Same. hub runs its own command and ignores the alias. |
| hub used its own login and token. | gh's login, through `gh api`. See [Hosts and login](../guide/hosts-and-login.md). |

## See also

- [hub pull-request](pull-request.md): open a pull request once CI passes.
- [hub sync](sync.md): bring your branches up to date.
- [hub browse](browse.md): open the project on GitHub.
- [The project and its remotes](../guide/project-and-remotes.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-ci-status(1)](https://hub.github.com/hub-ci-status.1.html)
- gh's manual: [gh pr checks](https://cli.github.com/manual/gh_pr_checks)
- This hub's manual:
  [hub ci-status](https://brc-dd.github.io/hub/ci-status.html)
