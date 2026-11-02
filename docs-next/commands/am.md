---
title: hub am
description: Apply the commits of a GitHub pull request, commit or comparison.
kind: git command hub extends
original: https://hub.github.com/hub-am.1.html
---

# hub am

`hub am` applies the commits of a GitHub pull request, commit or comparison,
with their authors and messages. `hub am` is `git am` with one addition: it
also accepts such a URL and downloads it through the GitHub CLI (gh) for git.
A command line without such a URL goes to `git am` unchanged. The most common
use is `hub am -3 URL`, which applies a pull request to the current branch.

```sh
hub am -3 https://github.com/cli/cli/pull/55
# runs: gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.patch'
# => git am -3 TMPDIR/hub-am.XXXXXX/1.patch
```

## Usage

```text
hub am [GIT-AM-OPTIONS...] (URL | MBOX)...
```

`URL` is a pull request, commit or comparison URL on a GitHub host that hub
knows. See [Hosts and login](../guide/hosts-and-login.md). `MBOX` is a mailbox
or patch file, as for `git am`. You can mix both kinds, in any order.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md), `git am`
is the same command. Each `# =>` line is what `hub --noop` prints: the git
command that hub runs. Each `# runs:` line is the download that hub makes with
gh. hub adds `--allow-escape-sequences` at its end when your gh has that
option. `TMPDIR` stands for your temporary directory. hub removes the
downloaded files when it ends.

Apply every commit of a pull request, with a three-way merge if a patch does
not apply cleanly:

```sh
hub am -3 https://github.com/cli/cli/pull/55
# runs: gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.patch'
# => git am -3 TMPDIR/hub-am.XXXXXX/1.patch
```

Apply one commit:

```sh
hub am https://github.com/cli/cli/commit/8526f046.diff
# runs: gh api --hostname github.com repos/cli/cli/commits/8526f046 -H 'Accept: application/vnd.github.patch'
# => git am TMPDIR/hub-am.XXXXXX/1.patch
```

A `.patch` or `.diff` suffix changes nothing. hub always downloads the patch,
so the commit keeps its author and message.

Apply one commit of a pull request:

```sh
hub am https://github.com/cli/cli/pull/55/commits/8526f046
# runs: gh api --hostname github.com repos/cli/cli/commits/8526f046 -H 'Accept: application/vnd.github.patch'
# => git am TMPDIR/hub-am.XXXXXX/1.patch
```

hub asks for that commit only, not for the whole pull request.

Apply the commits of a three-dot comparison:

```sh
hub am 'https://github.com/rails/rails/compare/v7.0.0...OWNER:BRANCH.patch'
# runs: gh api --hostname github.com repos/rails/rails/compare/v7.0.0...OWNER:BRANCH -H 'Accept: application/vnd.github.patch'
# => git am TMPDIR/hub-am.XXXXXX/1.patch
```

hub keeps the range as written, including an `OWNER:BRANCH` head from a fork.

Mix a local patch and a URL:

```sh
hub am --signoff fix.patch https://github.com/cli/cli/pull/57
# => git am --signoff fix.patch TMPDIR/hub-am.XXXXXX/1.patch
```

hub keeps every argument in its place, so git applies `fix.patch` first and
the pull request after it, and signs off both.

Apply several URLs in one command:

```sh
hub am https://github.com/cli/cli/commit/8526f046 https://github.com/cli/cli/commit/7233b3ac
# => git am TMPDIR/hub-am.XXXXXX/1.patch TMPDIR/hub-am.XXXXXX/2.patch
```

Git applies them in command-line order.

Apply a pull request from GitHub Enterprise:

```sh
GH_HOST=ghe.example.com hub am https://ghe.example.com/core/api/pull/7
# runs: gh api --hostname ghe.example.com repos/core/api/pulls/7 -H 'Accept: application/vnd.github.patch'
# => git am TMPDIR/hub-am.XXXXXX/1.patch
```

hub downloads the patch from the URL's host. The host must be github.com, the
value of `GH_HOST`, or a host that gh is logged in to.

Give `git am` options with values before the URL:

```sh
hub am -p 1 --patch-format mbox https://github.com/cli/cli/pull/55
# => git am -p 1 --patch-format mbox TMPDIR/hub-am.XXXXXX/1.patch
```

hub skips each option's value and still finds the URL.

See what hub would run:

```sh
hub --noop am -3 https://github.com/cli/cli/pull/55
```

```text
git am -3 /var/folders/mn/jm2nxd1s1p1g122ytx9s5lqh0000gn/T//hub-am.ulQHCA/1.patch
```

`hub --noop` still downloads the patch, because a download changes nothing,
but prints `git am` and does not run it. The file in the printed command line
is gone when hub ends.

Continue after a conflict. Git stops with `Patch failed at 0001 ...` and hub
exits with git's status (128). Resolve the conflict, then finish git's session
with `--continue`, `--skip` or `--abort`:

```sh
git add .
hub am --continue
# => git am --continue
```

These command lines hold no URL, so they go to `git am` unchanged.

Hand a command line to git without a download:

```sh
hub am fix.patch
# => git am fix.patch
hub am -- https://github.com/cli/cli/pull/55
# => git am -- https://github.com/cli/cli/pull/55
hub am --directory https://github.com/cli/cli/pull/55 fix.patch
# => git am --directory https://github.com/cli/cli/pull/55 fix.patch
```

The three cases are a local mailbox alone, a URL after `--`, and a URL that is
an option's value.

Give a GitHub URL that hub does not download:

```sh
hub am https://github.com/rails/rails/compare/v7.0.0..v7.0.1
# => git am https://github.com/rails/rails/compare/v7.0.0..v7.0.1
hub am https://github.com/cli/cli/pull/55/files/abc1234
# => git am https://github.com/cli/cli/pull/55/files/abc1234
hub am https://gist.github.com/OWNER/GIST_ID
# => git am https://gist.github.com/OWNER/GIST_ID
```

These URLs go to `git am` unchanged. Git then reads them as file names and
fails.

Apply a pull request that does not exist:

```sh
hub am https://github.com/cli/cli/pull/999999999
```

```text
gh: Not Found (HTTP 404)
hub am: could not download: https://github.com/cli/cli/pull/999999999
```

The failed download stops hub before `git am` runs. gh's message comes first.

## Options

`hub am` has no options of its own. Every option of `git am` stays as it is and
reaches git in its place. hub reads these options only to find the operands:

| Option | What it does |
|---|---|
| `-p`, `-C`, `--exclude`, `--include`, `--directory`, `--whitespace`, `--patch-format`, `--resolvemsg`, `--quoted-cr`, `--empty` | Take the next word as the option's value. hub never downloads that value, even when it is a URL. |
| `-S[KEYID]` | Write the key id attached, as `-SKEYID`. hub reads a separate word after `-S` as an operand. |
| `--`, `--end-of-options` | Send every word after it to git unchanged. hub downloads no URL there. |
| `-h`, `--help`, `--help-all` | Print git's usage or manual. hub downloads nothing. |

Any other option, such as `-3`, `-q` or `--signoff`, stays in its place. For
hub's manual, run `hub help am`. For what each option does, run
`git am --help`.

## How it works

hub applies these rules in order:

1. hub looks at the operands before `--` or `--end-of-options`. An option's
   value is not an operand.
2. hub downloads an operand when it is one of these URLs, with or without a
   `.patch` or `.diff` suffix: a pull request,
   `https://HOST/OWNER/REPO/pull/N`, also with a trailing `/`, a query, a
   fragment or a tab page such as `/files`; a commit,
   `https://HOST/OWNER/REPO/commit/SHA`, where `SHA` is 4 to 64 hex digits; one
   commit of a pull request, `.../pull/N/commits/SHA`; a comparison,
   `.../compare/BASE...HEAD` with three dots. A deeper path such as
   `.../pull/N/files/SHA` shows only some of the changes, so hub does not
   download it.
3. `HOST` must be github.com, the value of `GH_HOST`, or a host that gh is
   logged in to. See [Hosts and login](../guide/hosts-and-login.md) and
   [Repositories and URLs](../guide/repositories-and-urls.md).
4. Without such a URL, the command line is plain `git am`. hub does not need
   gh then.
5. If hub cannot tell which words are operands, it passes the command line to
   git unchanged. Examples are an abbreviated option such as `--dir URL`, a
   value-taking option as the last word, and a word with a newline.
6. When the command line has such a URL, hub stops outside a work tree before
   any download.
7. While an `am` session is in progress, hub downloads nothing and runs
   `git am` with the command line unchanged. Git refuses a new mailbox
   (`rebase-apply still exists but mbox given`).
8. hub downloads each URL with
   `gh api --hostname HOST ENDPOINT -H 'Accept: application/vnd.github.patch'`.
   The endpoint is `repos/OWNER/REPO/pulls/N`, `repos/OWNER/REPO/commits/SHA`
   or `repos/OWNER/REPO/compare/RANGE`. If gh has the
   `--allow-escape-sequences` option, hub adds it, so gh does not change
   escape characters in the patch.
9. hub saves the patches in a new directory under `TMPDIR` (or `/tmp`),
   numbered `1.patch`, `2.patch`, in command-line order. It puts each file in
   its URL's place and runs `git am` with the command line. Git copies the
   patches into its session, so hub removes the directory when it ends.

Other GitHub URLs go to git unchanged: a repository, an issue, a two-dot
comparison, a pull request page that shows only some commits
(`.../pull/N/files/SHA`, `.../pull/N/changes/SHA`), a gist, and URLs on other
hosts. See [How hub works](../guide/how-hub-works.md) for `--noop`.

## Exit status

`hub am` exits with git's status when hub runs `git am`, for example 128 when
a patch fails. When a download fails, hub prints
`hub am: could not download: URL`, git does not run, and hub exits with gh's
status. hub's own refusals exit with status 1. hub needs gh when the command
line has a URL to download. Without it, hub prints
`hub am: this command needs the GitHub CLI, gh (https://cli.github.com)`.
Outside a work tree, hub stops with git's message (`not a git repository`).
Inside a .git directory or a bare repository, hub prints
`hub am: not inside a work tree`. These are hub's messages:

```text
hub am: could not download: URL
hub am: this command needs the GitHub CLI, gh (https://cli.github.com)
hub am: not inside a work tree
```

## Differences from the original hub

The table compares `hub am` with the original hub (mislav/hub 2.x).

| Original hub | This hub |
|---|---|
| `hub am [-3] GITHUB-URL`. git am options such as `-q` passed through. | Same. Several URLs and local mailboxes can share one command line. Each URL becomes a file in its place. |
| Pull request, commit and `pull/N/commits/SHA` URLs were downloaded. | Same. |
| Comparison URLs were not downloaded. | Three-dot `compare/BASE...HEAD` URLs are downloaded. A two-dot `compare/A..B` goes to git unchanged, because GitHub's API compares only `BASE...HEAD`. |
| Gist URLs (`https://gist.github.com/ID`) were downloaded. | Not supported. Run `gh gist clone ID`, then `hub am` the file. |
| Patches were downloaded through the GitHub API with hub's own token, as `application/vnd.github.v3.patch`. | Patches are downloaded through `gh api` as `application/vnd.github.patch`. gh must be installed and logged in to the host. |
| GitHub Enterprise URLs worked on a host in hub's configuration, through `/api/v3`. | The URL's host must be github.com, `GH_HOST`, or a host gh is logged in to. gh finds the API. |
| hub wrote the patch to a temporary file, under `/tmp` when `TMPDIR` was empty. | Same. hub removes the files when it ends. |
| A local patch file was unchanged. | Same. |

The original manual showed `curl URL.patch` to explain the download. The
original hub did not run curl, and this hub does not run it either.

## See also

- [hub apply](apply.md): apply the same URLs as one diff, without commits.
- [hub cherry-pick](cherry-pick.md): fetch a commit by its URL and pick it.
- [hub merge](merge.md): merge a pull request locally.
- [hub checkout](checkout.md): check out a pull request's branch.
- [How hub works](../guide/how-hub-works.md): the git commands hub extends,
  and `--noop`.
- [Hosts and login](../guide/hosts-and-login.md): the hosts hub downloads
  from.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual: [hub-am(1)](https://hub.github.com/hub-am.1.html)
- gh's manual: [gh api](https://cli.github.com/manual/gh_api)
- git's manual: [git am](https://git-scm.com/docs/git-am)
- This hub's manual: [hub am](https://brc-dd.github.io/hub/am.html)
