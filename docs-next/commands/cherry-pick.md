---
title: hub cherry-pick
description: Cherry-pick a commit from its GitHub URL.
kind: git command hub extends
original: https://hub.github.com/hub-cherry-pick.1.html
---

# hub cherry-pick

`hub cherry-pick` is `git cherry-pick` with one addition: it also accepts a
commit's GitHub URL, fetches that commit and picks it by its full id. A command
line without a commit URL goes to `git cherry-pick` unchanged. Use it to bring a
fix from a fork or from another repository without adding a remote first. The
most common use is `hub cherry-pick COMMIT-URL`, which picks the commit at a URL
copied from the browser.

```sh
hub cherry-pick https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/rails/rails.git 0123456789abcdef0123456789abcdef01234567
# => git cherry-pick 0123456789abcdef0123456789abcdef01234567
```

## Usage

```text
hub cherry-pick [GIT-CHERRY-PICK-OPTIONS...] (COMMIT-URL | COMMIT)...
```

`COMMIT-URL` is the URL of a commit (`.../commit/SHA`) or of a pull request's
commit (`.../pull/N/commits/SHA`), on GitHub or on a GitHub Enterprise host that
hub knows (see [Hosts and login](../guide/hosts-and-login.md)). `COMMIT` is
anything `git cherry-pick` takes: a commit id, a branch, a range. You can mix
both kinds, in any order, and use several of each.

## Examples

The examples write `hub`. With the alias from
[Make git run hub](../getting-started/alias.md), `git cherry-pick` is the same
command. Each `# =>` line is what `hub --noop` prints: the git command that hub
runs. Each `# runs:` line is a lookup that hub runs even under `--noop`. The
repository has one remote, `origin`, for mislav/dotfiles. The `git_protocol`
setting of the GitHub CLI (gh) is `https`, the default (see
[Configuration](../guide/configuration.md)). The id `0123456...` stands for any
full commit id of 40 hex digits.

Pick a commit of a repository that a remote points at:

```sh
hub cherry-pick https://github.com/mislav/dotfiles/commit/0123456789abcdef0123456789abcdef01234567
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- origin 0123456789abcdef0123456789abcdef01234567
# => git cherry-pick 0123456789abcdef0123456789abcdef01234567
```

hub fetches the commit through `origin`, because `origin` points at
mislav/dotfiles.

Pick a commit by a short id:

```sh
hub cherry-pick https://github.com/cli/cli/commit/9490d20
# runs: gh api --hostname github.com repos/cli/cli/commits/9490d20 --jq .sha
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/cli/cli.git 9490d204a2ba95434153dedce99898ce9f281426
# => git cherry-pick 9490d204a2ba95434153dedce99898ce9f281426
```

A short id needs gh, and a full id does not. No remote points at cli/cli, so
hub fetches from the repository's URL, which is `git@github.com:cli/cli.git`
when gh's `git_protocol` for the host is `ssh`.

Pick a commit from a pull request's page:

```sh
hub cherry-pick https://github.com/rails/rails/pull/123/commits/0123456789abcdef0123456789abcdef01234567
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/rails/rails.git 0123456789abcdef0123456789abcdef01234567
# => git cherry-pick 0123456789abcdef0123456789abcdef01234567
```

hub fetches the commit from the repository in the URL, here rails/rails, which
also serves the commits of its pull requests.

Sign off, prefer the picked side on conflicts, and pick `main` before the URL's
commit:

```sh
hub cherry-pick --signoff -X theirs main https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/rails/rails.git 0123456789abcdef0123456789abcdef01234567
# => git cherry-pick --signoff -X theirs main 0123456789abcdef0123456789abcdef01234567
```

hub keeps every option and every other commit, such as a branch, in the place
where you typed it.

Record where the commit came from with `-x`:

```sh
hub cherry-pick -x https://github.com/rails/rails/commit/0123456789ABCDEF0123456789abcdef01234567
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/rails/rails.git 0123456789abcdef0123456789abcdef01234567
# => git cherry-pick -x 0123456789abcdef0123456789abcdef01234567
```

git writes `(cherry picked from commit FULL-ID)` in the message. hub passes the
full id in lowercase, also when the URL has it in capitals.

Pick commits from several repositories in one command line:

```sh
hub cherry-pick https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567 \
  https://github.com/mislav/dotfiles/commit/89abcdef0123456789abcdef0123456789abcdef
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/rails/rails.git 0123456789abcdef0123456789abcdef01234567
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- origin 89abcdef0123456789abcdef0123456789abcdef
# => git cherry-pick 0123456789abcdef0123456789abcdef01234567 89abcdef0123456789abcdef0123456789abcdef
```

hub looks up and fetches every commit first, in order, then runs one
`git cherry-pick` with all of them.

Pick a commit from the URL of its patch:

```sh
hub cherry-pick https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567.patch
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/rails/rails.git 0123456789abcdef0123456789abcdef01234567
# => git cherry-pick 0123456789abcdef0123456789abcdef01234567
```

hub reads other forms of a commit URL as the same commit: a `.patch` or `.diff`
suffix, a query, a `#fragment`, a trailing slash, and `http://`.

Finish a cherry-pick after a conflict, or stop it and restore the branch:

```sh
git cherry-pick --continue
git cherry-pick --abort
```

On a conflict, hub exits with git's status and leaves the cherry-pick in
progress. Resolve the conflict, then run the first command, or run the second
to stop.

Hand a command line to git with no lookup and no fetch:

```sh
hub cherry-pick main~2
# => git cherry-pick main~2
hub cherry-pick --continue
# => git cherry-pick --continue
hub cherry-pick -- https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
# => git cherry-pick -- https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
hub cherry-pick https://github.com/rails/rails/commits/abcdef1
# => git cherry-pick https://github.com/rails/rails/commits/abcdef1
hub cherry-pick --strat ort https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
# => git cherry-pick --strat ort https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
hub cherry-pick --help https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
# => git cherry-pick --help https://github.com/rails/rails/commit/0123456789abcdef0123456789abcdef01234567
```

The command lines are, in order: no URL, a sequencer option, a URL after `--`,
the URL of a commit list, an abbreviation of `--strategy`, and git's manual. git
then reports what it cannot read, for example `fatal: bad revision 'ort'` for
the abbreviated `--strat`.

## Options

`hub cherry-pick` has no options of its own. Every option of `git cherry-pick`
stays as it is and reaches git in its place. hub reads these options only to
find the operands. For each option with a value, hub reads the next word as
that value, not as a commit:

| Option | What it does |
|---|---|
| `-m`, `--mainline NUMBER` | Pick a merge commit against its parent NUMBER. git's option. |
| `--strategy STRATEGY` | Use the merge strategy STRATEGY. git's option. |
| `-X`, `--strategy-option OPTION` | Pass OPTION to the merge strategy. git's option. |
| `--cleanup MODE` | Clean up the commit message in MODE. git's option. |
| `--empty ACTION` | Handle a commit that becomes empty with ACTION. git's option. |
| `-S[KEYID]` | Sign the commit. git's option. A key id must be attached (`-SKEYID`). |
| `--`, `--end-of-options` | End the options. hub reads no commit URL after it, and the words go to git unchanged. |
| `-h`, `--help`, `--help-all` | Print git's usage or manual. hub hands the command line to git, also for a cluster with `h` such as `-xh`. |

For hub's manual, run `hub help cherry-pick`. It ends with a pointer to git's
manual, `git cherry-pick --help`.

## How it works

hub applies these rules in order:

1. hub looks at the operands before `--` or `--end-of-options`. A word that is
   the value of an option is not an operand. In
   `--cleanup https://github.com/...` the URL is the value of `--cleanup`, and
   git refuses it with `fatal: Invalid cleanup mode`.
2. An operand is a commit URL when its host is github.com, the host in
   `GH_HOST` or a host gh is logged in to (see
   [Hosts and login](../guide/hosts-and-login.md)), and its path is
   `OWNER/REPO/commit/SHA` or `OWNER/REPO/pull/N/commits/SHA`. The id has 4 to
   64 hex digits, in any case. Every other GitHub URL, such as a repository, a
   pull request or a `commits/` list, stays a word for git.
3. Without a commit URL, hub runs `git cherry-pick` with the command line
   unchanged, and gh is never asked.
4. hub must run inside a work tree. Outside one, it stops with a
   `not a git repository` message before it asks gh anything.
5. For each URL, in order, hub expands an id shorter than 40 hex digits through
   `gh api --hostname HOST repos/OWNER/REPO/commits/SHA --jq .sha` on the URL's
   host. If the id is longer than 40 hex digits, hub stops before gh runs. hub
   does not support SHA-256 commit ids (64 hex digits).
6. hub fetches each commit by its full id from the first remote that points at
   the URL's repository, in the order `upstream`, `github`, `origin`, then the
   others. Owner and repository names match in any case. Without such a
   remote, hub fetches from the repository's URL and adds no remote. See
   [The project and its remotes](../guide/project-and-remotes.md).
7. The fetch brings in no tags, updates no ref and leaves `FETCH_HEAD` as it
   was, even when it did not exist. A `FETCH_HEAD` operand next to a URL keeps
   its meaning. If your local repository already has the commit, hub picks it
   even when it cannot reach the URL's repository.
8. hub runs `git cherry-pick` with every word unchanged, except each URL, which
   becomes its full id in lowercase.

`git cherry-pick` also takes the revision walker's options, such as `--grep`
and `--author`. hub does not know that these options take a value. If you give
a commit URL as their value, hub reads it as a commit. For example, with
`--author https://github.com/OWNER/REPO/commit/SHA` hub fetches the commit, and
git gets the full id as the value of `--author`.

hub does all lookups and fetches before `git cherry-pick` runs. If one of them
fails, nothing is picked.

## Exit status

`hub cherry-pick` exits with git's status, for example 1 on a conflict or 128
for a bad revision. hub's own refusals exit with status 1:

```text
hub cherry-pick: not a commit id: https://github.com/OWNER/REPO/commit/ID
hub cherry-pick: no such commit: https://github.com/OWNER/REPO/commit/ID
hub cherry-pick: this command needs the GitHub CLI, gh (https://cli.github.com)
```

The first message is for an id longer than 40 hex digits. The second means
that gh answered with something that is not a commit id. When the gh lookup
fails, hub prints gh's message and exits with gh's status, for example
`gh: No commit found for SHA: abcdef0 (HTTP 422)`. When a fetch fails, hub
prints git's message and exits with git's status.

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub cherry-pick COMMIT-URL` | Same. |
| `hub cherry-pick USER@SHA` picked the commit SHA from USER's fork, with the repository name of the current repository | Not supported. Use the commit's URL. |
| The id in the URL went to `git cherry-pick` as written, after a fetch of a whole remote | hub expands a short id to the full id through `gh api`, and git gets the full id in lowercase. |
| `.../pull/N/commits/SHA` fetched `refs/pull/N/head` from `origin` | hub fetches the commit by its id from the URL's repository. |
| `git fetch -q --no-tags REMOTE` fetched a whole remote | `git fetch --quiet --no-tags --refmap= --no-write-fetch-head` fetches one commit, updates no ref and leaves `FETCH_HEAD` alone. |
| Without a remote for the owner, hub added `_hub-cherry-pick`, fetched and removed it | hub fetches from the repository's URL and adds no remote. |
| That URL was https by default | The URL follows gh's `git_protocol` for the host. |
| `-m N` or `--mainline N` turned off the URL handling | hub reads `-m` and `--mainline` with their value, and URLs still work. |
| hub ignored a `#fragment` | Same, and hub also ignores a query, `.patch`, `.diff` and a trailing slash. |

## See also

- [hub merge](merge.md): merge a pull request by its URL.
- [hub am](am.md): apply a commit or a pull request from its URL as patches.
- [hub fetch](fetch.md): add a user's fork as a remote and fetch it.
- [Repositories and URLs](../guide/repositories-and-urls.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [How hub works](../guide/how-hub-works.md)
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-cherry-pick(1)](https://hub.github.com/hub-cherry-pick.1.html)
- git's manual: [git cherry-pick](https://git-scm.com/docs/git-cherry-pick)
- This hub's manual:
  [hub cherry-pick](https://brc-dd.github.io/hub/cherry-pick.html)
