---
title: hub apply
description: Apply the changes of a GitHub pull request, commit or comparison.
kind: git command hub extends
original: https://hub.github.com/hub-apply.1.html
---

# hub apply

`hub apply` applies the changes of a GitHub pull request, commit or comparison
to the work tree. It is `git apply` with one addition: it also takes such a
URL, downloads it through the GitHub CLI (gh) as one diff and hands the file to
git. Without such a URL, the command line goes to `git apply` unchanged. Use
it to try out changes without a commit. The most common use is `hub apply`
with a pull request's URL.

```sh
hub apply https://github.com/cli/cli/pull/55
# runs: gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.diff'
# => git apply TMPDIR/hub-apply.XXXXXX/1.diff
```

## Usage

```text
hub apply [GIT-APPLY-OPTIONS...] (URL | PATCH)...
```

`URL` is the URL of a pull request, a commit or a three-dot comparison on
github.com, on `GH_HOST` or on a host gh is logged in to. See
[Hosts and login](../guide/hosts-and-login.md). `PATCH` is a patch file, as for
`git apply`. You can mix both kinds in one command line.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git apply` is the same command. Each `# =>` line is what `hub --noop` prints:
the git or gh command that hub runs. Each `# runs:` line is a download that
`--noop` still runs, because a download changes nothing. In the printed lines,
`TMPDIR/hub-apply.XXXXXX/1.diff` stands for the file hub downloaded, in a new
directory under `$TMPDIR`, or under `/tmp` when `TMPDIR` is empty or unset.

Apply the changes of a pull request to the work tree:

```sh
hub apply https://github.com/cli/cli/pull/55
# runs: gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.diff'
# => git apply TMPDIR/hub-apply.XXXXXX/1.diff
```

The files change. The branch, its commits and the index stay as they were.

Put git's options anywhere on the command line. hub leaves them in place and
replaces only the URL:

```sh
hub apply --index -3 https://github.com/cli/cli/pull/55.patch
# => git apply --index -3 TMPDIR/hub-apply.XXXXXX/1.diff
```

A `.patch` or `.diff` suffix makes no difference: hub always downloads one
diff. `--index` also stages the changes, as in git.

Apply the changes of one commit:

```sh
hub apply https://github.com/cli/cli/commit/9490d20
# => git apply TMPDIR/hub-apply.XXXXXX/1.diff
```

hub downloads from `repos/cli/cli/commits/9490d20`. A commit inside a pull
request, such as `https://github.com/octo/proj/pull/7/commits/abcdef0`, comes
from the same endpoint, `repos/octo/proj/commits/abcdef0`.

Apply the difference between two tags or branches with a three-dot comparison:

```sh
hub apply https://github.com/cli/cli/compare/v2.0.0...v2.1.0
# => git apply TMPDIR/hub-apply.XXXXXX/1.diff
```

hub downloads from `repos/cli/cli/compare/v2.0.0...v2.1.0`. A branch in a
fork works too, as in `compare/v1.0...OWNER:feature`, where `OWNER` is the
fork's owner.

Copy the URL from any page of the pull request. Quote a URL that contains `?`
or `#`, so that the shell passes it whole:

```sh
hub apply 'https://github.com/octo/proj/pull/7/files?w=1#diff'
```

hub downloads the whole pull request, `repos/octo/proj/pulls/7`. The commits
tab, `.../pull/7/commits`, also downloads the whole pull request.

Mix local patches and URLs. Each URL becomes its own file, in its place:

```sh
hub apply --stat fix.diff https://github.com/cli/cli/pull/55
# => git apply --stat fix.diff TMPDIR/hub-apply.XXXXXX/1.diff
```

hub knows which options take a value, so it never downloads a value given as
a separate word:

```sh
hub apply -p 1 --whitespace nowarn https://github.com/cli/cli/pull/55
# => git apply -p 1 --whitespace nowarn TMPDIR/hub-apply.XXXXXX/1.diff
```

Apply a pull request on GitHub Enterprise. The host must be `GH_HOST` or a host
gh is logged in to:

```sh
GH_HOST=ghe.example.test hub apply https://ghe.example.test/octo/proj/pull/3
# runs: gh api --hostname ghe.example.test repos/octo/proj/pulls/3 -H 'Accept: application/vnd.github.diff'
```

hub always downloads from the URL's host, even when `GH_HOST` names another
host.

Apply a local patch. Without a URL that hub downloads, the command line is
plain `git apply`:

```sh
hub apply some.patch
# => git apply some.patch
```

Keep a URL away from hub with `--` or `--end-of-options`. git then reads it as
a file name:

```sh
hub apply -- https://github.com/cli/cli/pull/55
# => git apply -- https://github.com/cli/cli/pull/55
```

These command lines also go to `git apply` unchanged, with no download:

```sh
hub apply https://github.com/cli/cli/pull/55/files/abc1234
# => git apply https://github.com/cli/cli/pull/55/files/abc1234
hub apply https://github.com/cli/cli/compare/v2.0.0..v2.1.0
# => git apply https://github.com/cli/cli/compare/v2.0.0..v2.1.0
hub apply --directory https://github.com/cli/cli/pull/55 x.diff
# => git apply --directory https://github.com/cli/cli/pull/55 x.diff
hub apply -h https://github.com/cli/cli/pull/55
# => git apply -h https://github.com/cli/cli/pull/55
```

The first is one commit's page within a pull request. The second is a two-dot
comparison. In the third, the URL is the value of `--directory`. The fourth
asks for git's usage. Without `--noop`, git fails on the first two with
`can't open patch 'URL'`, and on the third it reads `x.diff` with the URL as its
directory.

## Options

`hub apply` has no options of its own. Every option of `git apply` stays as it
is and reaches git in its place. hub reads these options only to find the
operands:

| Option | What it does |
|---|---|
| `-p`, `-C`, `--exclude`, `--include`, `--directory`, `--whitespace`, `--build-fake-ancestor` | Take the next word as the option's value. hub never downloads it. |
| `--`, `--end-of-options` | Download no URL after it. |
| Any other option | Leave it in place. |
| `-h`, `--help`, `--help-all` (also in a cluster such as `-Rh`) | Hand the whole command line to git: git's manual or usage, nothing downloaded. |

For hub's manual, run `hub help apply`. It ends with
`git's own manual: git apply --help`.

## How it works

hub applies these rules in order:

1. If the command line asks for help, or hub cannot tell the operands from
   the options, hub runs `git apply` with the command line unchanged. Two
   command lines do this: one with an abbreviated long option such as
   `--dir`, and one that ends in an option that takes a value, such as
   `hub apply URL -p`.
2. hub picks each operand before `--` or `--end-of-options` that is a pull
   request, commit or comparison URL on a known host (github.com, `GH_HOST`
   or a host gh is logged in to), with or without a `.patch` or `.diff`
   suffix. These are a pull request, `.../pull/N`, or a page of it such as
   `.../pull/N/files`, a commit, `.../commit/SHA` or
   `.../pull/N/commits/SHA` with a SHA of 4 to 64 hex digits, and a
   three-dot comparison, `.../compare/BASE...HEAD`.
3. If no operand is such a URL, hub runs plain `git apply` with the command
   line unchanged. Other URLs stay as they are: issues, two-dot comparisons,
   `.../pull/N/files/SHA` pages and URLs on hosts hub does not know.
4. hub makes a directory under `$TMPDIR`, or under `/tmp` when `TMPDIR` is
   empty or unset. For each URL, it runs
   `gh api --hostname HOST ENDPOINT -H 'Accept: application/vnd.github.diff'`
   and saves the diff as `1.diff`, `2.diff` and so on. hub adds
   `--allow-escape-sequences` when gh supports it. To check, hub runs
   `gh api --help` once per command.
5. hub runs `git apply` with every word in its place and each URL replaced by
   its file. hub removes the directory when it exits.

hub always downloads a diff, never a patch series. `git apply` reads a series
as one input, so a file that the series creates and later deletes would stay
in the work tree. With one diff, it does not.

hub makes no commit. To make commits from a pull request, use
[hub am](am.md). For the hosts hub knows, see
[Hosts and login](../guide/hosts-and-login.md). For the URL forms, see
[Repositories and URLs](../guide/repositories-and-urls.md).

## Exit status

`hub apply` exits with git's status, for example 1 when a patch does not apply
and 128 when a file is not a patch. hub removes its downloads in every case.

If a download fails, hub prints gh's message and the message below, and stops
before `git apply` runs. The work tree stays as it was, and the status is
gh's. hub's own refusals exit with status 1: when gh is not installed, and
when hub cannot make its directory under `$TMPDIR`, before any download.

```text
hub apply: could not download: URL
hub apply: this command needs the GitHub CLI, gh (https://cli.github.com)
```

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub apply GITHUB-URL`. | Same. Several URLs and local patches can also share one command line. |
| git apply's options passed through, for example `-3`. | Same. |
| A local patch file went to git unchanged. | Same. |
| hub made no commit. | Same. |
| Pull request and commit URLs, also `.../pull/N/commits/SHA`. | Same. Any page of a pull request also works, such as `.../pull/N/files`. |
| hub downloaded the changes as a patch. | hub downloads one diff, also for a URL that ends in `.patch`. |
| hub took no comparison URLs. | Three-dot `compare/BASE...HEAD` URLs. A two-dot `compare/A..B` goes to git unchanged. |
| Gist URLs, such as `https://gist.github.com/8da7fb575debd88c54cf`. | Not supported. Run `gh gist clone ID`, then apply the file. |
| GitHub Enterprise URLs on a host hub was configured for. | URLs on `GH_HOST` or a host gh is logged in to, downloaded with gh's login. |
| hub saved downloads under `TMPDIR`, or `/tmp` when it was empty. | Same. |

## See also

- [hub am](am.md): apply a pull request or commit as commits.
- [hub cherry-pick](cherry-pick.md) and [hub merge](merge.md): other ways to
  take a pull request's changes.
- [How hub works](../guide/how-hub-works.md): the git commands hub extends and
  `--noop`.
- [Hosts and login](../guide/hosts-and-login.md) and
  [Repositories and URLs](../guide/repositories-and-urls.md).
- [Coming from the original hub](../compatibility/README.md).
- The original hub's manual:
  [hub-apply(1)](https://hub.github.com/hub-apply.1.html)
- gh's manual: [gh api](https://cli.github.com/manual/gh_api) and
  [gh pr diff](https://cli.github.com/manual/gh_pr_diff)
- git's manual: [git apply](https://git-scm.com/docs/git-apply)
- This hub's manual: [hub apply](https://brc-dd.github.io/hub/apply.html)
