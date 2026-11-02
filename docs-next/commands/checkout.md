---
title: hub checkout
description: Check out a pull request, or run git checkout.
kind: git command hub extends
original: https://hub.github.com/hub-checkout.1.html
---

# hub checkout

`hub checkout` checks out a pull request in a local branch. It is
`git checkout` with one addition: it also accepts a pull request URL, and then
hub runs `gh pr checkout` of the GitHub CLI (gh), which fetches the pull
request and creates the branch. A command line without one goes to
`git checkout` unchanged. The most common use is `hub checkout URL`, which
checks out a pull request you have open in the browser to review it.

```sh
hub checkout https://github.com/rails/rails/pull/42
# => gh pr checkout https://github.com/rails/rails/pull/42
```

## Usage

```text
hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULL-REQUEST-URL [BRANCH]
hub checkout GIT-CHECKOUT-ARGS...
```

`PULL-REQUEST-URL` is the URL of a pull request, or of any page of it, on
GitHub.com, on the host in `GH_HOST`, or on a host gh is logged in to.
`BRANCH` is the name of the local branch, the same as `-b BRANCH`. Without it,
gh chooses the name. `GIT-CHECKOUT-ARGS` is anything `git checkout` takes.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git checkout` is the same command. Each `# =>` line is what `hub --noop`
prints: the git or gh command that hub runs.

Check out a pull request in a branch named `review`. The `BRANCH` operand and
`-b` do the same thing:

```sh
hub checkout https://github.com/rails/rails/pull/42 review
# => gh pr checkout https://github.com/rails/rails/pull/42 -b review
hub checkout -b review https://github.com/rails/rails/pull/42
# => gh pr checkout https://github.com/rails/rails/pull/42 -b review
```

Paste the URL of whatever page of the pull request you have open. The files
tab, a commit, the `.patch` and `.diff` forms, and a URL with a query (`?w=1`)
or a fragment (`#discussion`) all work. hub passes the URL to gh as you wrote
it:

```sh
hub checkout -b review https://github.com/rails/rails/pull/42/files
# => gh pr checkout https://github.com/rails/rails/pull/42/files -b review
hub checkout https://github.com/rails/rails/pull/42/commits/abc1234
# => gh pr checkout https://github.com/rails/rails/pull/42/commits/abc1234
hub checkout https://github.com/rails/rails/pull/42.patch
# => gh pr checkout https://github.com/rails/rails/pull/42.patch
hub checkout 'https://github.com/rails/rails/pull/42/files?w=1'
# => gh pr checkout https://github.com/rails/rails/pull/42/files\?w=1
hub checkout 'https://github.com/rails/rails/pull/42#discussion'
# => gh pr checkout https://github.com/rails/rails/pull/42#discussion
```

Check out the pull request's head commit without a branch:

```sh
hub checkout --detach https://github.com/rails/rails/pull/42
# => gh pr checkout https://github.com/rails/rails/pull/42 --detach
```

Update the submodules as well:

```sh
hub checkout https://github.com/rails/rails/pull/42 review --recurse-submodules
# => gh pr checkout https://github.com/rails/rails/pull/42 -b review --recurse-submodules
```

Check out a pull request on GitHub Enterprise. The host must be one gh is
logged in to, or the host in `GH_HOST`. Otherwise the command line goes to
git. hub runs gh with `GH_HOST` set to the URL's host, here
`ghe.example.test`. This value replaces any `GH_HOST` you set:

```sh
hub checkout https://ghe.example.test/acme/app/pull/3 review
# => gh pr checkout https://ghe.example.test/acme/app/pull/3 -b review
```

Without a pull request URL, the command line goes to `git checkout`
unchanged:

```sh
hub checkout main
# => git checkout main
hub checkout -b topic
# => git checkout -b topic
hub checkout -- README.md
# => git checkout -- README.md
```

A URL that is not a pull request goes to git as well, and git reads it as a
path. The same happens to a pull request URL after `--` or `--end-of-options`:

```sh
hub checkout https://github.com/rails/rails/issues/42
# => git checkout https://github.com/rails/rails/issues/42
hub checkout -- https://github.com/rails/rails/pull/42
# => git checkout -- https://github.com/rails/rails/pull/42
```

git then fails with `error: pathspec '...' did not match`. A repository page
such as `https://github.com/rails/rails`, a `pull/new` page, and a URL on
another host also go to git. hub knows github.com, the host in `GH_HOST`, and
the hosts that gh is logged in to.

Get git's help, even next to a pull request URL. git prints its
`usage: git checkout` summary:

```sh
hub checkout -h https://github.com/rails/rails/pull/42
# => git checkout -h https://github.com/rails/rails/pull/42
```

hub refuses git's other options next to a pull request URL. Nothing runs, and
hub exits with status 1:

```sh
hub checkout https://github.com/rails/rails/pull/42 -q
```

```text
hub checkout: unknown option: -q (gh pr checkout takes -b BRANCH, --detach and --recurse-submodules only)
Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULL-REQUEST-URL [BRANCH]
       hub checkout GIT-CHECKOUT-ARGS...
```

## Options

hub reads these options only on a command line with a pull request URL.
Without a URL, every option of `git checkout` stays as it is and reaches git
in its place:

| Option | What it does |
|---|---|
| `-b BRANCH` | Name the local branch, the same as the `BRANCH` operand. `-bBRANCH` works too. With `-b` given twice, the last one counts. Default: gh chooses the name. |
| `-d`, `--detach` | Check out the pull request's head commit without a branch. hub refuses it with a branch name. |
| `--recurse-submodules` | Update the submodules too. |
| `--`, `--end-of-options` | End the search for a pull request URL. A URL after it goes to git as a path. |
| `-h`, `--help` | Print git's help, even next to a pull request URL. |

These are all the options. Any other option next to a pull request URL is
refused (see [Exit status](#exit-status)).

## How it works

hub applies these rules in order:

1. hub looks at the words before `--` or `--end-of-options`. If one of them is
   `--help`, `--help-all` or `-h` (alone or among one-letter flags such as
   `-qh`), git runs with the command line unchanged and prints its help.
2. If one of those words is `--pathspec-from-file` or `--pathspec-file-nul`
   (also abbreviated, such as `--pathspec-fr`), the command line goes to git.
   Their file name can look like a pull request URL.
3. If no word is a pull request URL, the command line goes to git unchanged. A
   pull request URL is an `http` or `https` URL of the form
   `HOST/OWNER/REPO/pull/N`, with any page after it. `HOST` is github.com,
   `GH_HOST` or a host gh is logged in to. See
   [Repositories and URLs](../guide/repositories-and-urls.md).
4. Otherwise the command line is hub's. It may hold one URL, at most one
   `BRANCH` operand after the URL, and the options in [Options](#options). hub
   refuses anything else before it runs gh.
5. hub checks the branch name with `git check-ref-format --branch`. It also
   refuses a name that starts with `refs/`, `heads/`, `tags/` or `remotes/`,
   and names such as `HEAD`, `-` and `@{-1}`.
6. hub runs `gh pr checkout URL` and adds `-b BRANCH`, `--detach` and
   `--recurse-submodules` in that order. Each option appears at most once. hub
   sets `GH_HOST` to the URL's host, so gh fetches from a local remote of that
   host.

hub needs gh. Without it, hub prints
`hub checkout: this command needs the GitHub CLI, gh (https://cli.github.com)`
and changes nothing. `hub --noop` prints the command and does not run it (see
[How hub works](../guide/how-hub-works.md)).

## Exit status

`hub checkout` exits with gh's status, or git's on a command line it hands to
git. For example, if gh prints `could not find pull request` and exits with 4,
hub exits with 4. hub's own refusals exit with status 1. These are the
messages:

| Message | What to do |
|---|---|
| `X discards local changes in git; gh pr checkout --force resets the branch to the pull request instead (run it yourself)` | `-f` or `--force` (X) was next to a URL. To reset the branch, run `gh pr checkout URL --force` yourself. |
| `unknown option: X (gh pr checkout takes -b BRANCH, --detach and --recurse-submodules only)` | Another option, such as `-q`, `--track` or `--recurse-submodules=yes`, was next to a URL. Drop it. |
| `--detach cannot be used with a branch name (drop one)` | `--detach` or `-d` came with `-b` or `BRANCH`, and gh would drop the branch. Drop one. |
| `unexpected argument: X` | A word before the URL, a second URL, or a second operand. Drop it. |
| `unexpected argument: X (-b names the branch already)` | Both `-b BRANCH` and a `BRANCH` operand. Keep one. |
| `-b needs a value` | `-b` was at the end of the command line. Give it a name. |
| `-b needs a branch name`, `the branch name is empty` | An empty branch name, or an empty word anywhere on the command line. Remove the empty word. |
| `the pull request URL is missing` | `-b` took the URL as its value, as in `hub checkout -b URL`. Put the branch name after `-b`. |
| `not a valid branch name: X` | git would read the name as something else (rule 5). Choose another name. |

Each message starts with `hub checkout: `. All of them except the `-f`
message, `the branch name is empty` and `not a valid branch name` also print
the `Usage:` lines.

## Differences from the original hub

The original hub (mislav/hub 2.x) had the same synopsis,
`hub checkout PULLREQ-URL [BRANCH]`, and also left every command line without
a pull request URL to git. The rest changed:

| Original hub | This hub |
|---|---|
| hub read the pull request from the GitHub API and ran `git fetch` and `git checkout` itself, for example `git fetch origin refs/pull/73/head:BRANCH` then `git checkout BRANCH`. | hub runs `gh pr checkout URL`. gh fetches the pull request and makes the branch. |
| git's options went through and kept their place around the URL: `hub checkout -f URL -q` ran `git checkout -f BRANCH -q`. | Only `-b`, `-d`/`--detach` and `--recurse-submodules` go with a URL. Any other option is an error. |
| `-f` meant `git checkout -f`, which discards local changes. | hub refuses `-f` and `--force`, because gh's `--force` resets the branch to the pull request. To do that, run `gh pr checkout URL --force`. |
| hub took only the URL form `https://github.com/OWNER/REPO/pull/N`. | Any page of the pull request, also `.patch`, `.diff`, `commits/SHA`, a query or a fragment, on GitHub.com or a known GitHub Enterprise host. |
| The branch name defaulted to the head branch's name, or `OWNER-BRANCH` when that name was the head repository's default branch. | gh chooses the default name. Name the branch with `BRANCH` or `-b`. |
| It needed a local remote for the base repository, else `could not find a git remote for 'OWNER/REPO'`. | gh finds the remote, among the remotes of the URL's host. |
| hub set the branch's upstream (`branch.BRANCH.remote` and `.merge`), and kept an existing setting. When the fork allowed edits from maintainers, the upstream was the fork's URL, so `git push` updated the pull request. | gh sets up the branch. hub writes no configuration. |
| If the branch existed and was checked out, hub fast-forwarded it with `git merge --ff-only`. | gh handles an existing branch. |
| `--detach` and `--recurse-submodules` went to `git checkout` like its other options. | Both go to gh. hub refuses `--detach` with a branch name. |
| hub needed no GitHub CLI. | gh must be installed for a command line with a URL. |

To check out a pull request by number, use [`hub pr checkout`](pr.md), as in
`hub pr checkout 42 -b review`, which runs `gh pr checkout 42 -b review`.

## See also

- [hub pr](pr.md): list, show and check out pull requests by number.
- [hub merge](merge.md): merge a pull request by its URL.
- [hub am](am.md) and [hub cherry-pick](cherry-pick.md): other git commands
  that take a pull request URL.
- [Repositories and URLs](../guide/repositories-and-urls.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-checkout(1)](https://hub.github.com/hub-checkout.1.html)
- gh's manual: [gh pr checkout](https://cli.github.com/manual/gh_pr_checkout)
- git's manual: [git checkout](https://git-scm.com/docs/git-checkout)
- This hub's manual: [hub checkout](https://brc-dd.github.io/hub/checkout.html)
