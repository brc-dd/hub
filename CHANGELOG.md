# Changelog

All notable changes to hub are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and hub uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- `create` and `delete` take repository URLs, and `delete` takes `HOST/OWNER/NAME`.
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

[Unreleased]: https://github.com/brc-dd/hub/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/brc-dd/hub/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/brc-dd/hub/releases/tag/v0.1.0
