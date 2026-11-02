---
title: hub issue
description: List, view, create and edit issues (gh issue).
kind: gh command
original: https://hub.github.com/hub-issue.1.html
---

# hub issue

`hub issue` lists, views, creates and edits the issues of a GitHub repository.
It runs `gh issue` of the GitHub CLI (gh). hub changes two things: `show`
becomes `view`, and a command line without a subcommand runs `list`. Every
option and every line of output is gh's. The most common use is `hub issue`,
which lists the open issues of the current repository.

```sh
hub issue
# => gh issue list
```

## Usage

```text
hub issue [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-ISSUE-ARGS...]
```

`-R` (`--repo`) names the repository, as in gh. `SUBCOMMAND` is any
`gh issue` subcommand, such as `list`, `view`, `create`, `edit`, `close` or
`transfer`, or `show` for `view`. `GH-ISSUE-ARGS` go to gh unchanged.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git issue` is the same command. Each `# =>` line is what `hub --noop` prints:
the gh command that hub runs. hub quotes each argument for the shell, so you
can copy the printed command line and run it.

List the open issues of the current repository:

```sh
hub issue
# => gh issue list
```

List at most five closed issues. When the first word is an option, hub adds
`list`:

```sh
hub issue -s closed -L 5
# => gh issue list -s closed -L 5
```

Show an issue with its comments, then an issue of another repository. hub
keeps `-R` in front of the subcommand:

```sh
hub issue show 7 --comments
# => gh issue view 7 --comments
hub issue -R cli/cli show 12
# => gh issue -R cli/cli view 12
```

List the issues that `USER` opened and that mention `OTHER`, then the issues
with the label `bug` in the milestone `v1.0`. The original hub
(mislav/hub 2.x) spelled these `hub issue -c USER -@ OTHER` and
`hub issue -M v1.0 -l bug`:

```sh
hub issue -A USER --mention OTHER
# => gh issue list -A USER --mention OTHER
hub issue -m v1.0 -l bug
# => gh issue list -m v1.0 -l bug
```

Sort by the number of comments, fewest first, then list the issues updated
on or after a date. The original hub spelled these `hub issue -o comments -^`
and `hub issue -d 2026-10-01`:

```sh
hub issue -S 'sort:comments-asc'
# => gh issue list -S sort:comments-asc
hub issue -S 'updated:>=2026-10-01'
# => gh issue list -S updated:\>=2026-10-01
```

Print each issue's number and author. This replaces the original hub's
`-f "%I,%au%n"`. hub hands the command line to `gh issue list` unchanged:

```sh
hub issue --json number,author --jq '.[] | "\(.number),\(.author.login)"'
# => gh issue list --json number\,author --jq .\[\]\ \|\ \"\\\(.number\)\,\\\(.author.login\)\"
```

gh prints one line per issue, such as `12,USER`.

Create an issue with a title and a body, or fill in the new issue form in the
browser. The original hub used `-o` for the browser:

```sh
hub issue create -t Crash -b 'It crashes.'
# => gh issue create -t Crash -b It\ crashes.
hub issue create -t Crash -w
# => gh issue create -t Crash -w
```

Create an issue whose body comes from standard input. gh reads it, because
hub gives gh its standard input:

```sh
echo 'It crashes on start.' | hub issue create -t Crash -F -
# => gh issue create -t Crash -F -
```

Add one label and remove another. The original hub's `issue update` is
`gh issue edit`:

```sh
hub issue edit 12 --add-label bug --remove-label wontfix
# => gh issue edit 12 --add-label bug --remove-label wontfix
```

Close an issue as a duplicate, then reopen it:

```sh
hub issue close 12 --duplicate-of 7
# => gh issue close 12 --duplicate-of 7
hub issue reopen 12
# => gh issue reopen 12
```

Move an issue to another repository:

```sh
hub issue transfer 12 cli/go-gh
# => gh issue transfer 12 cli/go-gh
```

See what hub would run without running it:

```sh
hub --noop issue create -t 'two words' -b ''
# => gh issue create -t two\ words -b ''
```

Run a spelling of the original hub that gh does not share. hub passes it on,
and gh refuses it:

```sh
hub issue labels
# => gh issue labels
```

```text
unknown command "labels" for "gh issue"
```

## Options

hub has no options of its own here. The table maps the original hub's options
to gh's spelling. An original hub option works only when gh spells it the
same way, such as `-s`, `-a`, `-l` and `-L`.

| Original hub | gh's spelling | What it does |
|---|---|---|
| `issue -c CREATOR` | `gh issue list -A CREATOR` | List the issues `CREATOR` opened. |
| `issue -@ USER` | `gh issue list --mention USER` | List the issues that mention `USER`. |
| `issue -M MILESTONE` | `gh issue list -m MILESTONE` | List the issues in a milestone. |
| `issue -o KEY` | `gh issue list -S 'sort:KEY-desc'` | Sort by `KEY`, such as `created`, `updated` or `comments`. |
| `issue -o KEY -^` | `gh issue list -S 'sort:KEY-asc'` | Sort in ascending order. |
| `issue -d DATE` | `gh issue list -S 'updated:>=DATE'` | List the issues updated on or after `DATE`. |
| `issue`, `issue show -f FORMAT` | `--json FIELDS` with `--jq EXPR` or `-t TEMPLATE` | Format the output. |
| `issue show NUMBER` | `gh issue view NUMBER` | Show an issue. `-c` adds the comments. |
| `issue create -m MESSAGE` | `gh issue create -t TITLE -b BODY` | Set the title and the body. |
| `issue create -F FILE` | `gh issue create -t TITLE -F FILE` | Read the body from `FILE`. In gh, `-F` is the body only. |
| `issue create -e` | `gh issue create -e` | Write the title and the body in the editor. |
| `issue create -o` | `gh issue create -w` | Open the new issue form in the browser. |
| `issue create -M`, `-l`, `-a` | `gh issue create -m`, `-l`, `-a` | Set the milestone, the labels and the assignees. |
| `issue update N ...` | `gh issue edit N ...` | Change an issue. |
| `issue update N -l LABELS` | `gh issue edit N --add-label`, `--remove-label` | Add or remove labels. |
| `issue update N -a USERS` | `gh issue edit N --add-assignee`, `--remove-assignee` | Add or remove assignees. |
| `issue update N -s closed` | `gh issue close N` | Close an issue. `gh issue reopen N` opens it again. |
| `issue labels` | `gh label list` | List the repository's labels. |
| `issue transfer N REPO` | `gh issue transfer N OWNER/REPO` | Move an issue to another repository. |
| `issue -a ASSIGNEE` | `gh issue list -a ASSIGNEE` | List the issues assigned to `ASSIGNEE`. |
| `issue -s STATE` | `gh issue list -s STATE` | List by state: `open`, `closed` or `all`. Default: `open`. |
| `issue -l LABELS` | `gh issue list -l LABEL` | List the issues with a label. |
| `issue -L LIMIT` | `gh issue list -L LIMIT` | List at most `LIMIT` issues. Default: 30 (gh's). |

Every other argument goes to `gh issue` unchanged, so every gh option works.
`-R` and `--repo` are gh's, and hub keeps them where they are. See gh's
manual, [gh issue](https://cli.github.com/manual/gh_issue), for every option.

## How it works

hub applies these rules in order:

1. hub reads `-R VALUE`, `-RVALUE`, `--repo VALUE` and `--repo=VALUE` at the
   start of the command line and keeps them in front of the subcommand. A `-R`
   or `--repo` with no value after it goes to gh unchanged, with no `list`:
   `hub issue -R` runs `gh issue -R`, and gh says `flag needs an argument: -R`.
2. If the next word is `-h` or `--help`, hub prints its own manual, the same
   text as `hub help issue`. `hub issue -R --help` and `hub issue --repo -h`
   also print hub's manual when nothing follows. When any other word follows,
   a subcommand or an option, as in `hub issue -R --help list`, hub passes the
   command line to gh, and gh refuses the value.
3. If the next word is `show`, hub runs `view` in its place.
4. If the next word is an option, `--` or nothing, hub puts `list` before it.
   A word after an option is that option's value, so `hub issue -s show` runs
   `gh issue list -s show`, and `hub issue -- show 12` runs
   `gh issue list -- show 12`.
5. Any other word, such as `create`, `close` or `update`, goes to gh
   unchanged.
6. hub then runs `gh issue` with the command line. gh replaces hub's process
   and gets hub's standard input. Every argument stays whole, an empty one
   included.

hub adds no repository and no host. gh picks them: `-R`, `GH_REPO`, `GH_HOST`,
or the default that `gh repo set-default` saved. If `GITHUB_HOST` is set and
`GH_HOST` is not, gh gets `GITHUB_HOST` as `GH_HOST`. See
[Hosts and login](../guide/hosts-and-login.md).

`hub issue` runs outside a repository too, for example with `-R cli/cli`.
After the subcommand, `-h` and `--help` are gh's: `hub issue show --help`
prints the help of `gh issue view`.

## Exit status

`hub issue` exits with gh's status, and gh's messages reach you unchanged.
`hub issue show 99` for an issue that does not exist prints gh's error and
exits with gh's status, 1.

hub's own refusal exits with status 1. hub needs gh. Without it, hub prints:

```text
hub issue: this command needs the GitHub CLI, gh (https://cli.github.com)
```

## Differences from the original hub

| Original hub | This hub |
|---|---|
| hub's own options and output. | gh's options and output. hub changes only two things: `show` runs `view`, and no subcommand runs `list`. |
| `hub issue` listed the open issues. | Same. It runs `gh issue list`. |
| `hub issue show NUMBER` | Same. It runs `gh issue view NUMBER`, and gh prints its own layout. |
| `-c CREATOR` and `-@ USER` | `-A CREATOR` and `--mention USER`. |
| `-M MILESTONE` | `-m MILESTONE`. |
| `-d DATE`, `-o KEY` and `-^` | `-S` with `updated:>=DATE` or `sort:KEY-desc` (`sort:KEY-asc`). |
| `-f FORMAT` with placeholders such as `%I` and `%t` | `--json FIELDS` with `--jq EXPR` or `-t TEMPLATE`. |
| `--color` | Not supported. `gh issue list`, `gh issue view` and `gh label list` have no such flag. |
| The list fetched every page. | gh lists 30 issues unless you pass `-L`. |
| `--include-pulls` | Not supported. Use `gh search issues --include-prs -R OWNER/REPO`. |
| `create -m MESSAGE`: the text up to the first blank line was the title, the rest the body. | `create -t TITLE -b BODY`. |
| `create -F FILE` held the title and the body. | `-F FILE` is the body only. Pass the title with `-t`. |
| `create -o` opened the new issue. | `create -w` opens the new issue form. |
| `create -c` copied the URL. | Not supported. Pipe the URL that gh prints to `pbcopy`. |
| `issue update N` | `gh issue edit N`. The word `update` goes to gh, which does not know it. |
| `update -l` and `-a` replaced the labels and the assignees. | `--add-label`, `--remove-label`, `--add-assignee`, `--remove-assignee`. |
| `update -s closed` and `-s open` | `gh issue close N` and `gh issue reopen N`. |
| `issue labels` | `gh label list`. `hub issue labels` goes to gh, which does not know it. |
| `issue transfer N REPO` | `gh issue transfer N OWNER/REPO`. |
| `GITHUB_HOST` | Same. gh gets it as `GH_HOST` when `GH_HOST` is not set. |

The original hub's spellings that gh does not share reach gh unchanged, and
gh refuses them, as the last example shows. Use the gh form from the table.

## See also

- [hub pr](pr.md), [hub release](release.md), [hub gist](gist.md) and
  [hub api](api.md), the other gh commands.
- [How hub works](../guide/how-hub-works.md) and
  [Hosts and login](../guide/hosts-and-login.md).
- [hub and gh](../compatibility/hub-vs-gh.md).
- [Coming from the original hub](../compatibility/README.md).
- The original hub's manual:
  [hub-issue(1)](https://hub.github.com/hub-issue.1.html)
- gh's manual: [gh issue](https://cli.github.com/manual/gh_issue)
