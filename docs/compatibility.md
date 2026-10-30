# hub 2.x compatibility

How this hub compares with the last Go release, [hub 2.14.2](https://github.com/mislav/hub).
The intent is to cover the commands people typed, not to reproduce hub 2.x's
output formats or every flag; shared command names follow gh.

Two rules decide what the flags mean:

1. **Commands that only hub has** (`pull-request`, `browse`, `compare`,
   `create`, `fork`, `delete`, `ci-status`, `sync`, `alias`, and the extended
   git commands) use **hub's flags**, translated to gh or git.
2. **Commands gh also has** (`pr`, `issue`, `release`, `api`, `gist`) use
   **gh's flags and output**. hub only maps the old subcommand names and
   argument shapes gh lacks, then hands over to gh unchanged.

### Extended git commands

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub clone [-p] [OWNER/]REPO [DIR]` | **Yes** | `git clone owner/repo`, `git clone repo` (your own), `repo.wiki`, `HOST/OWNER/REPO`; every git clone flag is kept in place | No API lookup. No `upstream` remote for forks (use `gh repo clone` for that). |
| `hub remote add [-p] [NAME] USER[/REPO]`, `hub remote set-url …` | **Yes** | A bare `USER` means `USER/<current repo>`; `remote add origin` alone means your own fork, as in hub 2.x | No existence check. |
| `hub fetch USER[,USER2…]` | **Yes** | Adds missing remotes, then `git fetch --multiple`; `fetch --multiple USER USER2` works too, with `--multiple` and other options anywhere before the names | No existence check: git reports a missing fork. Remotes are added even with git's `--dry-run`. |
| `hub push REMOTE1,REMOTE2 [ARGS…]` | **Yes** | `git push REMOTE ARGS…` once per remote, arguments exactly as given; the current branch is pushed only when nothing follows the remotes; stops at the first failure | |
| `hub checkout PR-URL [BRANCH]` | **Yes** | `gh pr checkout URL [-b BRANCH]` | `-f` is refused: gh's `--force` resets the local branch. |
| `hub merge PR-URL` | **Yes** | Fetches `refs/pull/N/head` and merges **locally** with the merge-button message | Never `gh pr merge`, which merges on GitHub. |
| `hub am URL`, `hub apply URL` | **Yes** | PR URLs through `gh pr diff --patch`, commit URLs through the API's patch/diff; local files and options untouched; patches with escape bytes work on gh 2.103+ | Gist URLs are not supported. |
| `hub cherry-pick COMMIT-URL`, `USER@SHA` | **Yes** | Fetches the commit (or `refs/pull/N/head`) and cherry-picks it | |
| `hub sync [REMOTE]` | **Yes** | Pure git: fetch `--prune`, fast-forward branches that are behind, delete merged branches whose upstream is gone (after confirming with `git ls-remote` that the remote branch is really gone), warn about the rest; exits non-zero if a branch could not be updated, deleted or checked | `--color` dropped. |
| `hub init -g` | No | `git init && gh repo create --source=. --private` | |
| `hub submodule add OWNER/REPO DIR` | No | `git submodule add "$(gh repo view OWNER/REPO --json url -q .url).git" DIR` | |

### New commands

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub pull-request` | **Yes**, hub flags | `gh pr create`; `-m` (repeatable) and `-F FILE` split title and body, `-e`, `-b BASE` or `-b OWNER[/REPO]:BRANCH` (becomes `--repo` plus `--base`), `-h HEAD`, `-p` pushes first to the remote the head names, `-f`, `-d`, `-r`, `-a`, `-M`, `-l`, `--no-maintainer-edits`, `-o` opens, `-c` copies, `-i ISSUE` or an issue URL converts the issue (in that issue's repository); gh's `-B`/`-H` are accepted, other flags go to gh; the repository and host hub resolved are always passed to gh; before any `-p` push, hub checks that the push remote's push URLs name one GitHub repository on the base's host that is the base, a fork of it or a sibling fork (one or two API lookups), and that the head owner is not an organization | gh's `-b`, `-F`, `-m` and `-p` must be spelled `--body`, `--body-file`, `--milestone`, `--project`. `--dry-run` never pushes, not even through gh (hub pins the head). Milestones by number and auto-created labels are not supported. |
| `hub pr list \| checkout \| show \| merge` | **Yes**, gh flags | `show` → `gh pr view` (`-u` prints the URL), `checkout N BRANCH` → `-b BRANCH`, everything else → `gh pr …` | `merge` merges on GitHub, as gh does. |
| `hub issue …` | **Yes**, gh flags | bare → `list`; `show` → `view`; `update` → `edit`, with `-s closed\|open` → `close`/`reopen` for every number given; `labels` → `gh label list`; `create -m`/`-F` and `update -m`/`-F` split title and body (gh's own are `--milestone`, `--body-file`) | `--include-pulls`, sorting flags and `-f` formats are gone; use gh's `--search`, `--json`, `--jq`. |
| `hub release …` | **Yes**, gh flags | bare → `list`; `show` → `view`; `create -a FILE[#label]` become asset arguments, `-m`/`-F` split title and notes, `-t REF` → `--target`; `edit -a` → `gh release upload` (add `--clobber` yourself to replace an asset); every `-a` file is checked before anything runs; `download -i GLOB` → `-p GLOB` | `-e`, `-o`, `-c` and `-f` formats are gone. |
| `hub browse [-u] [-c] [[OWNER/]REPO] [SUBPAGE]` | **Yes** | URL built locally, no API call; on a non-default branch the root, `tree` and `commits` pages open at that branch (on your fork when the branch pushes there); `OWNER/REPO.wiki` projects open the wiki pages | |
| `hub compare [-u] [-c] [-b BASE] [OWNER] [RANGE]` | **Yes** | `A..B` becomes `A...B`; refuses an unpushed branch and a base equal to the head; wikis get `wiki/_compare/RANGE` | |
| `hub create [-p] [-d DESC] [-h URL] [[ORG/]NAME]` | **Yes**, hub flags | `gh repo create --source=.`; **private by default**, `--public` to publish, `--internal` for organizations, `--remote-name` (or `-r`/`--remote`), `-o` opens, `-c` copies the URL; options gh rejects together with `--source` are refused before anything is created | hub 2.x created public repositories by default. |
| `hub fork [--no-remote] [--remote-name NAME] [--org ORG]` | **Yes** | Forks the repository hub resolved through the API (`POST repos/OWNER/REPO/forks`), which returns the fork's real name even when it already existed, then `git remote add <your login> <fork URL>` and a fetch that retries while GitHub is still creating the fork; an existing remote is reused if it points at the fork, refused otherwise | The remote is named after you, as in hub 2.x; plain `gh repo fork` would rename `origin` to `upstream`. |
| `hub delete [-y] [OWNER/]NAME` | **Yes** | `gh repo delete [--yes]` | Needs the `delete_repo` scope: `gh auth refresh -s delete_repo`. |
| `hub ci-status [-v] [COMMIT]` | **Yes** | Combines commit statuses and check runs through `gh api`; prints one word; exit 0 success, 1 failure, 2 pending, 3 no status; a 403, 404 or 422 from the check-runs API falls back to the statuses, as in hub 2.x | `-f FORMAT` and `--color` are gone. `gh pr checks` is the richer view for a PR. |
| `hub api …` | **Yes**, gh flags | `gh api`; `-t/--flat` is an error (gh's `-t` means `--template`), `--cache N` gains the missing unit | Use `--jq` or `--template` for shell-friendly output. |
| `hub gist create \| show` | **Yes**, gh flags | `--public` → `-p`, `-o` → `-w`; `show ID [FILE]` → `gh gist view --raw` | `-c` is gone. |
| `hub alias [-s] [SHELL]` | **Yes** | bash, zsh, sh, ksh, dash, fish, csh, tcsh | |
| `hub help [COMMAND]`, `hub version`, `hub --noop` | **Yes** | Each module's header is its manual | |
| `-f FORMAT` placeholders (`%I`, `%t`, …) | No | gh's `--json FIELDS --jq EXPR` or `--template` | |
| `hub.protocol`, `hub.host`, `GITHUB_HOST` | **Yes** | Also gh's `git_protocol`, `GH_HOST`, and `GH_REPO` to target another repository | |
| hub's own login and `GITHUB_TOKEN` handling | No, by design | `gh auth login`, `GH_TOKEN` | |

## Not implemented, on purpose

- `init -g` and `submodule add OWNER/REPO`: use `git init && gh repo create --source=.`
  and `git submodule add "$(gh repo view OWNER/REPO --json url -q .url).git" DIR`.
- Gist URLs as patch sources for `am`/`apply`.
- `-f FORMAT` placeholders: use gh's `--json`, `--jq` and `--template`.
- The `-c` clipboard flag outside `browse`, `compare`, `create` and `pull-request`.
- Enterprise hosts on non-standard HTTPS ports: hosts are recognized with the
  port ignored, but web and API URLs use the standard port.
- hub 2.x's own login and `GITHUB_TOKEN` handling: gh's authentication is used.
