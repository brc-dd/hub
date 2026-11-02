---
title: Working on hub
description: Tests, lint, make targets, adding a command, releases, the workflows and the manuals website.
---

# Working on hub

This page shows contributors how to run the checks CI runs and test against
hub's stand-in for GitHub, so that they can add a command, make a release and
publish the manuals website. [How hub is built](design.md) explains the
design.

## Set up the tools

You need bash 5, git 2.30 and GitHub CLI (gh) 2.55 or newer
([Install hub](../getting-started/install.md)). You also need the versions that
[CI](../../.github/workflows/ci.yml) installs: bats 1.14.0, ShellCheck 0.11.0
and shfmt 3.14.1.

On macOS, `/bin/bash` is 3.2. Put Homebrew's bash first on `PATH`:

```sh
export PATH="$(brew --prefix)/bin:$PATH"
```

CI does the same on macOS and uses the runner's bash on Linux. actionlint is
optional. Without it, `make lint` prints a warning and skips the workflows.

## Run the checks

The [Makefile](../../Makefile) holds every task. Run `make check` before you
commit, as CI does on `ubuntu-latest` and `macos-latest`. The targets are:

```sh
make check        # lint, fmt-check, test and selftest, in that order
make test         # bats test
make lint         # shellcheck, the 100-column limit, actionlint
make fmt          # shfmt -w (its settings live in .editorconfig)
make fmt-check    # shfmt -d: print the diff, change nothing
make selftest     # script/update-formula --self-test
make site         # script/site site: the manuals as HTML in site/, which git ignores
make install      # symlinks under PREFIX (/usr/local); make uninstall removes them
```

`make lint` runs ShellCheck (`--severity=warning` on `.bats` files) and fails
lines over 100 columns, workflows included. The zsh and fish completions are
not linted. `make check` prints the ShellCheck, shfmt, bats and self-test
commands as it runs them, but not the column check or actionlint. Run without
a terminal, as on CI, it prints bats' TAP output. At a terminal, bats prints
check marks and a count of tests instead. On CI, the output of `make check`
starts and ends like this, with `...` marking a cut:

```text
shellcheck --external-sources --shell=bash bin/hub lib/hub/core.sh ...
shellcheck --external-sources --shell=bash --severity=warning test/alias.bats ...
shfmt -d bin/hub lib/hub/core.sh ...
bats test
1..923
ok 1 hub alias -s prints the alias for every shell
...
script/update-formula --self-test
The version order is right.
```

`make install` links `bin/hub` into `BINDIR` (`PREFIX/bin`) and prints each
`ln -s`. It also links each completion into `BASH_COMPLETION_DIR`,
`ZSH_COMPLETION_DIR` and `FISH_COMPLETION_DIR` when that directory exists. It
stops if a path starts with a literal `~`, or if a file that is not a hub link
is already at a destination. Links that it made before it stops stay in
place. `make uninstall` removes only links into this checkout. Install
under your home directory, or stage the links, like this:

```sh
make install PREFIX="$HOME/.local"
make install DESTDIR=/tmp/stage     # the links go under /tmp/stage/usr/local
make install PREFIX=~/.local
# => make: ~/.local starts with a literal ~; write PREFIX="$HOME/..."
```

## Find your way around

`bin/hub` dispatches every command to a module in `lib/hub/cmd/`, and the
modules share the helpers in `lib/hub/core.sh`. Each module has its own test
file, and the stubs that stand in for gh, ssh, the browser and the clipboard
live in `test/stubs/`. The repository is laid out like this:

```text
bin/hub                 the dispatcher
lib/hub/core.sh         shared helpers (hub::*)
lib/hub/cmd/NAME.sh     one module per command, defining hub_cmd_NAME
completions/            hub.bash, hub.zsh, hub.fish
test/NAME.bats          one file per module, plus dispatch, core, harness, completions, script-*
test/test_helper.bash   setup, fixtures and assertions
test/stubs/             gh, ssh, git-remote-https, browser (open, xdg-open), pbcopy (xclip, wl-copy)
script/                 bump, release, site, stable-tag, update-formula
Formula/hub.rb          the Homebrew formula (this repository is its own tap)
.github/                ci.yml, release.yml, pages.yml, actions.lock, dependabot.yml
```

## Run the tests

Run all the tests, one file, or the tests of a file whose names match:

```sh
make test                            # every test file
bats test/push.bats                  # one file
bats -f 'list alone' test/push.bats  # the tests in push.bats whose names match 'list alone'
```

The tests never use the network or touch your repositories, configuration or
GitHub account. Before each test, `hub_test_setup` in test/test_helper.bash
unsets every `GIT_*`, `GH_*`, `GITHUB_*` and `HUB_*` variable. It also unsets
`CDPATH`, `BROWSER`, `BASH_ENV` and `ENV`. Each test gets its own directory,
`HOME`, git and gh configuration, and `LC_ALL=C`. The git user is `hub tests`
and the default branch is `main`. The gh stub answers `mislav` for the login
and `https` for the protocol on github.com.
[How hub is built](design.md#testing) gives the principles behind this
isolation.

## Understand the fake GitHub

In the tests, GitHub is a set of bare repositories under
`$HUB_TEST_SRV/HOST/OWNER/REPO.git`, a directory that the test setup creates.
The repositories share one root commit, so a fork shares history with its
parent. Remotes keep their real URLs, such as
https://github.com/OWNER/REPO.git, so hub sees the same URLs as in real use.

git looks for remote helpers in `GIT_EXEC_PATH` before `PATH`. So the tests
link git's helpers into a directory of their own, with `git-remote-https` and
`git-remote-http` replaced by a stub. The https stub and the ssh stub both run
`git upload-pack` or `git receive-pack` on the served repository. They match
OWNER and REPO in any case, as GitHub does. hub runs `ssh -G` to resolve an
ssh host alias, so the ssh stub passes `-G` to the real ssh. The real ssh
then reads only the test `HOME`'s `~/.ssh/config`.

The gh stub logs every call. It answers with the latest entry that a test
added with `stub_gh` (see [Use the test helpers](#use-the-test-helpers)) whose
glob matches the arguments, joined with spaces. A call that no entry matches
prints `gh stub: unexpected call: gh ARGS` and exits 97. The browser stub
records the URL (`GH_BROWSER`, `open`, `xdg-open`), and the clipboard stub
its standard input (`pbcopy`, `wl-copy`, `xclip`).
`HUB_TEST_BROWSER_STATUS` and `HUB_TEST_CLIPBOARD_STATUS` set their status.
`test/harness.bats` tests the stubs.

## Use the test helpers

Each helper in [test_helper.bash](../../test/test_helper.bash) has a one-line
contract. SPEC is `[HOST/]OWNER/REPO`.

| Helper | What it does |
|---|---|
| `make_repo NAME [REMOTE=URL...]` | Creates a repository with one commit and these remotes, and `cd`s into it. |
| `pushed_feature` | Clones mislav/dotfiles, pushes a branch `feature` with `-u`, and stays in the clone. |
| `serve_github SPEC...` | Creates served bare repositories. The host defaults to github.com. |
| `clone_served SPEC [DIR]` | Clones a served repository over https and `cd`s into the clone. |
| `server_dir SPEC` | Prints the path of a served repository. |
| `server_ref SPEC REF` | Prints the commit that REF names on the server, or nothing. |
| `server_branches SPEC` | Prints the server's branch names, one per line. |
| `commit_on BRANCH MSG` | Makes an empty commit on BRANCH without checking it out. |
| `tip BRANCH` | Prints the commit of a local branch, or nothing. |
| `set_remote_head REMOTE BRANCH` | Sets `REMOTE/BRANCH` to `HEAD` and points `REMOTE/HEAD` at it. |
| `stub_gh 'ARGS GLOB' 'STDOUT' [STATUS]` | Answers matching gh calls with STDOUT (read as `%b`) and STATUS. |
| `stub_gh_file 'ARGS GLOB' FILE` | Answers matching gh calls with the contents of FILE. |
| `stub_patch ENDPOINT FORMAT FILE [HOST]` | Makes `gh api` answer ENDPOINT as FORMAT with FILE. |
| `gh_calls` | Prints the gh log, one call per line, with `GH_REPO=VALUE` in front when it was set. |
| `assert_gh_called GLOB` | Passes if a gh call matched GLOB. |
| `assert_gh_not_called` | Passes if gh was not called. |
| `recording_gh [stdin]` | Prints a directory for `PATH` with a gh that records its call (and its standard input). |
| `failing_gh MSG` | Prints a directory for `PATH` with a gh that writes MSG when it fails. |
| `no_gh_path [COMMAND...]` | Prints a directory for `PATH` with git, bash and these commands, never gh. |
| `opened` | Prints the URLs that the browser stub was given, one per line. |
| `copied` | Prints what the clipboard stub holds. |
| `assert_tmp_empty` | Passes if nothing is left in `$TMPDIR`. |
| `assert_success`, `assert_failure` | Checks that the last `run` exited 0, or not 0. |
| `assert_status N` | Checks that the last `run` exited N. |
| `assert_git_help CMD` | Checks that the last `run` exited as `git CMD -h` does. |
| `assert_output_equals TEXT` | Checks that the output of the last `run` is TEXT. |
| `assert_output_contains TEXT` | Checks that the output of the last `run` contains TEXT. |
| `assert_output_lacks TEXT` | Checks that the output of the last `run` does not contain TEXT. |
| `assert_line_equals N TEXT` | Checks that line N of the output is TEXT. |
| `assert_equals ACTUAL EXPECTED` | Checks that two values are equal. |

## Write a test

Follow the principles in [How hub is built](design.md#testing). Assert every
`run`'s status: a failing `a && b` or `! cmd` does not fail a bats test, so use
the assertions. A new `test/example.bats`:

```sh
#!/usr/bin/env bats
# hub push and hub fork: a push to served repositories, a fork through gh.

load test_helper

@test "hub push origin,upstream pushes the branch to both served repositories" {
  pushed_feature
  serve_github dotcom/dotfiles
  git remote add upstream https://github.com/dotcom/dotfiles.git
  run hub push origin,upstream
  assert_success
  assert_equals "$(server_ref dotcom/dotfiles refs/heads/feature)" "$(tip feature)"
  assert_gh_not_called
}

@test "hub fork asks gh for the fork and adds it as a remote" {
  serve_github dotcom/dotfiles mislav/dotfiles
  clone_served dotcom/dotfiles
  stub_gh 'api --hostname github.com --method POST repos/*/forks*' mislav/dotfiles
  run hub fork
  assert_success
  assert_gh_called 'api --hostname github.com --method POST repos/dotcom/dotfiles/forks*'
  assert_equals "$(git remote get-url mislav)" https://github.com/mislav/dotfiles.git
}
```

Run it with `bats test/example.bats`. The tests do not cover:

- gh's prompts and editor. The tests cover only hub's refusal when no
  terminal is present.
- The bash 3.2 code path. It runs only where `/bin/bash` is older than 5.
- fish beyond a syntax check with `fish -n`.
- Real GitHub, the workflows and the formula's `brew test`.

## Add a command

1. Write the header of `lib/hub/cmd/NAME.sh` first: the Summary line, the
   Usage lines, the sentence that names the kind of command, Options, and two
   or three examples. `hub help NAME` and the manuals website show it.
   [The module contract](design.md#the-module-contract) describes each part
   of the header.
2. Define `hub_cmd_NAME` (dashes become underscores). The dispatcher and
   `hub help` find the module by its file name.
3. Parse the arguments as the kind of command requires. For one of hub's own
   commands, use `hub::normalize_opts` and a closed `case` loop. For a gh
   command, use `hub::gh_subcommand`. For a git command hub extends, use
   `hub::scan` with an option table that a test pins.
4. Check everything first. Run side effects through `hub::git`, `hub::gh`
   or the `exec` helpers, lookups through `hub::git_query`, `hub::gh_query`.
5. Write `test/NAME.bats`, asserting effects.
6. Add NAME, its Summary and, for one of hub's own commands, its options to
   the three completion files. `test/completions.bats` fails until they match.
7. Run `make check`.

## Keep the completions in step

`test/completions.bats` runs `hub.bash` in `bash --noprofile --norc` and
`hub.zsh` in `zsh -f` over stubbed git completion functions, and checks the
syntax of `hub.fish`. The zsh and fish tests skip where that shell is
missing, so CI installs zsh on Linux. Each completion file must list every
module with its Summary line. For each of hub's own commands, the file must
list the options in the module's `# Options:` block.

Each file loads in its own way.
[Shell completion](../getting-started/completions.md) has the steps.

- `hub.bash` needs git's `git-completion.bash` sourced first, unless
  bash-completion or Homebrew's git loads it.
- `hub.zsh` goes on `$fpath` as `_hub`, or is sourced after `compinit`. It
  registers for git (`setopt complete_aliases`).
- `hub.fish` goes in a `vendor_completions.d` directory.

## Make a release

Write the notes under `## [Unreleased]` in `CHANGELOG.md`. Then try the
release with `-n`, which makes every check and prints the commands:

```sh
script/release -n 0.2.0
```

```text
Releasing hub 0.2.0 to github.com/brc-dd/hub
[dry-run] make check
[dry-run] script/bump 0.2.0
[dry-run] git push --atomic --no-follow-tags origin refs/heads/main:refs/heads/main refs/tags/v0.2.0:refs/tags/v0.2.0
The Release workflow publishes v0.2.0 and points Formula/hub.rb at it (gh run watch -R brc-dd/hub).
```

`script/release [-n] VERSION` stops before it commits or pushes anything
unless all of these hold:

1. `main` is checked out and clean, untracked files included.
2. origin's URL and every push URL name `REPO` on github.com. `REPO` is the
   repository that Formula/hub.rb downloads from, brc-dd/hub here.
3. VERSION is `X.Y.Z` or `X.Y.Z-PRE` (a leading `v` is dropped), and
   `git ls-remote` finds no tag `vVERSION` on origin.
4. After `git fetch origin +refs/heads/main:refs/remotes/origin/main`,
   whatever `remote.origin.fetch` says, `main` is not behind `origin/main`.
5. `gh repo view` can see `REPO`.
6. `script/bump --dry-run VERSION` passes: a new tag, notes under
   `## [Unreleased]`.
7. A stable VERSION is not lower than the version the formula names.

Then it runs `make check`, `script/bump VERSION` and one atomic push of
`main` and `vVERSION` with no other tag, whatever `push.followTags` says.
`script/bump` moves the notes to `## [VERSION] - YYYY-MM-DD`, updates the
changelog's links, writes `VERSION`, commits `hub vVERSION` and tags it (`-s`
signs). For a pre-release such as `0.2.0-rc.1`, the last line of the output
ends in "as a pre-release" in place of "and points Formula/hub.rb at it". The
scripts work in their own checkout, whatever `CDPATH` holds. A failed push
prints this, with START replaced by the commit `main` was on before the bump:

```text
script/release: the push failed (retry with git push --atomic --no-follow-tags origin refs/heads/main:refs/heads/main refs/tags/v0.2.0:refs/tags/v0.2.0, or undo the bump with git tag -d v0.2.0 && git reset --hard START)
```

The tag starts the Release workflow, which skips forks. If no release exists
for the tag, the `publish` job creates one named `hub VERSION` with generated
notes. A tag with a `-` gets a pre-release. If a draft release of the tag
exists, the job publishes it. If a published release exists, the job leaves
it alone.

For a stable tag, the `formula` job points `Formula/hub.rb` at the highest
published stable release (`script/stable-tag`), not at the tag that started
it. It pushes `Formula: hub TAG` to `main` when the formula changes. To do
this by hand, run `script/update-formula vX.Y.Z` (`-n` prints the diff).

## Publish the manuals website

`script/site DIR` writes `DIR/index.html`, the manual of `bin/hub` with the
list of commands, and `DIR/NAME.html` for every module, as static HTML with
no script or external resource. Build it into `site/` with:

```sh
script/site site
```

Each page renders a module header by the rules in
[The module contract](design.md#the-module-contract).
`test/script-site.bats` checks that a command page's text is what
`hub help NAME` prints, that the index holds `bin/hub`'s header, and that two
runs write the same bytes.

The Pages workflow deploys the site to https://brc-dd.github.io/hub/ on every
push to `main` that changes `bin/hub`, a module, `script/site`, `VERSION`,
`Formula/hub.rb` or `.github/workflows/pages.yml`, and on
`gh workflow run pages.yml`. It skips forks, and a new run waits for a
deployment in progress. Until an admin enables Pages with the GitHub Actions
source (Settings > Pages > Build and deployment > Source), the deploy job
fails. An admin can also enable it from the command line:

```sh
gh api -X POST repos/brc-dd/hub/pages -f build_type=workflow
```

## Change a workflow

[`gh actions-lock`](https://github.com/github/gh-actions-lock) records the
commit of each `uses:` tag in `.github/workflows/actions.lock`. Dependabot
updates the actions weekly with a 7-day cooldown. zizmor reads the lockfile
from 1.32 on. Older versions report unpinned actions. Check and audit the
workflows with:

```sh
gh actions-lock                                 # after you change a uses: line: record the new commits
gh actions-lock --verify                        # what CI runs: check the lockfile
actionlint .github/workflows/*.yml              # lint the workflows (make lint runs it)
uvx --from 'zizmor==1.32.0rc1' zizmor .github   # audit the workflows (needs uv)
```

## See also

- [How hub is built](design.md): the design, the module contract and the
  testing principles
- [Install hub](../getting-started/install.md)
- [Shell completion](../getting-started/completions.md)
- [CHANGELOG.md](../../CHANGELOG.md)
