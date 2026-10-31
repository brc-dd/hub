# hub 2.x compatibility

How this hub compares with the last Go release, [hub 2.14.2](https://github.com/mislav/hub).
The intent is to cover the commands people typed, not to reproduce hub 2.x's
output formats or every flag; shared command names follow gh. This hub needs
bash 5.3, git 2.41 and gh 2.40 or newer; the README says why.

Two rules decide what the flags mean:

1. **Commands that only hub has** (`pull-request`, `browse`, `compare`,
   `create`, `fork`, `delete`, `ci-status`, `sync`, `alias`, and the extended
   git commands) use **hub's flags**, translated to gh or git.
2. **Commands gh also has** (`pr`, `issue`, `release`, `api`, `gist`) use
   **gh's flags and output**. hub maps only the old subcommand names gh lacks
   (`show` to `view`, no subcommand to `list`) and hands everything else to gh
   unchanged; old hub's option letters are not translated.

### Extended git commands

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub clone [-p] [OWNER/]REPO [DIR]` | **Yes** | `git clone owner/repo`, `git clone repo` (your own), `repo.wiki`, dotted names such as `.github`; every git clone option stays in place; a name that is an existing path, a `NAME.git` repository or a `NAME.bundle` next to you stays git's | No API lookup. No `upstream` remote for forks (use `gh repo clone` for that). Other hosts through `GH_HOST` or `hub.host`, not `HOST/OWNER/REPO`. git's options are read as the installed git reads them, abbreviations (`--dep 1`) included. |
| `hub remote add [-p] [NAME] USER[/REPO]`, `hub remote set-url …` | **Yes** | A bare `USER` means `USER/<current repo>`; `remote add origin` alone means your own fork, as in hub 2.x; one operand always expands, with two an existing path keeps git's meaning; `set-url --delete`, when it is in effect, goes to git unchanged | No existence check. |
| `hub fetch USER[,USER2…]` | **Yes** | Adds the missing remotes, then `git fetch --multiple USER USER2`; `--multiple USER USER2` works too, and options may come before the names; an existing remote or group is fetched as it is, never split, an existing path is git's, and so is the whole command line when it has an option git does not know (nothing is added first); an empty or malformed member is an error before any remote is added | No existence check: git reports a missing fork. |
| `hub push REMOTE1,REMOTE2 [ARGS…]` | **Yes** | `git push REMOTE ARGS…` once per remote, arguments exactly as given (options may precede the list); the current branch (as `refs/heads/BRANCH`, so a tag of its name cannot make git refuse) is pushed only when the list is the whole command line; every member is checked before the first push; an existing remote, a path or a URL with a comma is one destination; stops at the first failure | |
| `hub checkout PR-URL [BRANCH]` | **Yes** | `gh pr checkout URL [-b BRANCH]`, with `GH_HOST` set to the URL's host so that gh fetches from a remote of that host; the URL may stand anywhere before `--`; `-d`/`--detach` and `--recurse-submodules` pass through as git reads them (the last of an option and its negation counts; `--recurse-submodules=VALUE` takes git's booleans, `=no` being `--no-recurse-submodules`) | `-f` is refused: gh's `--force` resets the local branch. An empty branch name is an error. A value git refuses (`--recurse-submodules=banana`, `--detach=1`) leaves the command line to git. |
| `hub merge PR-URL` | **Yes** | Fetches `refs/pull/N/head` into a private ref (with `--refmap=` and `--no-tags`, so the remote's own fetch refspecs write nothing on the side and no tag follows) and merges that commit **locally** with the merge-button message, `--no-ff` unless you choose otherwise; with `--squash` in effect (the last of `--squash`/`--no-squash` counts) hub adds no message; the URL is the only revision | Never `gh pr merge`, which merges on GitHub. |
| `hub am URL`, `hub apply URL` | **Yes** | Pull-request, commit and compare URLs, also in their `.patch`/`.diff` forms, downloaded through `gh api` (a patch for `am`, a diff for `apply`); local files and options untouched; patches with escape bytes work on gh 2.103+ | Gist URLs are not supported. |
| `hub cherry-pick COMMIT-URL`, `USER@SHA` | **Yes** | Fetches the commit (or `refs/pull/N/head`, into a private ref of the run; `--refmap=` keeps the remote's fetch refspecs from writing anything else) and cherry-picks it; several URL or `USER@SHA` operands are allowed; a `USER@SHA` that names a local revision is git's; the value of a revision option that reads the next argument (`--grep PATTERN`, `--author NAME`, `--since DATE`, `--max-count N`) is never an operand | |
| `hub sync [--color] [REMOTE]` | **Yes** | Fetches REMOTE (the main remote by default) with a fixed refspec, fast-forwards branches that are behind, deletes merged branches whose upstream is gone (only when REMOTE's default branch is known, from `refs/remotes/REMOTE/HEAD` or gh), warns about the rest; every update is conditional on the state sync saw, so a branch that moved meanwhile is left alone; symbolic refs and branches checked out in another work tree are skipped, and no other branch is ever moved through a symbolic ref; exits non-zero when something sync decided to do could not be done | `--color=always\|never\|auto` as in hub 2.x. |
| `hub init -g` | No | `git init && gh repo create --source=. --private` | |
| `hub submodule add OWNER/REPO DIR` | No | `git submodule add "$(gh repo view OWNER/REPO --json url -q .url).git" DIR` | |

### New commands

| hub 2.x | Status | This hub | Notes |
|---|---|---|---|
| `hub pull-request` | **Yes**, hub flags | `gh pr create` with hub's options only: `-m` (repeatable) and `-F FILE` split title and body, `-e` opens gh's editor, `--no-edit` takes the first commit of the head branch (HEAD's when the pull request is for the current branch, else its remote-tracking branch's here, where the remote's fetch refspecs put it), `-b BASE` or `-b OWNER[/REPO]:BASE`, `-h BRANCH`, `-h OWNER:BRANCH` or `-h OWNER/REPO:BRANCH` (a renamed fork; without it and without `-p`, the local branch of the head's name says which repository of OWNER's), `-p` pushes first (to where `git push` would send the branch, once every check has passed and gh is known to be installed; under `push.default matching` only a branch the destination already has, as `git ls-remote` shows), `-f` skips the pushed-branch check, `-d`, `-r`, `-a`, `-M`, `-l`, `--no-maintainer-edits`, `-o` opens and `-c` copies the URL looked up after gh is done, `-i ISSUE` or an issue URL converts the issue through the API; the head is named for gh from the push remote's push URL | gh's own options (`-R`, `--dry-run`, `--fill`, `-B`/`-H`) are not accepted: hub always passes the repository, base and head it resolved. A remote that fetches from one repository and pushes to another needs `-p` or `-f`. Without `-b`, the current branch's `branch.*.gh-merge-base` is the base whenever the pull request is for that branch (no `-h`, `-p`, or `-h` naming the repository and branch `git push` sends it to, however spelled); otherwise the base repository's default branch must be known (`refs/remotes/REMOTE/HEAD`, else gh's answer): hub never assumes `main` for a pull request. Milestones by number and auto-created labels are not supported. |
| `hub pr list \| checkout \| show \| merge` | **Yes**, gh flags | `show` → `gh pr view`; no subcommand → `gh pr list`; everything else → `gh pr …` unchanged (`checkout N -b BRANCH` names the local branch) | `merge` merges on GitHub, as gh does. Which repository a number or URL selects is gh's decision. |
| `hub issue …` | **Yes**, gh flags | bare → `list`; `show` → `view`; everything else → `gh issue …` unchanged | `update`, `labels`, `-m`/`-F` as title and body, `--include-pulls`, sorting flags and `-f` formats are gone: use `gh issue edit`, `gh label list`, `--body-file`, `--search`, `--json`, `--jq`. |
| `hub release …` | **Yes**, gh flags | bare → `list`; `show` → `view`; everything else → `gh release …` unchanged | `-a FILE` (name files as arguments of `create` or `upload`), `-m`/`-F`, `-t REF` (`--target`), `download -i` (`-p`), `-e`, `-o`, `-c` and `-f` formats are gone. |
| `hub browse [-u] [-c] [[OWNER/]REPO] [SUBPAGE]` | **Yes** | URL built locally; on a non-default branch the root, `tree` and `commits` pages open at that branch, in the repository the branch pushes to; `OWNER/REPO.wiki` projects open the wiki pages | The default branch is read from the remote's HEAD, else asked of gh once. |
| `hub compare [-u] [-c] [-b BASE] [OWNER] [RANGE]` | **Yes** | `A..B` becomes `A...B`; the head is the pushed branch, written `FORKOWNER:BRANCH` (or `FORKOWNER:FORKREPO:BRANCH` for a renamed fork) when it pushes to a fork; refuses an unpushed branch (or one whose remote fetches from another repository than it pushes to, or whose fetch refspecs do not map the branch to a remote-tracking ref: name the head yourself), a base equal to the head, and the compare repository's own default branch without a range; wikis get `wiki/_compare/RANGE` | |
| `hub create [-p] [-d DESC] [-h URL] [[ORG/]NAME]` | **Yes**, hub flags | `gh repo create HOST/OWNER/NAME --source=TOP --remote=REMOTE`, run where you are; **private by default**, `--public` to publish, `--internal` for organizations, `--remote-name`, `--push` (from a bare repository hub pushes the branch HEAD names itself, where gh's `--push` would mirror every ref), `-o` opens, `-c` copies the URL; NAME may be `OWNER/NAME`, `HOST/OWNER/NAME` or a repository URL; the repository layout, the names and a free remote are checked before gh runs | hub 2.x created public repositories by default. gh cannot create from a linked work tree or through `--git-dir`/`GIT_DIR`. |
| `hub fork [--no-remote] [--remote-name NAME] [--org ORG]` | **Yes** | `gh repo fork --remote --remote-name NAME` with `GH_REPO` set to the project hub resolved, so gh forks exactly it and adds the remote (named after you, or the organization) with the URL hub's protocol gives; `--fork-name` and `--default-branch-only` pass through; nothing is fetched (`git fetch NAME` once the fork exists); the remote name is checked before gh runs | The remote is named after you, as in hub 2.x; plain `gh repo fork` would rename `origin` to `upstream`. An existing remote of that name is an error. |
| `hub delete [-y] [OWNER/]NAME` | **Yes** | `gh repo delete [--yes]` | Needs the `delete_repo` scope: `gh auth refresh -s delete_repo`. |
| `hub ci-status [-v] [COMMIT]` | **Yes** | Combines commit statuses and check runs through `gh api`; prints one word; exit 0 success, 1 failure, 2 pending, 3 no status; a 403, 404 or 422 from the check-runs API falls back to the statuses only when no page of check runs was read, a failure already seen is final, and an answer without a `check_runs` array is an error, not an empty page | `-f FORMAT` and `--color` are gone. `gh pr checks` is the richer view for a PR. |
| `hub api …` | **Yes**, gh flags | `gh api …` unchanged | `-t`/`--flat` and `--cache N` are not translated: gh reads `-t` as `--template` and `--cache` needs a unit (`--cache 1h`). The host is gh's: `--hostname` or `GH_HOST`. |
| `hub gist create \| show` | **Yes**, gh flags | `show` → `gh gist view`; bare → `list`; everything else → `gh gist …` unchanged | `--public` is gh's own; `-o` (`-w`), `-c` and `show ID FILE` (`view ID -f FILE`) are gone. |
| `hub alias [-s] [SHELL]` | **Yes** | bash, zsh, sh, ksh, dash, fish, csh, tcsh | |
| `hub help [COMMAND]`, `hub version`, `hub --noop` | **Yes** | Each module's header is its manual | |
| `-f FORMAT` placeholders (`%I`, `%t`, …) | No | gh's `--json FIELDS --jq EXPR` or `--template` | |
| `hub.protocol`, `hub.host`, `GITHUB_HOST` | **Yes** | Also gh's `git_protocol`, `GH_HOST`, and `GH_REPO` to target another repository | An SSH remote whose host is an alias counts as a GitHub remote when `ssh -G` resolves the alias to a GitHub host (hub 2.x read `~/.ssh/config` itself). |
| hub's own login and `GITHUB_TOKEN` handling | No, by design | `gh auth login`, `GH_TOKEN` | |

## Not implemented, on purpose

- `init -g` and `submodule add OWNER/REPO`: use `git init && gh repo create --source=.`
  and `git submodule add "$(gh repo view OWNER/REPO --json url -q .url).git" DIR`.
- Gist URLs as patch sources for `am`/`apply`.
- `-f FORMAT` placeholders: use gh's `--json`, `--jq` and `--template`.
- The `-c` clipboard flag outside `browse`, `compare`, `create` and `pull-request`.
- Enterprise hosts on non-standard HTTPS ports: hosts are recognized with the
  port ignored, but web and API URLs use the standard port.
- SSH certificate URLs from shorthands: `owner/repo` with SSH always becomes
  `git@HOST:owner/repo.git`, as in hub 2.x. An organization that requires SSH
  certificates publishes a repository-specific URL carrying the organization
  ID (Code → SSH on the repository page); give that URL, or an SSH alias that
  resolves to it, instead of the shorthand. hub passes full URLs through
  unchanged and recognizes the remote they create.
- hub 2.x's own login and `GITHUB_TOKEN` handling: gh's authentication is used.
