---
title: hub gist
description: List, view, create and edit gists (gh gist).
kind: gh command
original: https://hub.github.com/hub-gist.1.html
---

# hub gist

`hub gist` lists, views, creates and edits gists. It runs `gh gist` of the
GitHub CLI (gh). hub changes two things: `show` becomes `view`, and a command
line without a subcommand runs `list`. Use it to share files and command output
as gists. The most common use is `hub gist create FILE`, which uploads a file
as a secret gist and prints its URL.

```sh
hub gist create notes.md
# => gh gist create notes.md
```

## Usage

```text
hub gist [SUBCOMMAND] [GH-GIST-ARGS...]
```

`SUBCOMMAND` is one of gh's gist subcommands (`list`, `view`, `create`, `edit`,
`rename`, `clone`, `delete`) or `show`, which hub turns into `view`.
`GH-GIST-ARGS` are gh's arguments for that subcommand, and they go to gh
unchanged. A gist is an ID such as `8f3c4e2` or a URL such as
`https://gist.github.com/USER/8f3c4e2`.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md), `git gist`
is the same command. Each `# =>` line is what `hub --noop` prints: the gh
command that hub runs.

Create a secret gist from a file:

```sh
hub gist create notes.md
# => gh gist create notes.md
```

gh prints the URL of the new gist.

Create a public gist from two files, with the description `Notes`:

```sh
hub gist create -p -d Notes a.txt b.md
# => gh gist create -p -d Notes a.txt b.md
```

`-p` is the short form of `--public`, and `-d` is the short form of `--desc`.

Create a gist from standard input:

```sh
echo hello | hub gist create --public
# => gh gist create --public
```

Without a file, gh reads standard input, and hub passes its standard input to
gh.

List your gists, then only the five newest public gists:

```sh
hub gist
# => gh gist list
hub gist -L 5 --public
# => gh gist list -L 5 --public
```

Without a subcommand, hub runs `list`. When the first argument is an option,
hub puts `list` in front of it.

Print one file of a gist as plain text, without gh's rendering:

```sh
hub gist show 8f3c4e2 --raw -f notes.md
# => gh gist view 8f3c4e2 --raw -f notes.md
```

This is what the original hub's `hub gist show ID FILE` did.

View a gist by its URL:

```sh
hub gist show https://gist.github.com/USER/8f3c4e2
# => gh gist view https://gist.github.com/USER/8f3c4e2
```

gh renders the files unless you pass `--raw`.

Pick a gist from your recent ones:

```sh
hub gist show
# => gh gist view
```

`show` without an ID runs `gh gist view`, which offers recent gists to choose
from.

Create a gist and open it in the web browser:

```sh
hub gist create -w build.log
# => gh gist create -w build.log
```

The original hub spelled this `-o`. gh spells it `-w`.

Copy the URL of a new gist to the clipboard:

```sh
hub gist create build.log | pbcopy
```

gh has no copy option, so pipe its output to `pbcopy` on macOS (`wl-copy` or
`xclip -selection clipboard` on Linux).

List the files of a gist, then add a file to it with `-a` (`--add`):

```sh
hub gist view 8f3c4e2 --files
# => gh gist view 8f3c4e2 --files
hub gist edit 8f3c4e2 -a extra.md
# => gh gist edit 8f3c4e2 -a extra.md
```

Clone a gist as a git repository, rename a file in it, then delete it:

```sh
hub gist clone 8f3c4e2
# => gh gist clone 8f3c4e2
hub gist rename 8f3c4e2 old.md new.md
# => gh gist rename 8f3c4e2 old.md new.md
hub gist delete 8f3c4e2 --yes
# => gh gist delete 8f3c4e2 --yes
```

`--yes` skips gh's confirmation prompt. The other subcommands go to gh
unchanged.

## Options

hub has no options of its own for `gist`, apart from `-h` and `--help` before
the subcommand. The table gives the original hub's options in gh's spelling.

| Original hub | gh's spelling | What it does |
|---|---|---|
| `gist create --public FILE...` | `gh gist create --public FILE...` (`-p` is `--public` too) | Make the gist public. Default: secret. |
| `gist create` (no `FILE`) | `gh gist create` | Read standard input. |
| `gist create -o`, `--browse` | `gh gist create -w` (`--web`) | Open the new gist in the web browser. |
| `gist create -c`, `--copy` | Not supported. gh prints the URL: pipe it to `pbcopy`. | Copy the URL of the new gist to the clipboard. |
| `gist show ID` | `gh gist view ID --raw` | Print the gist. To get every file byte for byte, use `gh gist clone ID`. |
| `gist show ID FILE` | `gh gist view ID --raw -f FILE` | Print one file. |

Every other argument goes to `gh gist` unchanged. See gh's manual for the
options of each subcommand:
[list](https://cli.github.com/manual/gh_gist_list),
[view](https://cli.github.com/manual/gh_gist_view),
[create](https://cli.github.com/manual/gh_gist_create),
[edit](https://cli.github.com/manual/gh_gist_edit),
[rename](https://cli.github.com/manual/gh_gist_rename),
[clone](https://cli.github.com/manual/gh_gist_clone) and
[delete](https://cli.github.com/manual/gh_gist_delete).

## How it works

hub changes the subcommand and nothing else. hub applies these rules in order:

1. If `-h` or `--help` comes before the subcommand, hub prints its manual, the
   same text as `hub help gist`. After the subcommand, `--help` is gh's:
   `hub gist show --help` runs `gh gist view --help`.
2. If `-R VALUE`, `-RVALUE`, `--repo VALUE` or `--repo=VALUE` comes before the
   subcommand, hub looks past it to find the subcommand and leaves the option
   in place. `hub gist -R OWNER/REPO show 8f3c4e2` runs
   `gh gist -R OWNER/REPO view 8f3c4e2`. gh refuses the option, because
   `gh gist` has no `-R` or `--repo`. For `-R`, gh says
   `unknown shorthand flag: 'R' in -R`. If the value is `-h` or `--help` and
   nothing follows it, hub prints its manual.
3. If the subcommand is `show`, hub makes it `view`.
4. If there is no subcommand, or an option or `--` comes first, hub puts
   `list` in front of the rest: `hub gist -- show` runs
   `gh gist list -- show`.
5. Otherwise hub passes the word on as the subcommand, even a word gh does not
   know.

hub then runs `gh gist` with the result. hub keeps every argument whole, empty
ones and ones with spaces included, and gives gh its standard input.
`hub gist` works outside a git repository.

`hub --noop` prints the gh command, exits 0 and does not run gh. It does this
for every gist subcommand, even for `list` and `view`, which only read from
GitHub. gh must still be installed: without it, hub exits 1 with the message
under Exit status.

hub adds no host and no repository. gh picks the host, even for a gist URL that
names another host: `GH_HOST`, else the one host gh is logged in to, else
github.com. The original hub's `GITHUB_HOST` reaches gh as `GH_HOST` when
`GH_HOST` is not set. See [Hosts and login](../guide/hosts-and-login.md).

## Exit status

`hub gist` exits with gh's status, and the messages are gh's. For example,
`hub gist show 0000` exits with gh's status when gh cannot find the gist.
hub's own refusal exits with status 1. If gh is not installed, hub prints:

```text
hub gist: this command needs the GitHub CLI, gh (https://cli.github.com)
```

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub gist create [FILES...]` uploaded files, or standard input without files, and printed the URL. | Same, through `gh gist create`. |
| `--public` made the gist public. Gists were secret by default. | Same. `-p` is `--public` too. |
| `-o`, `--browse` opened the new gist. | `-o` is now `-w` (`--web`). |
| `-c`, `--copy` copied the URL to the clipboard. | Not supported. Pipe gh's output to `pbcopy`. |
| `hub gist show ID` printed the gist's content. | `show` runs `gh gist view`, which renders the content. Add `--raw` for the plain content. |
| `hub gist show ID FILE` printed one file. A gist with several files and no `FILE` was an error. | The second operand is not translated. Use `--raw -f FILE`. `gh gist view ID` shows the whole gist. |
| There was no list, edit, rename, clone or delete. | No subcommand runs `gh gist list`. gh's other subcommands work as `hub gist edit`, `rename`, `clone` and `delete`. |
| hub printed its own error messages, such as `Error creating gist: Not Found (HTTP 404)` and a hint about token scopes. | gh's messages and exit status. |
| `GITHUB_HOST` selected GitHub Enterprise. | `GITHUB_HOST` reaches gh as `GH_HOST` when `GH_HOST` is not set. |
| `hub gist` did not need a git repository. | Same. |
| `hub am` and `hub apply` accepted gist URLs. | Not supported. Run `gh gist clone ID`, then apply the file. |

## See also

- [hub api](api.md), [hub issue](issue.md), [hub pr](pr.md) and
  [hub release](release.md): the other gh commands.
- [hub am](am.md) and [hub apply](apply.md): they do not take gist URLs.
- [How hub works](../guide/how-hub-works.md), for gh commands and `--noop`.
- [Hosts and login](../guide/hosts-and-login.md).
- [Browser and clipboard](../guide/browser-and-clipboard.md).
- [hub and gh](../compatibility/hub-vs-gh.md).
- [Coming from the original hub](../compatibility/README.md).
- The original hub's manual:
  [hub-gist(1)](https://hub.github.com/hub-gist.1.html)
- gh's manual: [gh gist](https://cli.github.com/manual/gh_gist)
- This hub's manual: [hub gist](https://brc-dd.github.io/hub/gist.html)
