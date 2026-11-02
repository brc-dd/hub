---
title: hub pull-request
description: Open a pull request for the current branch.
kind: hub's own command
original: https://hub.github.com/hub-pull-request.1.html
---

# hub pull-request

`hub pull-request` opens a pull request for the current branch. hub finds the
repository that the branch pushes to, checks that the branch is pushed there,
and runs `gh pr create` of the GitHub CLI (gh) in the
[project](../guide/project-and-remotes.md). Use it to open a pull request
without leaving the terminal. The most common use is
`hub pull-request -p -m 'Fix the bug'`, which pushes the branch and opens the
pull request in one step.

```sh
hub pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- origin HEAD:refs/heads/feature
# => gh pr create --repo github.com/mislav/dotfiles --head feature --title Fix\ the\ bug --body ''
```

## Usage

```text
hub pull-request [-fpdoc] [-b [OWNER[/REPO]:]BASE] [-h [OWNER:]HEAD] [-m MESSAGE]...
                 [-F FILE] [-e | --no-edit] [-r LIST] [-a LIST] [-M MILESTONE] [-l LIST]
                 [--no-maintainer-edits]
```

The command takes no operands, only options. `BASE` is the base branch, the
branch to merge into. `HEAD` is the head branch, the branch with the changes.
A `LIST` is comma-separated.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git pull-request` is the same command. Each `# =>` line is what `hub --noop`
prints: the git or gh command that hub runs. A `# runs:` line is a command that
hub runs when the example has no `--noop`. The examples run in a clone of
`mislav/dotfiles`. The current branch is `feature`, and `origin` is the only
remote. `LOGIN` stands for your GitHub login.

Push the current branch and open the pull request. `feature` has no upstream
yet, so hub sets one:

```sh
hub --noop pull-request -p -m 'Fix the bug'
# => git push --set-upstream -- origin HEAD:refs/heads/feature
# => gh pr create --repo github.com/mislav/dotfiles --head feature --title Fix\ the\ bug --body ''
```

Without `--noop`, gh then prints the URL of the new pull request.

Open the pull request for a branch you pushed already, or skip the check that
it is pushed with `-f`:

```sh
hub pull-request -f -m 'Fix the bug'
```

Give a title and a body. Each `-m` is one paragraph: the first is the title,
and the rest is the body. hub does not check that a head branch named with
`-h` is pushed:

```sh
hub --noop pull-request -h alice:topic -m 'Fix the bug' -m 'It was broken.'
# => gh pr create --repo github.com/mislav/dotfiles --head alice:topic --title Fix\ the\ bug --body It\ was\ broken.
```

Read the message from a file, or from standard input with `-F -`:

```sh
printf 'Fix the bug\n\nIt was broken.\n' | hub --noop pull-request -f -F -
# => gh pr create --repo github.com/mislav/dotfiles --head feature --title Fix\ the\ bug --body It\ was\ broken.
```

Take the title and body from the first commit on the branch:

```sh
hub --noop pull-request -f --no-edit
# => gh pr create --repo github.com/mislav/dotfiles --head feature --fill-first
```

Write the message in gh's editor, starting from a file. This needs a terminal.
`message.txt` holds `Fix the bug`, a blank line and `It was broken.`:

```sh
hub pull-request -e -F message.txt
# runs: gh pr create --repo github.com/mislav/dotfiles --head feature --title 'Fix the bug' --body 'It was broken.' --editor
```

Open a draft, request reviews from a user and a team, and add an assignee, a
milestone and labels:

```sh
hub --noop pull-request -f -d -r alice,org/team -a bob -M 'Version 1.0' -l bug,ui -m 'Fix the bug'
# => gh pr create --repo github.com/mislav/dotfiles --head feature --title Fix\ the\ bug --body '' --draft --reviewer alice\,org/team --assignee bob --milestone Version\ 1.0 --label bug\,ui
```

Open the pull request against another base branch, or against a branch in
alice's fork. When the base is in another repository, hub names the head
branch `OWNER:BRANCH`:

```sh
hub pull-request -b develop -m 'Fix the bug'
# runs: gh pr create --repo github.com/mislav/dotfiles --base develop --head feature ...
hub --noop pull-request -f -b alice:develop -m 'Fix the bug'
# => gh pr create --repo github.com/alice/dotfiles --base develop --head mislav:feature --title Fix\ the\ bug --body ''
```

Open the pull request against a fork with another name, with
`OWNER/REPO:BRANCH`:

```sh
hub --noop pull-request -f -b alice/fork:main --no-maintainer-edits -m Fix
# => gh pr create --repo github.com/alice/fork --base main --head mislav:feature --title Fix --body '' --no-maintainer-edit
```

Work from your fork. In a clone of `octocat/dotfiles`, after `hub fork`,
`origin` is the parent and the remote `LOGIN` is your fork. `-p` pushes to the
fork, and the pull request goes to the parent:

```sh
hub pull-request -p -m 'Fix the bug'
# runs: git push --set-upstream -- LOGIN HEAD:refs/heads/feature
# runs: gh pr create --repo github.com/octocat/dotfiles --head LOGIN:feature ...
```

Open the new pull request in the browser and copy its URL. hub finds it by
its head branch:

```sh
hub --noop pull-request -f -o -c -m 'Fix the bug'
# => gh pr create --repo github.com/mislav/dotfiles --head feature --title Fix\ the\ bug --body ''
# => gh api --hostname github.com repos/mislav/dotfiles/pulls\?head=mislav:feature\&state=open --jq .\[0\].html_url
# => copy URL
# => open URL
```

Outside a clone, set `GH_REPO` to name the project, and name the head branch
with `-h`:

```sh
GH_REPO=octocat/dotfiles hub pull-request -h LOGIN:topic -m 'Fix the bug'
# runs: gh pr create --repo github.com/octocat/dotfiles --head LOGIN:topic ...
```

Open the pull request for a branch that is not pushed. hub refuses:

```sh
hub --noop pull-request -m 'Fix the bug'
```

```text
hub pull-request: feature is not pushed to origin (use -p to push it, or -f to skip the check)
```

## Options

| Option | What it does |
|---|---|
| `-m`, `--message MESSAGE` | Give a paragraph of the message. Repeat it for more paragraphs. |
| `-F`, `--file FILE` | Read the message from `FILE`. `-` is standard input. Cannot be combined with `-m`. |
| `-e`, `--edit` | Write the message in gh's editor (`--editor`), starting from `-m` or `-F`. Needs a terminal. |
| `--no-edit` | Take the message from the first commit (gh's `--fill-first`). Not with `-m`, `-F`, `-e` or `-h`. |
| `-b`, `--base BASE` | Merge into this branch: `BRANCH`, `OWNER:BRANCH` or `OWNER/REPO:BRANCH`. Default: gh picks it. |
| `-h`, `--head HEAD` | Name the branch with the changes, `BRANCH` or `OWNER:BRANCH`. Not checked. Default: the current branch. |
| `-p`, `--push` | Push the current branch first. Not with `-h`. |
| `-f`, `--force` | Skip the check that the current branch is pushed. |
| `-d`, `--draft` | Open the pull request as a draft. |
| `-r`, `--reviewer LIST` | Request reviews from these users or `ORG/TEAM`s. Repeatable. |
| `-a`, `--assign LIST` | Assign these users. Repeatable. |
| `-M`, `--milestone MILESTONE` | Add the pull request to this milestone. |
| `-l`, `--labels LIST` | Add these labels. Repeatable. |
| `--no-maintainer-edits` | Do not let maintainers push to the head branch (gh's `--no-maintainer-edit`). |
| `-o`, `--browse` | Open the pull request in the browser. |
| `-c`, `--copy` | Copy the pull request's URL to the clipboard. |

These are all the options. Long options take their value as `--base=develop`
or `--base develop`. Short options cluster: `-dralice` is `-d -r alice`. Any
other option, and any operand, is a usage error, and `--help` prints the
manual.

## How it works

hub applies these rules in order:

1. hub reads the options and refuses contradictions before it pushes or calls
   gh: `-m` with `-F`, `-e` with `--no-edit`, `--no-edit` with `-m`, `-F` or
   `-h`, and `-p` with `-h`.
2. hub splits the message. The first paragraph is the title, its lines trimmed
   and joined by a space. The rest is the body, as written, without leading
   and trailing blank lines or a carriage return at the end of a line. hub
   refuses an empty title unless you give `-e`.
3. Without `-m`, `-F` or `--no-edit`, gh asks for the title and body. gh asks,
   and opens its editor for `-e`, only when standard input and output are a
   terminal, `GH_PROMPT_DISABLED` is unset and gh's `prompt` setting is not
   `disabled`. Otherwise hub refuses before it pushes.
4. The project comes from `GH_REPO` or the remotes, as
   [Project and remotes](../guide/project-and-remotes.md) explains.
   `-b OWNER:BASE` moves the pull request to `OWNER`'s repository of the same
   name.
5. Without `-h`, the head branch is the current branch, under its own name, in
   the repository that it pushes to. hub takes that repository's remote from
   the first of these that applies: `branch.BRANCH.pushRemote`,
   `remote.pushDefault`, an upstream branch of the same name, the only remote,
   the only remote of a repository that you own (such as the fork that
   [hub fork](fork.md) adds), then `origin`. That repository must be on the
   project's host. If it is not the base repository, hub names the head branch
   `OWNER:BRANCH`, with `OWNER` from the push URL:
   `https://github.com/Mislav/dotfiles.git` gives `Mislav:feature`.
6. Unless you give `-p` or `-f`, the branch must be pushed: the push remote's
   tracking branch must contain every local commit.
7. `-p` runs `git push -- REMOTE HEAD:refs/heads/BRANCH`, so a tag named like
   the branch does not get in the way. hub adds `--set-upstream` when the
   branch has no upstream, when its upstream is a local branch, or when its
   upstream is the start point it was created from, such as `origin/main`
   after `git checkout -b fix origin/main`. If `branch.BRANCH.pushRemote` or
   `remote.pushDefault` is set, hub keeps a start point on another remote as
   the upstream.
8. hub runs `gh pr create --repo HOST/OWNER/REPO`, with `--base` when you give
   `-b`. Without `-b`, gh picks the base: `branch.BRANCH.gh-merge-base` (gh 2.64
   and later), else the default branch.
9. For `-o` and `-c`, hub finds the open pull request from the head branch with
   `gh api`, then copies and opens its URL. hub picks the browser and the
   clipboard tool (`pbcopy`, then `wl-copy`, then `xclip`) as
   [Browser and clipboard](../guide/browser-and-clipboard.md) explains.

hub ignores `remote.*.push` refspecs, `push.default` and mirror settings when
it names the head branch. With `-p`, git refuses to push to a mirror remote,
and hub relays git's message.

gh does not accept an organization as the `OWNER` in `--head OWNER:BRANCH`
(gh's [issue 10093](https://github.com/cli/cli/issues/10093)), and hub passes
the head branch to gh unchanged. Open a pull request from an organization's
fork to another owner's repository on GitHub's website instead.

## Exit status

`hub pull-request` exits with git's or gh's status when one of them fails, and
then opens nothing. Otherwise it exits with the status of the browser or the
clipboard tool. hub copies the URL first, then opens the browser, so the
browser still opens when the copy fails. hub's own refusals and usage errors
exit with status 1. The usage errors also print the Usage line. These are the
messages, for the branch `feature` that pushes to `origin`:

| Message | What to do |
|---|---|
| `hub pull-request: feature is not pushed to origin (use -p to push it, or -f to skip the check)` | Push it with `-p`, or skip the check with `-f`. |
| `hub pull-request: 2 commits of feature are not pushed to origin/feature (use -p to push them, or -f to skip the check)` | Push them with `-p`, or skip the check with `-f`. With one commit, the message starts `1 commit of feature is`. |
| `hub pull-request: -p pushes the current branch (push the head yourself, and name it with -h)` | Push the head branch yourself, and drop `-p`. |
| `hub pull-request: the title is empty (give it with -m or -F)` | Give a title. |
| `hub pull-request: gh prompts for the title and body, which needs a terminal (give the message with -m or -F)` | Give the message with `-m` or `-F`. |
| `hub pull-request: -e opens gh's editor, which needs a terminal (give the message with -m or -F)` | Run it in a terminal, or drop `-e`. |
| `hub pull-request: cannot read the message from missing.txt` | Name a file that exists. |
| `hub pull-request: not on a branch (name the head with -h [OWNER:]BRANCH)` | Check out a branch, or name the head with `-h`. |
| `hub pull-request: cannot tell where feature pushes (git push -u REMOTE feature first, or name the head with -h)` | Push with `-u`, set `remote.pushDefault`, or name the head with `-h`. |
| `hub pull-request: origin does not push to a GitHub repository (name the head with -h)` | Name the head with `-h`. |
| `hub pull-request: origin pushes to ghe.example.com, not to github.com (name the head with -h)` | Name the head with `-h`, or set `GH_REPO`. |
| `hub pull-request: not a base: alice: (use -b [OWNER[/REPO]:]BRANCH)` | Give `-b` a branch name, as in `alice:main`. |
| `hub pull-request: -m and -F cannot be combined` | Use one of the two. |
| `hub pull-request: -e and --no-edit cannot be combined` | Use one of the two. |
| `hub pull-request: --no-edit takes the message from the first commit (drop -m and -F)` | Drop `-m` and `-F`, or `--no-edit`. |
| `hub pull-request: --no-edit cannot be used with -h (give the message with -m or -F)` | Give the message with `-m` or `-F`. |
| `hub pull-request: -i is not supported (use gh api to attach a pull request to an issue, or link it in the body)` | Write `Fixes #123` in the body. |
| `hub pull-request: unknown option: --fill` | Run `gh pr create` for gh's options. |
| `hub pull-request: unexpected argument: extra` | Pass options only. |
| `hub pull-request: -b needs a branch name` | Give `-b` a non-empty value. |
| `hub pull-request: -m needs a value` | Give `-m` a value. |
| `hub pull-request: no open pull request from feature was found after gh pr create (gh api --hostname github.com 'repos/mislav/dotfiles/pulls?head=mislav:feature&state=open')` | Find the pull request on GitHub. gh found none open, for example after its "Continue in browser". |
| `hub pull-request: no browser found to open URL (set GH_BROWSER or BROWSER)`, with the pull request's URL in place of `URL` | Set `GH_BROWSER` or `BROWSER`. |
| `hub pull-request: no clipboard tool found (install pbcopy, wl-copy or xclip)` | Install one of them. |
| `hub pull-request: this command needs the GitHub CLI, gh (https://cli.github.com)` | Install gh. |

## Differences from the original hub

| Original hub | This hub |
|---|---|
| Opened an editor when no message was given, with a list of the commits. | gh prompts for the title and body in a terminal. `-e` opens gh's editor. hub refuses without a terminal. |
| Kept the message in `.git/PULLREQ_EDITMSG` and used `core.commentchar`. | gh handles the editor. hub writes no message file. |
| `-i ISSUE`, or an issue URL, turned an issue into a pull request. | Not supported. To link the issue, write `Fixes #123` in the body, for example `-m 'Fix the bug' -m 'Fixes #123'`. |
| `-M` took a milestone number (deprecated). | Not supported. Use the milestone's name. |
| The default base was the default branch of the project. | gh picks it: `branch.BRANCH.gh-merge-base` with gh 2.64 and later, else the default branch. |
| `-p` ran `git push --set-upstream origin HEAD:BRANCH`. | `-p` pushes to the branch's push remote, your fork included, and keeps an upstream of the branch's own name. |
| `-p` and `-h` could be given together. | An error: push the head branch yourself and name it with `-h`. |
| Retried after an HTTP 422 for `HUB_RETRY_TIMEOUT` seconds. | No retry. `HUB_RETRY_TIMEOUT` is not read. |
| `-o` and `-c` replaced printing the URL. | gh prints the URL, and `-o` and `-c` act after it. |
| Messages started with `Aborted:` or `Error creating pull request:`. | hub's messages start with `hub pull-request:`, and gh's reach you unchanged. |
| Other options were errors. | Same. hub refuses `--fill`, `-R` and gh's other options. Run `gh pr create` for them. |
| `-m` and `-F` split the title from the body at the first blank line, and repeated `-m` were joined with a blank line. | Same. |
| `--no-edit` took the message from the first commit, and `-f` skipped the check that the branch was pushed. | Same. |
| `-b OWNER/REPO:BRANCH` and `ORG/TEAM` reviewers worked, and repeated `-a`, `-r` and `-l` added up. | Same. |

## See also

- [hub fork](fork.md): fork the project, to push your branch to the fork.
- [hub compare](compare.md): see what the branch adds before you open the pull
  request.
- [hub pr](pr.md): list, view and check out pull requests.
- [hub push](push.md): push the branch to several remotes.
- [Project and remotes](../guide/project-and-remotes.md): the project and where
  a branch pushes.
- [Browser and clipboard](../guide/browser-and-clipboard.md): `-o`, `-c` and
  the browser.
- [Hosts and login](../guide/hosts-and-login.md)
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-pull-request(1)](https://hub.github.com/hub-pull-request.1.html)
- gh's manual: [gh pr create](https://cli.github.com/manual/gh_pr_create)
- This hub's manual:
  [hub pull-request](https://brc-dd.github.io/hub/pull-request.html)
