---
title: hub pr
description: List, view and check out pull requests (gh pr).
kind: gh command
original: https://hub.github.com/hub-pr.1.html
---

# hub pr

`hub pr` lists, shows and checks out pull requests. It runs `gh pr` of the
GitHub CLI (gh). hub changes two things: `show` becomes `view`, and a command
line without a subcommand runs `list`. The most common use is `hub pr`, which
lists the open pull requests of the current repository.

```sh
hub pr
# => gh pr list
```

## Usage

```text
hub pr [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-PR-ARGS...]
```

`-R` (`--repo`) names another repository, as in gh. `SUBCOMMAND` is any
subcommand of `gh pr`, plus `show`, which hub runs as `view`. `GH-PR-ARGS` are
the arguments of the subcommand, and they go to `gh pr` unchanged.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md), `git pr`
is the same command. Each `# =>` line is what `hub --noop` prints: the gh
command that hub runs.

List the open pull requests of the current repository:

```sh
hub pr
# => gh pr list
```

List the last five closed pull requests. When the first word is an option,
hub inserts `list` before it:

```sh
hub pr -s closed -L 5
# => gh pr list -s closed -L 5
```

Show the pull request of the current branch in the terminal:

```sh
hub pr show
# => gh pr view
```

Show pull request 12 with its comments:

```sh
hub pr show 12 --comments
# => gh pr view 12 --comments
```

Open pull request 12 in the web browser, as `hub pr show 12` of the original
hub (mislav/hub 2.x) did:

```sh
hub pr show 12 -w
# => gh pr view 12 -w
```

Show the pull request of another branch. The original hub spelled this
`hub pr show -h fix-docs`:

```sh
hub pr show fix-docs
# => gh pr view fix-docs
```

Check out pull request 77 in a branch named `review-77`:

```sh
hub pr checkout 77 -b review-77
# => gh pr checkout 77 -b review-77
```

Work on a pull request of another repository. Put `-R` before or after the
subcommand. gh reads it in both places:

```sh
hub pr -R cli/cli show 12
# => gh pr -R cli/cli view 12
hub pr -R cli/cli
# => gh pr -R cli/cli list
```

`hub pr -R cli/cli` also works outside a git repository.

Filter by the branch of the pull request and its base branch. The original hub
spelled this `hub pr list -h fix-docs -b main`:

```sh
hub pr list -H fix-docs -B main
# => gh pr list -H fix-docs -B main
```

Sort by the last update. The original hub spelled this `hub pr list -o updated`:

```sh
hub pr list -S 'sort:updated-desc'
# => gh pr list -S sort:updated-desc
```

Print only the URL of pull request 12. The original hub spelled this
`hub pr show -u 12`:

```sh
hub pr show 12 --json url --jq .url
# => gh pr view 12 --json url --jq .url
```

On macOS, copy that URL to the clipboard. The original hub spelled this
`hub pr show -c 12`:

```sh
hub pr show 12 --json url --jq .url | pbcopy
```

Print the number and title of each open pull request, in place of the original
`-f` format. hub passes each argument to `gh pr list` as one argument, with its
spaces and quotes:

```sh
hub pr list --json number,title --jq '.[] | "\(.number) \(.title)"'
```

Merge pull request 12 on GitHub with a squash commit and delete its branch:

```sh
hub pr merge 12 --squash -d
# => gh pr merge 12 --squash -d
```

## Options

hub has no options of its own for `pr`. The table gives the original hub's
options in gh's spelling.

| Original hub | gh's spelling | What it does |
|---|---|---|
| `pr list -h BRANCH -b BASE` | `gh pr list -H BRANCH -B BASE` | Filter by the branch of the pull request and its base branch. gh's `-H` takes no `OWNER:` prefix. |
| `pr list -o KEY [-^]` | `gh pr list -S 'sort:KEY-desc'` (`sort:KEY-asc`) | Sort by `created` or `updated`. |
| `pr list -o popularity` | `gh pr list -S 'sort:comments-desc'` | Sort by the number of comments. |
| `pr list\|show -f FORMAT` | `--json FIELDS` with `--jq EXPR` or `-t TEMPLATE` | Print the fields you choose. |
| `pr checkout PR BRANCH` | `gh pr checkout PR -b BRANCH` | Check out the pull request in a branch you name. |
| `pr show -h HEAD` | `gh pr view HEAD` | Show the pull request of a branch. |
| `pr show -u` | `gh pr view --json url --jq .url` | Print the URL. |
| `pr show -c` | Not supported. | gh's `-c` is `--comments`. Pipe the URL to `pbcopy`. |
| `pr show` (opens the browser) | `gh pr view -w` | Open the pull request in the browser. `hub pr show` without `-w` prints it in the terminal. |

`-s STATE` (`open`, `closed`, `merged`, `all`) and `-L LIMIT` keep their
spelling in `gh pr list`. gh lists 30 pull requests unless `-L` says otherwise.

Every other argument goes to `gh pr` unchanged, so every option and every
output is gh's. See [gh pr](https://cli.github.com/manual/gh_pr) for every
option.

## How it works

hub applies these rules in order:

1. hub keeps `-R REPO`, `-RREPO`, `--repo REPO` and `--repo=REPO` in front of
   the subcommand, where you typed them.
2. If the first word after the `-R` options is `-h` or `--help`, hub prints
   its own manual, the text of `hub help pr`. hub also prints it for
   `hub pr -R --help`, where `--help` stands in the place of the value.
3. If the next word is `show`, hub runs `view` in its place. A later `show`
   stays as it is: `hub pr -s show` runs `gh pr list -s show`.
4. If no word follows, or the next word is an option (`--` included), hub
   inserts `list` before it: `hub pr -- 12` runs `gh pr list -- 12`.
5. Any other subcommand (`checkout`, `merge`, `create`, `diff` and the rest)
   goes to gh unchanged.
6. hub then runs `gh pr` with the arguments, each kept whole, in place of
   itself.

After the subcommand, `-h` and `--help` are gh's: `hub pr show --help` prints
the help of `gh pr view`. A `-R` with no value after it, as in `hub pr -R`,
goes to gh. gh reports the missing value.

hub adds no repository and no host, and leaves your `GH_REPO` as it is. gh
picks the repository and the host, from `-R`, `GH_REPO`, `GH_HOST` and
`gh repo set-default`. If you set `GITHUB_HOST`, the variable of the original
hub, and `GH_HOST` is not set, gh receives it as `GH_HOST`. See
[Hosts and login](../guide/hosts-and-login.md) and
[How hub works](../guide/how-hub-works.md).

`hub --noop pr` prints the gh command and does not run it. gh must still be
on `PATH`. hub needs gh 2.55 or newer, logged in with `gh auth login`.

## Exit status

`hub pr` exits with gh's status, and gh's messages reach you unchanged. This
includes a failed `hub pr show` on a branch without a pull request. hub's own
refusal exits with status 1. Without gh on `PATH`, hub prints:

```text
hub pr: this command needs the GitHub CLI, gh (https://cli.github.com)
```

## Differences from the original hub

The original hub implemented `hub pr` itself. This hub hands it to gh, so the
options and the output are gh's.

| Original hub | This hub |
|---|---|
| `hub pr list`, `hub pr checkout` | Same subcommands, run by `gh pr list` and `gh pr checkout`. |
| `hub pr show` opened the pull request in the browser. | `hub pr show` is `gh pr view`, which prints it in the terminal. Add `-w` to open the browser. |
| `pr show -u` printed the URL. | Use `--json url --jq .url`. |
| `pr show -c` copied the URL. | Not supported. gh's `-c` is `--comments`. Pipe the URL to `pbcopy`, `wl-copy` or `xclip -selection clipboard`. |
| `pr show -h HEAD` and `pr list -h HEAD` | After the subcommand, `-h` is gh's help. Use `gh pr view HEAD` and `gh pr list -H HEAD`. |
| `pr list -h OWNER:BRANCH` found a fork's branch. | gh's `-H` takes no `OWNER:` prefix. |
| `pr list -b BASE` | `-B BASE`. `gh pr list` has no `-b`. |
| `pr list -o created\|updated [-^]` | `-S 'sort:KEY-desc'`, or `sort:KEY-asc` for `-^`. |
| `pr list -o popularity` | `-S 'sort:comments-desc'`. `hub help pr` gives no gh spelling for `-o long-running`. |
| `-f FORMAT` with placeholders such as `%I`, `%t`, `%U` | Not supported. Use `--json FIELDS` with `--jq` or `-t` (a Go template). |
| `--color[=WHEN]` on `list` and `show` | Not supported. `gh pr list` and `gh pr view` have no `--color` option. |
| `-L LIMIT` | Same. gh lists 30 pull requests unless `-L` says otherwise. |
| `-s open\|closed\|merged\|all` | Same. |
| `pr checkout PR-NUMBER BRANCH` | `gh pr checkout PR -b BRANCH`. hub hands a second word to gh unchanged. |
| `pr merge` (in the original hub's development branch, not in 2.14.2) | `gh pr merge`. `--squash` and `--rebase` are the same. `-m MESSAGE` is `-t` (`--subject`) with `-b` (`--body`): gh's `-m` is `--merge`. `-F FILE` is `-t SUBJECT` with `-F FILE` (`--body-file`): gh reads only the body from the file. `--head-sha` is `--match-head-commit`. gh's `-d` also deletes the local branch. |
| Messages such as `no open pull requests found for branch 'OWNER:topic'` and `invalid pull request number`, exit 1 | gh's messages and gh's exit status. |
| The repository came from hub's remotes. `GITHUB_HOST` picked the host. | gh picks the repository (`-R`, `GH_REPO`, `GH_HOST`, `gh repo set-default`). `GITHUB_HOST` reaches gh as `GH_HOST` when `GH_HOST` is not set. |

## See also

- [hub pull-request](pull-request.md), to open a pull request (`gh pr create`
  with the original hub's options).
- [hub checkout](checkout.md), to check out a pull request by its URL.
- [hub merge](merge.md), to merge a pull request locally.
- [hub ci-status](ci-status.md) and `gh pr checks`, for the checks of a commit.
- [hub issue](issue.md), the same mapping for issues.
- [Browser and clipboard](../guide/browser-and-clipboard.md) and
  [hub and gh](../compatibility/hub-vs-gh.md).
- [Coming from the original hub](../compatibility/README.md).
- The original hub's manual: [hub-pr(1)](https://hub.github.com/hub-pr.1.html).
- gh's manual: [gh pr](https://cli.github.com/manual/gh_pr),
  [gh pr list](https://cli.github.com/manual/gh_pr_list),
  [gh pr view](https://cli.github.com/manual/gh_pr_view),
  [gh pr checkout](https://cli.github.com/manual/gh_pr_checkout),
  [gh pr merge](https://cli.github.com/manual/gh_pr_merge).
- This hub's manual: [hub pr](https://brc-dd.github.io/hub/pr.html), the text
  of `hub help pr`.
