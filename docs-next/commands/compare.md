---
title: hub compare
description: Open a GitHub compare page for a branch or a range.
kind: hub's own command
original: https://hub.github.com/hub-compare.1.html
---

# hub compare

`hub compare` opens the GitHub compare page of a range, or of the current
branch on the repository it pushes to. It can also print the URL or copy it to
the clipboard. Use it to review what a branch or a release adds before you open
a pull request or write release notes. The most common use is
`hub compare v1.0..v1.1`, which opens the changes between two tags.

```sh
hub compare v1.0..v1.1
# => open https://github.com/mislav/dotfiles/compare/v1.0...v1.1
```

## Usage

```text
hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]
```

`START...END` is a range of branches, tags or commits. hub also accepts
`START..END` (two dots) and writes it with three dots. `END` alone is a branch,
a tag or a commit that GitHub compares with the default branch. `OWNER` is an
owner name: hub opens the compare page of OWNER's copy of the project, for
example a fork. Without a range, hub compares the current branch on the remote
it pushes to. [The project and its remotes](../guide/project-and-remotes.md)
explains which repository is the project.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git compare` is the same command. Each `# =>` line is what `hub --noop`
prints, or with `-u` the URL that hub prints. The examples run in a clone of
`mislav/dotfiles`.

Open the changes between two releases. hub turns `..` into `...`:

```sh
hub compare v1.0..v1.1
# => open https://github.com/mislav/dotfiles/compare/v1.0...v1.1
```

Open the current branch, `feature`, after you pushed it. GitHub compares it
with the default branch:

```sh
hub compare
# => open https://github.com/mislav/dotfiles/compare/feature
```

Print the URL of the current branch compared with `develop`, instead of
opening it:

```sh
hub compare -u -b develop
# => https://github.com/mislav/dotfiles/compare/develop...feature
```

Compare a branch that you do not have checked out with a base branch:

```sh
hub compare -u -b develop feature
# => https://github.com/mislav/dotfiles/compare/develop...feature
```

Copy the URL to the clipboard. With `-c` alone, hub prints nothing. With `-u`
and `-c`, hub prints the URL and copies it:

```sh
hub compare -c v2..v3
hub compare -u -c v3..v4
# => https://github.com/mislav/dotfiles/compare/v3...v4
```

Print the URL of the same range on another owner's copy of the project:

```sh
hub compare -u alice v1..v2
# => https://github.com/alice/dotfiles/compare/v1...v2
```

Print the URL of a branch on a fork, compared with the upstream project. In
this clone, `origin` is the fork `mislav/dotfiles` and `upstream` is
`github/dotfiles`. The project is `github/dotfiles`, the repository of
`upstream`. `feature` is pushed to the fork, so hub writes the branch as
`mislav:feature`:

```sh
hub compare -u
# => https://github.com/github/dotfiles/compare/mislav:feature
```

Name a range that already has three dots, or a branch on someone else's fork.
hub keeps the three dots and the `OWNER:` prefix, and escapes the space:

```sh
hub compare -u 'main...alice:my branch'
# => https://github.com/mislav/dotfiles/compare/main...alice:my%20branch
```

Print the URL of a compare page of another project with `GH_REPO`. This works
outside a repository too:

```sh
GH_REPO=cli/cli hub compare -u v1..v2
# => https://github.com/cli/cli/compare/v1...v2
```

See the URL hub would open, without opening it. `--noop` prints `open URL`, or
`copy URL` with `-c`:

```sh
hub --noop compare a..b
# => open https://github.com/mislav/dotfiles/compare/a...b
```

Use `--` before an `END` that starts with a dash:

```sh
hub compare -u -b develop -- -x
# => https://github.com/mislav/dotfiles/compare/develop...-x
```

A range needs both sides. hub refuses `v1.0..` and prints the Usage line:

```sh
hub compare v1.0..
```

```text
hub compare: not a range: v1.0..
Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]
```

## Options

| Option | What it does |
|---|---|
| `-b`, `--base BASE` | Compare `END`, or the current branch, with `BASE`. `--base=BASE` works too. hub refuses `-b` together with a range. Default: the default branch. |
| `-u`, `--url` | Print the URL instead of opening it. |
| `-c`, `--copy` | Copy the URL to the clipboard instead of opening it. With `-u`, print it and copy it. |
| `-h`, `--help` | Print the manual. |

You can combine short options, as in `-uc` or `-ubdevelop`. These are all the
options. Any other option is a usage error, and `-h` or `--help` prints the
manual.

## How it works

hub applies these rules in order:

1. hub finds the project: `GH_REPO` when it is set, else the first GitHub
   remote among `upstream`, `github` and `origin`, then the others. See
   [The project and its remotes](../guide/project-and-remotes.md).
2. With `OWNER`, hub keeps the project's host and repository name and uses
   `OWNER` instead of the project's owner. `OWNER` must be an owner name, not
   `OWNER/REPO`.
3. A range `START..END` becomes `START...END`. On GitHub, three dots show the
   commits that `END` adds, which is what `git log START..END` shows. Both
   sides must be present: hub does not read `START..` as `START..HEAD`.
4. Without a range, hub uses the current branch on its push remote, as
   [Find where a branch pushes](../guide/project-and-remotes.md#find-where-a-branch-pushes)
   explains. That remote must have a remote-tracking branch of the same name,
   `REMOTE/BRANCH`. An unborn branch counts as not pushed. hub does not
   compare the commits: local commits on top, or a remote branch that has
   moved on, are fine, and the page shows what GitHub has.
5. When that remote is a repository of another owner, hub writes the branch as
   `OWNER:BRANCH`. hub matches owners without regard to case.
6. With `-b BASE`, the range is `BASE...END`.
7. hub escapes the range for the URL. Letters, digits, `.`, `_`, `~`, `/`,
   `:`, `@` and `-` stay as they are. Every other character becomes `%XX`.
8. hub opens the URL, prints it with `-u`, or copies it with `-c`. See
   [Browser and clipboard](../guide/browser-and-clipboard.md) for the browser
   and the clipboard tool hub uses.

Without a range, hub needs a work tree, also when `GH_REPO` is set.

## Exit status

`hub compare` exits with the status of the browser, or of the clipboard tool
with `-c`. With `-u` alone, and with `-h`, it exits with 0. hub's own refusals
and usage errors exit with status 1. Outside a repository, without a range,
git's `not a git repository` message appears.

Each refusal names the word that caused it. hub quotes the word when it is
empty or holds a space, a newline or another control character, as in `''`,
`my\ owner` or `$'al\nice'`. The refusals about options and arguments also
print the Usage line. These are the messages:

| Message | What to do |
|---|---|
| `hub compare: not a range: v1.0..` | Name both sides, as in `v1.0..v1.1`. |
| `hub compare: use either -b BASE or a range, not both: a..b` | Drop `-b`, or name only `END`. |
| `hub compare: not an owner: alice/dotfiles` | Pass the owner alone: `alice`. |
| `hub compare: unexpected argument: c` | Pass at most `OWNER` and a range. |
| `hub compare: empty range` | Pass a non-empty range. |
| `hub compare: unknown option: -x` | Use `-u`, `-c`, `-b` or `-h`. Put `--` before an `END` that starts with a dash. |
| `hub compare: -b needs a value` | Give `-b` a branch name. |
| `hub compare: -b needs a branch name` | Give `-b` a non-empty value. |
| `hub compare: not on a branch (check out a branch, or name a range)` | Check out a branch, or name a range. |
| `hub compare: feature is not pushed to origin (push it first, or name a range)` | Push the branch. |
| `hub compare: cannot tell where feature pushes (git push -u REMOTE feature first, or name a range)` | Push with `-u`, or set `remote.pushDefault`. |
| `hub compare: branch.feature.pushRemote names no remote (set it to a remote, or name a range)` | Set it to a remote name. An empty value or a URL is no remote. |
| `hub compare: other does not push to a GitHub repository (name a range)` | Name a range. |
| `hub compare: other pushes to ghe.example.com, not to github.com (name a range)` | Name a range, or set `GH_REPO`. |
| `hub compare: no GitHub remote found (looked for upstream, github, origin)` | Add a GitHub remote, or set `GH_REPO`. |
| `hub compare: no browser found to open URL (set GH_BROWSER or BROWSER)`, with the compare URL in place of `URL` | Set `GH_BROWSER` or `BROWSER`, or use `-u`. |
| `hub compare: no clipboard tool found (install pbcopy, wl-copy or xclip)` | Install one of them, or use `-u`. |

## Differences from the original hub

The original hub (mislav/hub 2.x) had the same command.

| Original hub | This hub |
|---|---|
| `hub compare [-uc] [-b BASE]` and `hub compare [-uc] [OWNER] [BASE...]HEAD` | One synopsis, `hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]`. `-u`, `-c`, `-b` and their long forms `--url`, `--copy`, `--base` are the same. |
| `-b BASE` worked only when no range or head was given. | Same with no arguments. `-b BASE END` also works. `-b` with a range is a usage error in both. |
| `A..B` became `A...B`. | Same. |
| The original hub left a range that was not two simple refs, such as `@{a..b}..@{c..d}`, unchanged. | A range with a second `..`, such as `@{a..b}..@{c..d}`, is refused: `not a range`. Name the commits by their SHAs instead. Any other `A..B`, such as `HEAD^..main`, becomes `A...B`. |
| On the default branch with no `-b`, the original hub refused because the branch was the default branch. | No refusal: hub opens `compare/main`. |
| The original hub refused a `-b` equal to the pushed branch. | No refusal: hub opens `compare/main...main`. |
| A branch pushed to a fork became `OWNER:branch`. | Same. hub finds your fork by the push rules in [Find where a branch pushes](../guide/project-and-remotes.md#find-where-a-branch-pushes). |
| The head came from the branch's remote, and a full URL in `branch.BRANCH.remote` worked too. | The six push rules in [Find where a branch pushes](../guide/project-and-remotes.md#find-where-a-branch-pushes) decide. A pushRemote or pushDefault that holds a URL names no remote, and hub refuses. `push.default`, `remote.*.push` refspecs and mirror remotes are not read. |
| A branch that was not pushed got `the current branch 'master' doesn't seem pushed to a remote`. | `BRANCH is not pushed to REMOTE (push it first, or name a range)`. |
| The original hub kept `/ : ^ ~ * !` in the URL and left a range with `..` unescaped. | Only `/ : @ ~ . _ -`, letters and digits are kept. `^`, `*` and `!` become `%5E`, `%2A`, `%21`, also inside a range. |
| A wiki repository opened `/wiki/_compare/RANGE`. | Not supported. Use `hub browse -- wiki`. |
| A renamed fork worked as the head. | Not supported. Use `hub browse -- compare/BASE...OWNER:FORK:BRANCH`. |
| A range given in detached HEAD worked. | Same. Without a range, detached HEAD is refused. |
| The browser was `$BROWSER`, else `open`, `xdg-open` and others. | `GH_BROWSER`, then the `browser` setting of the GitHub CLI (gh), then `BROWSER`, then `open`, then `xdg-open`. |
| `-c` put the URL on the clipboard. | Same, with `pbcopy`, `wl-copy` or `xclip`. |
| A GitHub Enterprise project opened on its own host, as in `https://git.my.org/OWNER/dotfiles/compare/a...b`. | Same: the URL uses the project's host. `GH_REPO` can also name the project, outside a repository too. |

## See also

- [hub browse](browse.md): open other pages of a repository.
- [hub pull-request](pull-request.md): open a pull request from the current
  branch.
- [The project and its remotes](../guide/project-and-remotes.md): the project
  and where a branch pushes.
- [Browser and clipboard](../guide/browser-and-clipboard.md): `-u`, `-c` and
  the browser.
- [Coming from the original hub](../compatibility/README.md).
- The original hub's manual:
  [hub-compare(1)](https://hub.github.com/hub-compare.1.html).
- gh's manual: [gh pr create](https://cli.github.com/manual/gh_pr_create),
  whose `--web` opens the web browser to create a pull request.
- This hub's manual: [hub compare](https://brc-dd.github.io/hub/compare.html)
