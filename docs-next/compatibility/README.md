---
title: Coming from the original hub
description: What changed between the original hub (mislav/hub 2.x) and this hub, command by command.
---

# Coming from the original hub

This page is for people who used the original hub (mislav/hub 2.x, last
release 2.14.2) and want to know what still works. It compares the two command
by command and lists the flags that moved, the defaults that changed and the
settings that are gone. hub keeps the commands people typed, not every flag or
output format. With [the alias](../getting-started/alias.md), `git` runs the
same commands.

Install bash 5, git 2.30 and the GitHub CLI (gh) 2.55 or newer. Log in with
`gh auth login`. hub has no token or settings file of its own. See
[Install hub](../getting-started/install.md).

## What stayed the same

The everyday commands keep their form. The examples run in a clone of
`OWNER/REPO`, on a branch named `feature`. `LOGIN` is your GitHub login.

A comment `# => CMD` is a git or gh command that hub runs, as `hub --noop`
prints it when gh's `git_protocol` setting has its default value, https. See
[Settings that changed](#settings-that-changed). A comment `# => open URL` means
that hub opens the URL in the browser. Any other comment is a line that hub
prints. To run a command, leave out `--noop`.

```sh
hub clone OWNER/REPO               # => git clone https://github.com/OWNER/REPO.git
hub browse -- issues               # => open https://github.com/OWNER/REPO/issues
hub compare v1.0..v1.1             # => open https://github.com/OWNER/REPO/compare/v1.0...v1.1
hub --noop push origin,upstream
# => git push origin HEAD
# => git push upstream HEAD
hub --noop fork --org acme
# => gh api ... repos/OWNER/REPO/forks -f organization=acme ...
# => git remote add -- acme https://github.com/acme/REPO.git
hub checkout https://github.com/cli/cli/pull/123 fix-it
# => gh pr checkout https://github.com/cli/cli/pull/123 -b fix-it
hub --noop delete -y recipes       # => gh repo delete github.com/LOGIN/recipes --yes
hub --noop pull-request -f -m 'Fix the bug'
# => gh pr create --repo github.com/OWNER/REPO --head feature --title Fix\ the\ bug --body ''
```

`hub merge PULL-REQUEST-URL` still merges locally, with the merge button's
message and `--no-ff`. It does not merge on GitHub. `hub ci-status` keeps its
exit statuses: 0 success, 1 failure or error, 2 pending, 3 no status.

## Three rules for flags

Each rule matches one kind of command. See
[How hub works](../guide/how-hub-works.md).

1. hub's own commands (`alias`, `browse`, `ci-status`, `compare`, `create`,
   `delete`, `fork`, `help`, `pull-request`, `sync`, `version`) use hub's
   flags. Each manual (`hub help COMMAND`) lists all of them. Any other
   option is an error, except in `help`, which hands it to `git help`.
2. git commands hub extends (`am`, `apply`, `checkout`, `cherry-pick`, `clone`,
   `fetch`, `merge`, `push`, `remote`) keep git's options and add hub's
   shorthands and URLs.
3. gh commands (`api`, `gist`, `issue`, `pr`, `release`) use gh's flags and
   output. For gist, issue, pr and release, hub renames `show` to `view` and
   runs `list` when no subcommand is given. hub api hands every argument to gh
   unchanged. Each manual lists the original hub's options in gh's spelling.

```sh
hub ci-status -f %t      # hub ci-status: unknown option: -f
hub issue show 7         # => gh issue view 7
hub pr                   # => gh pr list
```

The first line follows rule 1. The other two follow rule 3.

## Command by command

The first column links the original manual and the second links hub's page.
Status: Same (works as before), Partly (some forms are not supported), Changed
(a different flag or default), gh (gh does the work, with gh's flags and
output), Not supported (hub has no such command and hands the line to git
unchanged; the Notes say what to run).

### hub's own commands

| Original hub | This hub | Status | Notes |
|---|---|---|---|
| [`hub pull-request [-focpd] [-b BASE] [-h HEAD] ...`](https://hub.github.com/hub-pull-request.1.html) | [`pull-request`](../commands/pull-request.md) | Partly | Runs `gh pr create` with hub's options: `-m`, `-F`, `-e`, `--no-edit`, `-b`, `-h`, `-p`, `-f`, `-d`, `-r`, `-a`, `-M`, `-l`, `-o`, `-c`, `--no-maintainer-edits`. `-i ISSUE` and milestones by number are not supported. |
| [`hub browse [-uc] [[USER/]REPOSITORY\|--] [SUBPAGE]`](https://hub.github.com/hub-browse.1.html) | [`browse`](../commands/browse.md) | Changed | Same options. `HOST/OWNER/REPO` and URLs are new. A wiki clone is not special: use the `wiki` subpage. |
| [`hub compare [-uc] [-b BASE]`, `[OWNER] [BASE...]HEAD`](https://hub.github.com/hub-compare.1.html) | [`compare`](../commands/compare.md) | Partly | `A..B` becomes `A...B`, and `-b` now also works with a `HEAD` operand. Wiki compare pages and a renamed fork as the `HEAD` operand are not supported. |
| [`hub create [-poc] [-d DESCRIPTION] [-h HOMEPAGE] [[ORGANIZATION/]NAME]`](https://hub.github.com/hub-create.1.html) | [`create`](../commands/create.md) | Changed | Runs `gh repo create`, then `git remote add`. Private by default; `--public`, `--internal` and `--push` are new. hub refuses a bare repository. |
| [`hub fork [--no-remote] [--remote-name REMOTE] [--org ORGANIZATION]`](https://hub.github.com/hub-fork.1.html) | [`fork`](../commands/fork.md) | Changed | Same options, plus `--fork-name`, `--default-branch-only` and an `ORG` operand. hub fetches nothing. |
| [`hub delete [-y] [ORGANIZATION/]NAME`](https://hub.github.com/hub-delete.1.html) | [`delete`](../commands/delete.md) | Changed | Runs `gh repo delete [--yes]`. Without `-y`, gh asks you to type the repository's name. Needs the `delete_repo` scope: `gh auth refresh -s delete_repo`. |
| [`hub ci-status [-v] [COMMIT]`](https://hub.github.com/hub-ci-status.1.html) | [`ci-status`](../commands/ci-status.md) | Partly | GitHub's combined verdict on checks and statuses. `-f FORMAT` and `--color` are not supported. `-v` shows the first 100 checks. |
| [`hub sync [--color]`](https://hub.github.com/hub-sync.1.html) | [`sync`](../commands/sync.md) | Partly | `--color` is not supported, and a `REMOTE` operand is new. A branch without an upstream is left alone, where the original used the remote's branch of the same name. hub keeps a squash-merged branch and prints a warning. |
| [`hub alias [-s] [SHELL]`](https://hub.github.com/hub-alias.1.html) | [`alias`](../commands/alias.md) | Partly | bash, zsh, sh, ksh, dash, fish, csh and tcsh. `dash` is new. `rc` is not supported. |
| [`hub help COMMAND`](https://hub.github.com/hub-help.1.html), `hub version` | [`help`](../commands/help.md), [`version`](../commands/version.md) | Changed | `hub help NAME` prints the manual as text. `hub version` prints hub's version, then git's, then gh's. |
| `hub --noop COMMAND` | [`hub`](../commands/hub.md) | Same | Prints the git and gh commands that change something. For every command hub handles, hub leaves out git's global options. A plain git command prints them. |

### Git commands hub extends

| Original hub | This hub | Status | Notes |
|---|---|---|---|
| [`hub clone [-p] [OPTIONS] [USER/]REPOSITORY [DESTINATION]`](https://hub.github.com/hub-clone.1.html) | [`clone`](../commands/clone.md) | Partly | `REPO` alone is your repository of that name, and `REPO.wiki` is its wiki. hub hands `HOST/OWNER/REPO` to git clone unchanged; for another host, set `GH_HOST`. The URL follows gh's `git_protocol` setting, and `-p` uses ssh for this clone only. |
| [`hub remote add [-p] [OPTIONS] USER[/REPOSITORY]`](https://hub.github.com/hub-remote.1.html), `hub remote set-url` | [`remote`](../commands/remote.md) | Partly | `USER` alone names the remote and the owner. `origin` alone adds your own repository of the same name. `OWNER/REPO` alone is not supported: name the remote, `hub remote add OWNER OWNER/REPO`. |
| [`hub fetch USER[,USER2...]`](https://hub.github.com/hub-fetch.1.html) | [`fetch`](../commands/fetch.md) | Changed | Adds each user's fork as a remote if it is missing, then runs `git fetch`, or `git fetch --multiple` for a list. `--multiple USER1 USER2` is plain git fetch: write `USER1,USER2`. hub refuses a user without a copy of the project, and a user name that matches a remote except for case. |
| [`hub push REMOTE[,REMOTE2...] [REF]`](https://hub.github.com/hub-push.1.html) | [`push`](../commands/push.md) | Same | `git push` once per remote, in order, stopping at the first failure. Every name must be a remote before anything is pushed. |
| [`hub checkout PULLREQ-URL [BRANCH]`](https://hub.github.com/hub-checkout.1.html) | [`checkout`](../commands/checkout.md) | Changed | Runs `gh pr checkout URL [-b BRANCH]`. `-b`, `--detach` and `--recurse-submodules` pass through. `-f` is refused, because gh's `--force` resets the branch. |
| [`hub merge PULLREQ-URL`](https://hub.github.com/hub-merge.1.html) | [`merge`](../commands/merge.md) | Same | Fetches the pull request's branch and merges it locally. For a URL of the pull request's commits or its patch, hub runs plain `git merge`. |
| [`hub am [-3] GITHUB-URL`](https://hub.github.com/hub-am.1.html), [`hub apply GITHUB-URL`](https://hub.github.com/hub-apply.1.html) | [`am`](../commands/am.md), [`apply`](../commands/apply.md) | Partly | hub downloads pull request, commit and `compare/BASE...HEAD` URLs through `gh api`. Gist URLs are not supported: run `gh gist clone ID` and apply the file. |
| [`hub cherry-pick COMMIT-URL`](https://hub.github.com/hub-cherry-pick.1.html), `hub cherry-pick USER@SHA` | [`cherry-pick`](../commands/cherry-pick.md) | Partly | Fetches the commit from its repository and cherry-picks it. `USER@SHA` is not supported: use the commit's URL. |
| [`hub init -g`](https://hub.github.com/hub-init.1.html) | [`init`](../commands/init.md) | Not supported | Run `git init`, then `gh repo create --source=.`. |
| [`hub submodule add [-p] [OPTIONS] [USER/]REPOSITORY DESTINATION`](https://hub.github.com/hub-submodule.1.html) | [`submodule`](../commands/submodule.md) | Not supported | Run `git submodule add https://github.com/OWNER/REPO.git DIR`. |

### gh commands

| Original hub | This hub | Status | Notes |
|---|---|---|---|
| [`hub pr list\|checkout\|show`](https://hub.github.com/hub-pr.1.html) | [`pr`](../commands/pr.md) | gh | `gh pr list\|checkout\|view`. `show -c` is not supported: pipe `gh pr view --json url --jq .url` to `pbcopy`. |
| [`hub issue [show\|create\|update\|labels\|transfer]`](https://hub.github.com/hub-issue.1.html) | [`issue`](../commands/issue.md) | gh | `gh issue ...`. hub hands `update` and `labels` to gh unchanged: run `hub issue edit` for `update`, and `gh label list` for `labels`. |
| [`hub release [show\|create\|edit\|download\|delete]`](https://hub.github.com/hub-release.1.html) | [`release`](../commands/release.md) | gh | `gh release ...`. `-a FILE` is `gh release upload TAG FILE`, and `-t TARGET` is `--target`. |
| [`hub gist create\|show`](https://hub.github.com/hub-gist.1.html) | [`gist`](../commands/gist.md) | gh | `gh gist create\|view`. `-o` is `-w`. `-c` is not supported: pipe gh's URL to `pbcopy`. |
| [`hub api [-it] [-X METHOD] ... ENDPOINT`](https://hub.github.com/hub-api.1.html) | [`api`](../commands/api.md) | gh | `gh api` with every argument unchanged. `-t` and `--flat` are not supported: use `--jq`. |

## Renamed or moved flags

hub's own commands keep the original letters. The flags in this table moved
because gh owns the command now. Each gh command's manual has the full list.

| Original hub | This hub |
|---|---|
| `hub pr list -h BRANCH -b BASE` | `hub pr list -H BRANCH -B BASE` (no `OWNER:` prefix) |
| `hub pr list -o KEY [-^]` | `hub pr list -S 'sort:KEY-desc'` (`sort:KEY-asc`) |
| `hub pr checkout 12 BRANCH` | `hub pr checkout 12 -b BRANCH` |
| `hub pr show -u` | `hub pr view --json url --jq .url` |
| `-f FORMAT` on `pr`, `issue`, `release` | `--json FIELDS` with `--jq EXPR` or `-t TEMPLATE` |
| `hub issue -c CREATOR -@ USER` | `hub issue list -A CREATOR --mention USER` |
| `hub issue -M MILESTONE` | `hub issue list -m MILESTONE` |
| `hub issue -d DATE` | `hub issue list -S 'updated:>=DATE'` |
| `hub issue create -m MESSAGE` | `hub issue create -t TITLE -b BODY` |
| `hub issue create -o` | `hub issue create -w` |
| `hub issue update N -s closed` | `hub issue close N` (`hub issue reopen N` for open) |
| `hub release create -m MESSAGE` | `hub release create TAG --title TITLE --notes TEXT` |
| `hub release create -F FILE` | `hub release create TAG --notes-file FILE --title TITLE` |
| `hub release create -t TARGET` | `hub release create TAG --target TARGET` (gh's `-t` is the title) |
| `hub release download TAG -i GLOB` | `hub release download TAG -p GLOB` |
| `hub gist create -o` | `hub gist create -w` |
| `hub api --cache 600` | `hub api --cache 600s` (a duration with its unit) |

```sh
hub --noop release create v1.0 --target main dist.tgz   # => gh release create v1.0 --target main dist.tgz
hub api --cache 600s repos/cli/cli                      # => gh api --cache 600s repos/cli/cli
```

## Changed defaults

- `hub create` makes a private repository. The original made public ones. Pass
  `--public` for a public repository.
- `hub browse` treats a wiki clone like any repository. Open the wiki with
  `hub browse -- wiki`.
- `hub pr show` prints the pull request in the terminal, as `gh pr view` does.
  Add `-w` to open it in the browser.
- `hub fork` and `hub create` add the remote and fetch nothing. To fetch, run
  `git fetch REMOTE` after GitHub creates the repository. `REMOTE` is the name
  of the remote that hub added.
- `hub fork --remote-name origin` refuses when `origin` exists. The original
  renamed `origin` to `upstream`.
- `hub delete` without `-y` asks you to type the repository's name.
- Clone and remote URLs follow gh's `git_protocol` setting. If it is not set,
  hub uses https.

The two `hub create` lines run in a new repository named `REPO` with no remote.
The other two run in the clone of `OWNER/REPO`.

```sh
hub --noop create
# => gh repo create github.com/LOGIN/REPO --private
# => git remote add -- origin https://github.com/LOGIN/REPO.git
hub --noop create --public # => gh repo create github.com/LOGIN/REPO --public ...
hub browse -- wiki         # => open https://github.com/OWNER/REPO/wiki
hub pr show 12             # => gh pr view 12
```

## Settings that changed

hub reads gh's login, hosts and `git_protocol` setting, and no file of its own.
See [Configuration](../guide/configuration.md) for every setting hub reads, and
[Browser and clipboard](../guide/browser-and-clipboard.md) for the tools hub
uses to copy a URL.

| Original hub | This hub |
|---|---|
| `hub.protocol`, `HUB_PROTOCOL` | `gh config set git_protocol ssh` |
| `hub.host` | `gh auth login -h HOST`, and `GH_HOST` for the default host |
| `GITHUB_HOST` | Read as `GH_HOST` when `GH_HOST` is not set |
| `~/.config/hub` and its token | `gh auth login`, or `GH_TOKEN` |
| `HUB_VERBOSE` | Not read |
| `BROWSER` | `GH_BROWSER`, then `gh config set browser CMD`, then `BROWSER` |

```sh
GH_HOST=ghe.example.com hub --noop clone OWNER/REPO       # => git clone https://ghe.example.com/OWNER/REPO.git
GITHUB_HOST=ghe.example.com hub --noop clone OWNER/REPO   # => git clone https://ghe.example.com/OWNER/REPO.git
```

## What is not supported

Some original forms are gone on purpose, each with a way to do it with git or
gh. [Not supported](not-supported.md) lists them all. To choose between hub and
gh for a task, see [hub and gh](hub-vs-gh.md).

```sh
hub --noop init -g                    # => git init -g
hub --noop issue update 7 -s closed   # => gh issue update 7 -s closed
```

hub has no `init`, so it hands the first line to git unchanged. It hands the
second line to gh unchanged.

## See also

- [Not supported](not-supported.md)
- [hub and gh](hub-vs-gh.md)
- [Install hub](../getting-started/install.md)
- [Make git run hub](../getting-started/alias.md)
- [How hub works](../guide/how-hub-works.md)
- [Configuration](../guide/configuration.md)
- [Browser and clipboard](../guide/browser-and-clipboard.md)
- [hub's manuals](https://brc-dd.github.io/hub/)
- [the original hub's manuals](https://hub.github.com/)
- [gh's manual](https://cli.github.com/manual/)
