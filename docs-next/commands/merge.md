---
title: hub merge
description: Merge a pull request locally, with the message GitHub's merge button uses.
kind: git command hub extends
original: https://hub.github.com/hub-merge.1.html
---

# hub merge

`hub merge` merges a pull request into the current branch on your machine. It
is `git merge` with one addition: it also accepts a pull request URL, and then
hub fetches the pull request and runs `git merge --no-ff` with the message of
GitHub's merge button. A command line without one goes to `git merge`
unchanged. The most common use is `hub merge URL`, to test the result before
you push.

```sh
hub merge https://github.com/rails/rails/pull/42
# => git fetch --quiet --no-tags --refmap= -- upstream refs/pull/42/head
# => git merge --no-ff -m Merge\ pull\ request\ #42\ from\ OWNER/BRANCH -m TITLE FETCH_HEAD
```

## Usage

```text
hub merge [GIT-MERGE-OPTIONS...] PULL-REQUEST-URL
```

`PULL-REQUEST-URL` is the URL of a pull request, such as
`https://github.com/OWNER/REPO/pull/N`, or of any page of the whole pull
request, such as `.../pull/N/files`. Its host is GitHub.com, the host in
`GH_HOST`, or a host the GitHub CLI (gh) is logged in to. `GIT-MERGE-OPTIONS`
are the options of `git merge`. Without a pull request URL, the command line is
plain `git merge`.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git merge` is the same command. Each `# =>` line is what `hub --noop` prints:
the git command that hub runs. `--noop` shows the fetched commit as
`FETCH_HEAD`, and a real run merges the commit by its full id. In these
examples, a remote named `upstream` points at rails/rails.

Merge a pull request with GitHub's merge commit message:

```sh
hub merge https://github.com/rails/rails/pull/42
# => git fetch --quiet --no-tags --refmap= -- upstream refs/pull/42/head
# => git merge --no-ff -m Merge\ pull\ request\ #42\ from\ OWNER/BRANCH -m TITLE FETCH_HEAD
```

OWNER and BRANCH are the owner and name of the pull request's branch. The
second `-m` is the pull request's title, which becomes the commit body after a
blank line.

Merge in a clone with no remote that points at rails/rails:

```sh
hub merge https://github.com/rails/rails/pull/42
# => git fetch --quiet --no-tags --refmap= -- git@github.com:rails/rails.git refs/pull/42/head
```

hub fetches from the repository's URL. The URL is ssh when gh's `git_protocol`
setting is `ssh`, as here, and https otherwise (see
[Configuration](../guide/configuration.md#change-settings-through-gh)).

Squash the pull request into the index, with no merge commit and no message
from hub:

```sh
hub merge --squash https://github.com/rails/rails/pull/42
# => git merge --squash FETCH_HEAD
```

Fast-forward only, or stop with an error:

```sh
hub merge --ff-only https://github.com/rails/rails/pull/42
# => git merge -m Merge\ pull\ request\ #42\ from\ OWNER/BRANCH -m TITLE --ff-only FETCH_HEAD
```

`--ff`, `--no-ff` and `--ff-only` replace hub's `--no-ff`.

Write your own message, or let git write its default one:

```sh
hub merge -m 'Merge the logging fix' https://github.com/rails/rails/pull/42
# => git merge --no-ff -m Merge\ the\ logging\ fix FETCH_HEAD

hub merge --no-message https://github.com/rails/rails/pull/42
# => git merge --no-ff --no-message FETCH_HEAD
```

`-m`, `--message`, `-F`, `--file` and `--no-message` replace hub's message, in
any spelling (`-mText`, `--message=Text`, `--file=PATH`). With `--no-message`,
git writes its default message, `Merge commit 'SHA'`.

Pass any other option of `git merge`, such as `--no-edit` or a signing key:

```sh
hub merge https://github.com/rails/rails/pull/42 --no-edit
# => git merge --no-ff -m Merge\ pull\ request\ #42\ from\ OWNER/BRANCH -m TITLE FETCH_HEAD --no-edit

hub merge -Sme@example.com https://github.com/rails/rails/pull/42
# => git merge --no-ff -m Merge\ pull\ request\ #42\ from\ OWNER/BRANCH -m TITLE -Sme@example.com FETCH_HEAD
```

hub puts `--no-ff` and its message first. Your arguments follow in the order
you typed them, with the pull request in the place of the URL.

Merge the pull request from the URL of any of its tabs, such as Files changed:

```sh
hub merge https://github.com/rails/rails/pull/42/files
# => git fetch --quiet --no-tags --refmap= -- upstream refs/pull/42/head
```

Merge a branch, or stop a merge. A command line without a pull request URL goes
to `git merge` unchanged:

```sh
hub merge feature
# => git merge feature

hub merge --abort
# => git merge --abort
```

Merge the URL of one commit (`.../pull/N/commits/SHA`) or of the patch
(`.../pull/N.patch`), and git refuses it:

```sh
hub merge https://github.com/rails/rails/pull/42/commits/abc1234
# => git merge https://github.com/rails/rails/pull/42/commits/abc1234

hub merge https://github.com/rails/rails/pull/42.patch
# => git merge https://github.com/rails/rails/pull/42.patch
```

hub does not treat these URLs as the pull request. git prints
`not something we can merge`.

Give a pull request URL as the value of `-m`, and it is the commit message:

```sh
hub merge --no-ff -m https://github.com/rails/rails/pull/42 refs/heads/topic
# => git merge --no-ff -m https://github.com/rails/rails/pull/42 refs/heads/topic
```

hub runs plain `git merge`, here of the local branch `topic`.

Finish a merge that stopped on a conflict, after you resolve the files as for
any merge:

```sh
hub merge --continue
# => git merge --continue
```

git records the pull request's last commit as `MERGE_HEAD`. hub runs plain
`git merge --continue`.

Merge two operands at once, and hub refuses and fetches nothing:

```sh
hub merge https://github.com/rails/rails/pull/42 topic
```

```text
hub merge: unexpected argument: topic (a pull request is merged alone)
Usage: hub merge [GIT-MERGE-OPTIONS...] PULL-REQUEST-URL
```

## Options

`hub merge` has no options of its own. Every option of `git merge` stays as it
is and reaches git in its place. hub reads these options only to decide what to
add and to find the operands:

| Option | What it does |
|---|---|
| `--ff`, `--no-ff`, `--ff-only` | Choose how git merges. hub does not add its `--no-ff`. git's option. |
| `-m`, `--message`, `-F`, `--file`, `--no-message` | Set the commit message. hub does not add its message. git's option. |
| `--squash` | Squash the pull request into the index. hub adds neither `--no-ff` nor its message. A later `--no-squash` undoes it. git's option. |
| `--abort`, `--quit`, `--continue` | Stop or finish a merge. The command line is plain `git merge`. git's option. |
| `-s`, `--strategy`, `-X`, `--strategy-option`, `--into-name`, `--cleanup` | Pass a value to git. hub reads the next word as that value, even when it is a URL. git's option. |
| `-S[KEY]` | Sign the merge commit. hub reads a key only when it is attached (`-SKEY`). git's option. |
| `--`, `--end-of-options` | End the options. A URL after it is git's operand, and the command line is plain `git merge`. |
| `-h`, `--help`, `--help-all` | Print git's usage or manual. The command line is plain `git merge`. |

For hub's manual, run `hub help merge`.

## How it works

hub applies these rules in order:

1. hub reads the options as `git merge` does. The word after an option that
   takes a value is that value, even when it is a URL. In combined short
   options such as `-qm URL`, `m` takes the next word, so the URL is the
   message.
2. When hub cannot read the command line with certainty, it passes it to git
   unchanged. These are an abbreviated option (`--squ`, `--no-mess=Text`),
   combined short options with a value letter after another letter
   (`-qmText`), and an option that takes a value as the last word
   (`hub merge URL -m`). For example, `hub merge --squ URL` runs
   `git merge --squ URL`.
3. The first operand before `--` that is a pull request URL is the pull
   request. Its host must be GitHub.com, `GH_HOST` or a host gh is logged in
   to. Without one, the command line is plain `git merge`. hub reads the
   number as gh does: `.../pull/012` is pull request 12, and hub fetches
   `refs/pull/12/head`.
4. Any other operand, empty ones included, is an error.
5. hub must run in a work tree, and gh 2.55 or newer must be installed and
   logged in. hub asks gh for the number, the title and the branch
   (`gh pr view URL --json ...`). `hub --noop` still runs this lookup.
6. hub fetches `refs/pull/N/head` from the pull request's repository, through
   the first remote that points at it (`upstream`, `github`, `origin`, then
   the others), else its URL. `--no-tags` brings in no tags, even with
   `remote.NAME.tagOpt`. `--refmap=` keeps a configured `refs/pull/*` refspec
   from moving local branches.
7. hub runs `git merge` with `--no-ff` and its message first, then your
   arguments in your order. The message is
   `Merge pull request #N from OWNER/BRANCH`, then the title. The pull request
   takes the place of the URL. hub merges the fetched commit by its full id,
   which `--noop` shows as `FETCH_HEAD`.

hub pushes nothing. The pull request stays open on GitHub until you push the
merge commit to its base branch. To merge on GitHub instead, use
`gh pr merge`. See [Project and remotes](../guide/project-and-remotes.md) for
which remote points at a repository, and
[Repositories and URLs](../guide/repositories-and-urls.md) for the URL forms.

## Exit status

`hub merge` exits with git's status, also when the fetch or the merge fails, a
conflict included, and when the command line is plain `git merge`. hub's own
refusals exit with status 1:

```text
hub merge: unexpected argument: topic (a pull request is merged alone)
hub merge: not inside a work tree
hub merge: this command needs the GitHub CLI, gh (https://cli.github.com)
hub merge: could not read refs/pull/N/head from FETCH_HEAD
```

Outside a repository, hub prints git's message, such as `not a git repository`,
and exits with status 1. The last message means that hub cannot read the
fetched commit. When gh cannot look the pull request up, hub prints gh's
message, exits with gh's status and fetches nothing.

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub merge PULLREQ-URL` merged locally with `--no-ff` and the message `Merge pull request #N from OWNER/BRANCH`, the title after a blank line. | Same. |
| A command line without a pull request URL (`hub merge master`) went to git unchanged. | Same. Also `--abort`, `--quit`, `--continue`, a URL after `--`, and a URL that is an option's value. |
| Fetched with `git fetch origin refs/pull/N/head`. | Fetches from the pull request's own repository, through the remote that points at it, else its URL. Adds `--quiet --no-tags --refmap=`. |
| Ran `git merge FETCH_HEAD --no-ff -m ...`. | Runs `git merge --no-ff -m 'Merge pull request ...' -m TITLE ... COMMIT`, where COMMIT is the fetched commit's full id. |
| Kept extra options, in order, before `FETCH_HEAD`. | Keeps them in your order, around the pull request where you typed them. |
| `--squash` dropped `--no-ff` but kept hub's message. | `--squash` drops both. `--ff` and `--ff-only` drop `--no-ff`. `-m`, `-F` and `--no-message` drop the message. |
| Refused with `Error: that fork is not available anymore` when the repository of the pull request's branch was gone. | No such check. hub fetches `refs/pull/N/head` from the pull request's repository. |

New in this hub: hub merges one pull request at a time, and another operand is
an error. A URL of some of the pull request's changes
(`.../pull/N/commits/SHA`, `.../pull/N/files/SHA`) or of its patch
(`.../pull/N.patch`) is plain `git merge`, while other pages of the pull
request, such as `.../pull/N/files`, merge it whole. `.../pull/012` is pull
request 12, as gh reads it. hub looks the pull request up through gh, so gh
2.55 or newer must be installed and logged in.

## See also

- [hub checkout](checkout.md): check out a pull request's branch instead of
  merging it.
- [hub pr](pr.md): `gh pr merge` merges on GitHub.
- [hub cherry-pick](cherry-pick.md) and [hub am](am.md): take some of a pull
  request's commits.
- [How hub works](../guide/how-hub-works.md): the git commands hub extends,
  and `--noop`.
- [Project and remotes](../guide/project-and-remotes.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-merge(1)](https://hub.github.com/hub-merge.1.html)
- gh's manual: [gh pr merge](https://cli.github.com/manual/gh_pr_merge)
- git's manual: [git merge](https://git-scm.com/docs/git-merge), also shown by
  `git merge --help`
