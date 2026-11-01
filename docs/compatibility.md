# hub 2.x compatibility

This page compares this hub with the last release of the original hub,
[hub 2.14.2](https://github.com/mislav/hub). The goal is the commands people
typed. hub 2.x's output formats and every one of its flags are not a goal.
The [README](../README.md) lists the requirements.

Two rules decide what the flags mean:

1. **hub's own commands** (`pull-request`, `browse`, `compare`, `create`,
   `fork`, `delete`, `ci-status`, `sync`, `alias`, `help`, `version`) use
   hub's flags. Each manual (`hub help COMMAND`) lists all of them; any other
   option is an error, except in `help`, which hands it to `git help`. The
   git commands hub extends keep git's options and add hub's shorthands and
   URLs.
2. **gh's commands** (`pr`, `issue`, `release`, `gist`, `api`) use
   gh's flags and output. hub renames `show` to `view`, runs `list` when no
   subcommand is given, and hands every other argument to gh unchanged. Each
   manual lists hub 2.x's options in gh's spelling.

`GITHUB_HOST` reaches gh as `GH_HOST` when `GH_HOST` is not set.

## The git commands hub extends

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub clone [-p] [OWNER/]REPO [DIR]` | Yes | `git clone URL` on the default host (`GH_HOST`, else the one host gh is logged in to, else github.com); `REPO` alone is yours; `REPO.wiki` is the wiki; every git option stays in place. | `HOST/OWNER/REPO` is plain git clone: use `GH_HOST`. The protocol is gh's `git_protocol`; `-p` is ssh once. |
| `hub remote add [-p] [NAME] OWNER[/REPO]`, `hub remote set-url` | Yes | `git remote add NAME URL`; `USER` alone names the remote and the owner; `origin` alone is your own copy. | The protocol is gh's `git_protocol`. |
| `hub fetch USER[,USER...]` | Yes | Adds each missing user's copy as a remote, then `git fetch`, or `git fetch --multiple` for a list. | |
| `hub push REMOTE1,REMOTE2 [ARGS...]` | Yes | `git push` once per remote, in order, stopping at the first failure. | Every name must be a remote before anything is pushed. |
| `hub checkout PULL-REQUEST-URL [BRANCH]` | Yes | `gh pr checkout URL [-b BRANCH]`; `-b`, `--detach` and `--recurse-submodules` pass through. | `-f` is refused: gh's `--force` resets the branch. Other options are errors. |
| `hub merge PULL-REQUEST-URL` | Yes | Fetches the pull request's head and merges it locally with the merge button's message and `--no-ff`. | A URL of some of its changes (`.../pull/N/commits/SHA`, `.../pull/N/files/SHA`) or of its patch is plain git merge; other pages of the pull request merge it whole. |
| `hub am URL`, `hub apply URL` | Partly | Pull request, commit and comparison URLs are downloaded through `gh api`: a patch series for `am`, one diff for `apply`. | Gist URLs are not supported; use `gh gist clone ID` and apply the file. |
| `hub cherry-pick COMMIT-URL` | Partly | Fetches the commit from its repository and cherry-picks it; a short id is expanded through `gh api`. | `USER@SHA` is not supported; use the commit's URL. |
| `hub init -g` | No | | Use `git init && gh repo create --source=.`. |
| `hub submodule add OWNER/REPO DIR` | No | | Use `git submodule add https://github.com/OWNER/REPO.git DIR`. |

## New commands

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub pull-request` | Partly | `gh pr create` with hub's options: `-m`, `-F`, `-e`, `--no-edit`, `-b`, `-h`, `-p`, `-f`, `-d`, `-r`, `-a`, `-M`, `-l`, `-o`, `-c`, `--no-maintainer-edits`. | `-i ISSUE` is not supported; link the issue in the body. Milestones by number are not supported; use the name. `-p` with `-h` is an error. Without `-b`, gh picks the base: `branch.NAME.gh-merge-base` with gh 2.64 and later, else the default branch. |
| `hub pr list\|show\|checkout` | gh | `gh pr list\|view\|checkout`. | `show -c` is not supported; pipe `gh pr view --json url --jq .url` to `pbcopy`. |
| `hub issue ...` | gh | `gh issue ...`; no subcommand is `list`. | `issue update` is `gh issue edit`; `issue labels` is `gh label list`. |
| `hub release ...` | gh | `gh release ...`; no subcommand is `list`. | `-a FILE` is `gh release upload TAG FILE`; `-t TARGET` is `--target`. |
| `hub gist create\|show` | gh | `gh gist create\|view`; no subcommand is `list`. | `-o` is `-w`; `-c` is not supported: pipe gh's URL to `pbcopy`. |
| `hub api ...` | gh | `gh api ...` unchanged. | `-t` and `--flat` are not supported; use `--jq`. `--cache` needs a unit (`600s`). |
| `hub browse [-u] [-c] [[OWNER/]REPO] [SUBPAGE]` | Yes | Opens the repository page; on a pushed branch other than the default, `tree` and `commits` open at that branch. Without `refs/remotes/REMOTE/HEAD`, every pushed branch counts as non-default. | Wikis are not special; use the `wiki` subpage. |
| `hub compare [-u] [-c] [-b BASE] [OWNER] [RANGE]` | Partly | Opens the compare page; `A..B` becomes `A...B`; without a range, the current branch where it pushes. | Wiki compare pages and renamed forks in the head are not supported. |
| `hub create [-p] [-d DESC] [-h URL] [[ORG/]NAME]` | Yes | `gh repo create`, then `git remote add` of the remote `origin` (any work tree, a linked one included); `--public`, `--internal`, `--remote-name`, `--push`. | Private by default; hub 2.x made public repositories. A bare repository is refused. |
| `hub fork [--no-remote] [--remote-name NAME] [--org ORG]` | Yes | GitHub's fork API through `gh api`, then the remote named after you or the organization, for the fork GitHub answers with; `--fork-name` and `--default-branch-only` too, and an existing fork is reused under its own name. | Nothing is fetched: run `git fetch NAME` once the fork exists. |
| `hub delete [-y] [ORG/]NAME` | Yes | `gh repo delete [--yes]`. | Needs the `delete_repo` scope: `gh auth refresh -s delete_repo`. |
| `hub ci-status [-v] [COMMIT]` | Partly | GitHub's combined verdict on checks and statuses; exit 0 success, 1 failure, 2 pending, 3 no status. | `-f FORMAT` and `--color` are not supported; use `gh pr checks`. `-v` shows the first 100 checks. |
| `hub sync [REMOTE]` | Partly | Fetches with `--prune`, fast-forwards branches that are behind, deletes merged branches whose upstream is gone. A branch checked out in another work tree is left alone, with a warning. | `--color` is not supported. A squash-merged branch is kept, with a warning. With git older than 2.48, git fetch does not create `refs/remotes/REMOTE/HEAD`; run `git remote set-head REMOTE --auto` once so that sync knows a non-GitHub remote's default branch. |
| `hub alias [-s] [SHELL]` | Yes | bash, zsh, sh, ksh, dash, fish, csh and tcsh. | |
| `hub help [COMMAND]`, `hub version` | Yes | Each command's manual is its module's header. | |
| `hub --noop` | Yes | Prints the git and gh commands hub would run. | For hub's commands, git's global options are not printed; a plain git command is printed as given. |

## Not implemented, on purpose

- `hub init -g`: use `git init && gh repo create --source=.`.
- `hub submodule add OWNER/REPO`: use
  `git submodule add https://github.com/OWNER/REPO.git DIR`.
- Gist URLs in `am` and `apply`: use `gh gist clone ID`, then apply the file.
- `USER@SHA` in `cherry-pick`: use the commit's URL.
- `-i ISSUE` in `pull-request`: link the issue in the body, or use `gh api`.
- Milestones by number in `pull-request`: use the milestone's name.
- `-f FORMAT` placeholders (`%I`, `%t`, ...): use gh's `--json` with `--jq`
  or `--template`.
- The `-c` clipboard flag outside `browse`, `compare`, `create` and
  `pull-request`: pipe the URL gh prints to `pbcopy`.
- `--color` in `sync` and `ci-status`: use `gh pr checks` for a colored view.
- Wiki pages in `browse` and `compare`: use `hub browse -- wiki`.
- Renamed forks as `compare` heads: use
  `hub browse -- compare/BASE...OWNER:FORK:BRANCH`.
- `HOST/OWNER/REPO` as a `clone` shorthand: use
  `GH_HOST=HOST hub clone OWNER/REPO`, or the URL.
- `hub.protocol` and `HUB_PROTOCOL`: use `gh config set git_protocol ssh`.
- `hub.host`: use `gh auth login -h HOST` and `GH_HOST`.
- hub's own login and token file: use `gh auth login`, or `GH_TOKEN`.
- Enterprise hosts on non-standard ports: hosts are recognized with the port
  ignored, and web and API URLs use the standard port.
- ssh host aliases that `ssh -G HOST` does not resolve to a GitHub host: use
  the host's real name in the remote URL.
