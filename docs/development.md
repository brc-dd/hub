# Development

```sh
make check        # shellcheck + the bats suite
make test         # bats --recursive test
make lint         # shellcheck
make fmt          # shfmt -w (settings live in .editorconfig)
```

Layout:

```
bin/hub              dispatcher: option parsing, fast path, module loading
lib/hub/core.sh      shared helpers (hub::git, hub::gh, repo and URL detection, …)
lib/hub/ext/*.sh     extended git commands (one file per command)
lib/hub/cmd/*.sh     new commands built on gh
completions/         zsh, bash and fish completion
test/                bats tests; test/stubs/gh replaces gh, --noop captures git
Formula/hub.rb       Homebrew formula (this repo is a tap)
script/              bump, release, update-formula
```

Adding a command is one file: `lib/hub/cmd/<name>.sh` (or `ext/`) defining
`hub_cmd_<name>` (or `hub_ext_<name>`), with a comment-block header that becomes
its `hub help <name>` manual, plus `test/cmd/<name>.bats`. Side effects go
through `hub::git`, `hub::gh`, `hub::exec_git` and `hub::exec_gh` so that
`--noop` keeps working; read-only lookups use `hub::git_query` and
`hub::gh_query`.

Releases: `script/release X.Y.Z` runs the checks, bumps `VERSION` and
`CHANGELOG.md`, tags, pushes exactly `main` and the new tag (never other local
tags), publishes the GitHub release and updates the Homebrew formula's URL and
checksum. The release targets the repository `origin` names: an SSH alias in its
URL is resolved with `ssh -G`, and `gh repo view` must see the repository before
anything is pushed. A stable release must come from a checkout of the repository
`Formula/hub.rb` names (its `REPO`), since the formula downloads the tag from
there; a pre-release from another repository, a fork, is allowed and leaves the
formula alone. An existing draft release for the tag is published, not taken for
a published one. After a failure, fix the cause and run `script/release` without
a version: it resumes the release named by `VERSION`, with HEAD at its tag or at
the formula commit that follows it, and skips the steps that are done.
`script/release --dry-run` checks the local state and prints the commands
instead of running them; `make check` is printed, not run. See `script/bump`,
`script/release` and `script/update-formula` for the individual steps.

## Testing approach

Tests are [bats](https://github.com/bats-core/bats-core) files under `test/`.
Every test runs in a throwaway directory with an isolated git configuration;
`gh` is replaced by `test/stubs/gh`, which records each call and replays
responses registered with `stub_gh`; real git is used for fixtures, and hub's
own side effects are observed with `--noop`, which prints the git and gh
commands instead of running them. See `test/test_helper.bash` for the helpers.

Releases are documented in `script/release --help`; the design and the
module contract are in [design.md](design.md).

The completions are tested by hand in the shells themselves: hub's commands
must appear after git's global options (`hub -C dir <TAB>`, `hub -c k=v <TAB>`,
`hub --config-env k=v <TAB>`), plain `git <TAB>` must keep the user's own git
aliases, `_git_CMD`/`_git-CMD` functions and zsh `user-commands` style, and
`alias git=hub` must add hub's commands and arguments on top of git's.

## Workflows

The GitHub Actions workflows keep readable version tags in the YAML; the
commits they resolve to are recorded in `.github/workflows/actions.lock` by the
[`gh actions-lock`](https://github.com/github/gh-actions-lock) extension, which
GitHub Actions enforces at run time. After changing a `uses:` line run
`gh actions-lock`; CI runs `gh actions-lock --verify`. The release workflow
runs on every `v*` tag: it publishes the GitHub release (or publishes the draft
that exists for the tag) and, for stable versions, points the formula at the
highest published stable version by SemVer precedence, whatever the creation
order of the releases. To lint the workflows:

```sh
actionlint .github/workflows/*.yml                       # rhysd/actionlint or the kjanat fork
uvx --from 'zizmor==1.32.0rc1' zizmor .github/workflows  # zizmor 1.32+ understands the lockfile
```
