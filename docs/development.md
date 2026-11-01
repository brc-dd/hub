# Development

Development uses bats 1.14.0, ShellCheck 0.11.0 and shfmt 3.14.1, the
versions [CI](../.github/workflows/ci.yml) installs. CI runs Homebrew's bash
on macOS and the runner's own bash on Linux. The module contract is in
[design.md](design.md).

```sh
make check        # lint, fmt-check, test and selftest, in that order
make test         # bats test
make lint         # shellcheck (--severity=warning on *.bats), 100 columns, actionlint
make fmt          # shfmt -w (its settings live in .editorconfig)
make fmt-check    # shfmt -d
make selftest     # script/update-formula --self-test
make site         # script/site site: the manuals as HTML in site/, which git ignores
make install      # symlinks under PREFIX (/usr/local); make uninstall removes them
```

`make install` makes the links in order: the command, then the bash, zsh and
fish completions. A refusal at a later destination leaves the earlier links
in place, and `make uninstall` removes them.

## Layout

```
bin/hub                 dispatcher
lib/hub/core.sh         shared helpers (hub::*)
lib/hub/cmd/NAME.sh     one module per command, defining hub_cmd_NAME
completions/            hub.bash, hub.zsh, hub.fish
test/NAME.bats          one file per module, plus dispatch, core, harness, completions, script-*
test/test_helper.bash   setup, fixtures and assertions
test/stubs/             gh, ssh, git-remote-https, browser (open, xdg-open), pbcopy (xclip, wl-copy)
script/                 bump, release, site, stable-tag, update-formula
Formula/hub.rb          Homebrew formula (this repository is its own tap)
.github/                ci.yml, release.yml, pages.yml, actions.lock, dependabot.yml
```

## Tests

Tests are [bats](https://github.com/bats-core/bats-core) files; `make test`
runs them all, and `bats -f PATTERN test/push.bats` runs some of one file.
How the tests isolate themselves, stand in for GitHub and what they assert is
in [design.md](design.md#testing).

`test/test_helper.bash` gives each helper a one-line contract:

- Repositories: `make_repo`, `commit_on`, `tip`, `set_remote_head`,
  `pushed_feature`; served ones: `serve_github`, `server_dir`, `server_ref`,
  `server_branches`, `clone_served`.
- gh: `stub_gh 'ARGS GLOB' 'STDOUT' [STATUS]`, `stub_gh_file`, `stub_patch`,
  `gh_calls`, `assert_gh_called`, `assert_gh_not_called`, `recording_gh`,
  `failing_gh`, `no_gh_path`. Records: `opened`, `copied`, `assert_tmp_empty`.
- Assertions: `assert_success`, `assert_failure`, `assert_status`,
  `assert_git_help`, `assert_output_equals`, `assert_output_contains`,
  `assert_output_lacks`, `assert_line_equals`, `assert_equals`.

`test/harness.bats` tests the stubs.

## Adding a command

The steps are in [design.md](design.md#adding-a-command).

## Releases

`script/release [-n] VERSION` refuses unless `main` is checked out and clean,
origin's URL and every push URL name the formula's `REPO` on github.com,
VERSION is `X.Y.Z` or `X.Y.Z-PRE`, origin has no tag `vVERSION` (it asks with
`git ls-remote`), and, after fetching origin's `main` explicitly
(`git fetch origin +refs/heads/main:refs/remotes/origin/main`, whatever
`remote.origin.fetch` says), `main` is not behind `origin/main`.
`gh repo view` must see `REPO`, and `script/bump --dry-run` must pass: a new
SemVer tag and notes under `## [Unreleased]`. A stable VERSION must not be
lower than the formula's. Then it runs `make check`, `script/bump VERSION`
and one `git push --atomic --no-follow-tags` of `main` and `vVERSION` (no
other tag, whatever `push.followTags` says), or prints them under `-n`. When
the push fails, it prints the push to retry and the commands that undo the
bump: `git tag -d vVERSION && git reset --hard START`. The release scripts
work in their own checkout whatever `CDPATH` holds.

The tag starts the Release workflow (`gh run watch -R brc-dd/hub`), which
skips forks. Its `publish` job creates the release with generated notes (a
pre-release for a tag with a `-`), publishes a draft, or leaves a published
release alone. For a stable tag, the `formula` job points `Formula/hub.rb` at
the highest published stable tag, pushing `Formula: hub TAG` when it changes.

## Manuals website

`script/site DIR` renders the module headers as static HTML with no script or
external resource: `DIR/index.html`, the manual of `bin/hub` with the list of
commands, and `DIR/NAME.html` for every module. A page holds the Summary
line, the Usage lines up to the first blank line, then the blocks: unindented
lines are a paragraph that the browser reflows, lines indented by two or more
spaces are preformatted, and an unindented line ending in a colon before
indented lines is a heading. `test/script-site.bats` checks that the text of
a command page is what `hub help NAME` prints and that the index holds
`bin/hub`'s header, and that two runs on one commit write the same bytes.

The Pages workflow (`.github/workflows/pages.yml`) builds the site and
deploys it to https://brc-dd.github.io/hub/ on every push to `main` that
changes `bin/hub`, a module, `script/site`, `VERSION`, `Formula/hub.rb` or the
workflow, and on `gh workflow run pages.yml`. It skips forks, and a new run
waits for a deployment in progress to finish. A repository admin enables Pages
once with the GitHub Actions source, under Settings > Pages > Build and
deployment > Source, or with the line below; until then the deploy job fails.

```sh
gh api -X POST repos/brc-dd/hub/pages -f build_type=workflow
```

## Workflows

`.github/workflows/actions.lock`, written by
[`gh actions-lock`](https://github.com/github/gh-actions-lock), records the
commits of the `uses:` tags in every workflow. After changing a `uses:` line,
run `gh actions-lock`; CI runs `gh actions-lock --verify`. Dependabot updates
the actions weekly with a 7-day cooldown. zizmor before 1.32 does not read the
lockfile and reports unpinned actions:

```sh
actionlint .github/workflows/*.yml
uvx --from 'zizmor==1.32.0rc1' zizmor .github
```

## Completions

- bash: source git's `git-completion.bash` first unless bash-completion or
  Homebrew's git loads it.
- zsh: install as `_hub` on `$fpath`, or source after `compinit`. It also
  registers for git, which `setopt complete_aliases` completes as git.
- fish: install as `hub.fish` in a `vendor_completions.d` directory.

`test/completions.bats` runs the files in `bash --noprofile --norc` and
`zsh -f` over stubbed git completion functions, and syntax-checks fish; the
zsh and fish tests skip where that shell is not installed (CI installs zsh
on Linux). Each file's commands must equal the modules in `lib/hub/cmd`,
with their Summary lines, and its options each module's `# Options:` block.
ShellCheck and shfmt read bash only, so `make lint` skips the zsh and fish
files.
