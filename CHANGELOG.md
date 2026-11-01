# Changelog

All notable changes to hub are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and hub uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A manuals website at https://brc-dd.github.io/hub/: `script/site DIR`
  (`make site`) renders the manuals that `hub help` prints as static HTML,
  and the Pages workflow publishes them on every push to `main` that changes
  a manual.

## [0.3.0] - 2026-11-01

### Changed

- hub needs git 2.30 or newer, for `cherry-pick`'s
  `git fetch --no-write-fetch-head` and `git rev-parse --end-of-options`, and
  gh 2.55 or newer, for `gh pr create --editor`.

### Fixed

- `am`, `apply` and `cherry-pick` convert only operands: a GitHub URL given
  as an option's value (`--include URL`, `--directory URL`) goes to git as
  given.
- `cherry-pick` no longer changes `FETCH_HEAD`, so a `FETCH_HEAD` operand
  next to a commit URL keeps its meaning.
- GitHub Enterprise Managed User logins (`NAME_SHORTCODE`) are read as owners
  in shorthands, URLs and `GH_REPO`.
- A word containing whitespace or a newline is never read as a GitHub URL.
- `sync` leaves a branch checked out in another work tree alone with a
  warning and exits 1, also on git older than 2.35, which fast-forwarded it
  under that work tree.
- `sync` fast-forwards a chain of branches that track local branches in one
  run, each after the branch it tracks, the current branch included.
- `sync` says a branch is ahead of its local upstream instead of warning
  about unpushed commits.
- `fork` asks GitHub's fork API through `gh api`, so it adds the remote for
  an existing fork, under that fork's own name, and works on every gh hub
  supports.
- `push REMOTE1,REMOTE2` pushes the current branch when a later `--no-FLAG`
  cancels `--all`, `--branches`, `--mirror`, `--tags` or `--delete` (for
  example `--all --no-all`).
- `push REMOTE1,REMOTE2` pushes the current branch when `--no-all` cancels
  `--branches` or `--no-branches` cancels `--all`, git's alias of it, and
  when `--no-delete` follows a repeated `-d`.
- `push REMOTE1,REMOTE2` reads `remote.NAME.push` and `remote.NAME.mirror`
  from the repository's configuration even with `GIT_CONFIG` set, as git push
  does.
- `push` hands a word with a comma that git rewrites through
  `url.BASE.insteadOf` to git as one destination instead of splitting it.
- `sync` fast-forwards the default branch it switched to after deleting the
  current branch, when the default branch tracks a local branch; git refused
  to fetch into it.
- `sync` fast-forwards branches that are not checked out in a repository
  whose git directory is separate from its work tree (`--git-dir` and
  `--work-tree`, or `GIT_DIR` and `GIT_WORK_TREE`), and no longer reads a
  repository that happens to sit at the top of the work tree.
- `sync` shows a `GH_REPO` that no remote points to quoted, so a newline
  cannot split the message.
- `checkout --pathspec-from-file FILE` is git's even when FILE looks like a
  pull request URL; so is a line with `--pathspec-file-nul`.
- `checkout` refuses `--detach` together with `-b BRANCH` or a BRANCH
  operand; gh dropped the branch and reported success.
- `am` and `apply` leave a two-dot compare URL (`compare/A..B`) to git as
  given, since GitHub's API compares only `BASE...HEAD`.
- `pull-request -o` and `-c` find the new pull request by its head, so a
  branch named like a number (`123`) no longer opens another pull request.
- `pull-request` refuses before pushing when gh's configuration has prompt
  disabled and gh would have to prompt.
- `create` works from a linked work tree and from a work tree with a
  separate git directory: gh creates the repository and git adds the remote.
- `create` accepts `OWNER/NAME`, `HOST/OWNER/NAME` and URL forms whose name
  starts with a hyphen.
- `create`'s help says that an internal repository is readable by every
  member of the enterprise.
- `fetch` refuses a list that names one missing user in two cases
  (`alice,Alice`) instead of adding two remotes.
- `fetch` hands a first operand that git rewrites through
  `url.BASE.insteadOf`, and a URL or host:path word containing a comma, to
  git untouched instead of adding remotes for it.
- `fetch` counts a list member as a remote group only by git's lowercase
  key, and refuses a group named in another case (`Friends`) before asking
  gh or adding a remote.
- `remote add NAME WORD` and `remote set-url NAME WORD` keep a word git
  rewrites through `url.BASE.insteadOf` instead of replacing it with a
  GitHub URL, also when the word names a remote.
- Refusals of `ci-status`, `compare`, `alias`, `fork` and `pull-request`
  show the user's word quoted, so an empty word or a newline is visible.
- hub refuses to run when the `git` on `PATH` is hub itself through a
  trailing empty `PATH` entry.
- hub's commands started from a bare repository or a `.git` directory no
  longer pass `GIT_IMPLICIT_WORK_TREE=0` to git, so
  `hub clone --recurse-submodules` works there.
- zsh completion offers the options of hub's own commands when git's own
  `git-completion.zsh` is the `_git` completer, as Homebrew git and Apple's
  Command Line Tools install it.
- `browse`, `compare` and the `-o` of `pull-request` and `create` open URLs
  in the browser named by gh's `browser` setting when `GH_BROWSER` is unset,
  before `BROWSER`.
- `merge` reads a zero-padded pull request number in a URL (`pull/012`) as
  gh does, as pull request 12, instead of fetching `refs/pull/012/head`.
- `sync` fast-forwards branches that are not checked out also when
  `protocol.file.allow` is `never` or `GIT_ALLOW_PROTOCOL` leaves out `file`.
- `pull-request`, `compare` and `browse` no longer follow a pushRemote or
  pushDefault that holds a URL or another word that names no remote;
  `pull-request` says it cannot tell where the branch pushes.
- `fork` and `create` refuse a remote name that differs from an existing
  remote's only in case (`remote already exists: NAME`).
- `pull-request -o` and `-c` no longer claim a pull request was created when
  `gh pr create` exits without one (gh's "Continue in browser"); they say
  that no open pull request from the head was found.
- `pull-request -F FILE` shows the file name quoted in its refusal, like
  other words the user typed.

## [0.2.0] - 2026-11-01

### Added

- `fetch` checks with gh that a user's copy of the project exists before it
  adds the remote, and takes git fetch options before the user names.
- `push` takes git push options before the comma-separated list of remotes,
  and checks that every member is a remote before the first push.
- `cherry-pick` takes several commit URLs in one command line; `am` and
  `apply` also take comparison URLs (`.../compare/BASE...HEAD`).
- `remote add origin` alone adds your own copy of the repository
  (`LOGIN/REPO`).
- `pull-request` refuses a branch that is not pushed, or has unpushed
  commits, unless `-p` pushes it or `-f` skips the check.
- `pull-request -b OWNER:BASE` (or `OWNER/REPO:BASE`) opens the pull request
  in another copy of the project.
- `create` and `delete` take repository URLs, and `delete` takes
  `HOST/OWNER/NAME`.
- `create -c` copies the new repository's URL, and `create` checks the name,
  the remote and, with `--push`, the branch before gh runs.
- `fork` takes `--fork-name`, `--default-branch-only` and an `ORG` operand as
  its own options, and reuses a fork that already exists.
- `browse` opens `commits/BRANCH` for the current branch, and takes
  repository URLs.
- `sync` also fetches every remote a local branch tracks, fast-forwards the
  default branch from the project's remote whatever it tracks, and exits 1
  when an update or a deletion failed.
- `version` prints gh's version too, and takes `--build-options`.
- Every host gh is logged in to counts as a GitHub host.
- hub refuses to run when the `git` it finds on `PATH` is hub itself.

### Changed

This release is a rewrite from scratch. hub asks git instead of modeling
it: hub's commands re-enter through git, which applies its own global
options, and when hub cannot tell what a command line means, git gets it
untouched. Every GitHub request goes through gh, with gh's login, hosts and
`git_protocol`. hub pushes only when asked (`pull-request -p`,
`create --push`), and names the remote in every push it runs. Git commands
that hub does not extend run on any bash; hub's commands need bash 5. Every
command is one module in one directory, `lib/hub/cmd/`, and the module's
header is its manual. Behavior differs from 0.1.0 in the ways listed here;
[docs/compatibility.md](docs/compatibility.md) compares hub with hub 2.x.

### Removed

[docs/compatibility.md](docs/compatibility.md) names what to use instead of
each item that hub 2.x also had.

- `git config hub.protocol` is not read.
- `git config hub.host` is not read.
- `HUB_VERBOSE` is gone; `hub --noop COMMAND` prints the git and gh commands
  instead of running them.
- `--noop` no longer prints git's global options for hub's commands; it
  prints the commands as hub runs them, after git has applied those options.
  A plain git command is printed as given.
- `clone HOST/OWNER/REPO` is plain git clone.
- `fetch` with `--multiple`, `--no-multiple` or `--all` is plain git fetch;
  a comma-separated list (`hub fetch alice,bob`) adds `--multiple` itself.
- `cherry-pick USER@SHA` is not supported.
- `pull-request -i ISSUE` is not supported.
- `pull-request`, `create` and `fork` no longer pass other options to gh
  (`--fill`, `-R`, `--dry-run`, `--license`, ...); run `gh pr create`,
  `gh repo create` or `gh repo fork` for them.
- `fork` no longer fetches the new remote; run `git fetch NAME` once GitHub
  has made the fork.
- `sync` no longer holds a branch without an upstream against the remote's
  branch of the same name; set an upstream with `git branch -u`.
- `ci-status` no longer ranks the states itself (`neutral` as success); it
  prints GitHub's combined verdict.
- `issue update`, `issue labels` and `issue create -m`/`-F` are not
  translated; use `gh issue edit`, `close` or `reopen`, `gh label list`, and
  `--title` with `--body`.
- `release` no longer translates `-a`, `-m`, `-F`, `-t` and `download -i`;
  use asset arguments or `gh release upload`, `--title` with `--notes`,
  `--notes-file`, `--target` and `-p`.
- `pr show -u` and `pr checkout PR BRANCH` are not translated; use
  `gh pr view --json url --jq .url` and `gh pr checkout PR -b BRANCH`.
- `gist create -o` and `gist show ID FILE` are not translated; use `-w` and
  `gh gist view ID --raw -f FILE`.
- `api -t`/`--flat` and `api --cache N` without a unit are not translated;
  use `--jq` or `--template`, and `--cache Ns`.
- The completions no longer list `hub api`'s options; gh's own completion
  covers `gh api`.

## [0.1.0] - 2026-10-29

### Added

- The first release: a bash wrapper around git that adds the GitHub
  commands of the classic hub, with the GitHub work done by gh.

[Unreleased]: https://github.com/brc-dd/hub/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/brc-dd/hub/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/brc-dd/hub/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/brc-dd/hub/releases/tag/v0.1.0
