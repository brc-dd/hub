---
title: hub release
description: List, view, create, edit, upload and download releases (gh release).
kind: gh command
original: https://hub.github.com/hub-release.1.html
---

# hub release

`hub release` lists, views, creates, edits, uploads and downloads the releases
of a GitHub repository. It runs `gh release` of the GitHub CLI (gh). hub
changes two things: `show` becomes `view`, and a command line without a
subcommand runs `list`. Use it to publish a version and its assets. The most
common use is `hub release`, which lists the releases of the current
repository.

```sh
hub release
# => gh release list
```

## Usage

```text
hub release [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-RELEASE-ARGS...]
```

`-R` (`--repo`) picks another repository, as in gh, and can come before or
after the subcommand. `SUBCOMMAND` is any subcommand of
[gh release](https://cli.github.com/manual/gh_release), such as `list`, `view`
(or `show`), `create`, `edit`, `upload`, `download` or `delete`.
`GH-RELEASE-ARGS` are gh's arguments for that subcommand, and they go to gh
unchanged.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git release` is the same command. Each `# =>` line is what `hub --noop`
prints: the gh command that hub runs.

List the releases of the current repository:

```sh
hub release
# => gh release list
```

List the five newest releases without drafts:

```sh
hub release -L 5 --exclude-drafts
# => gh release list -L 5 --exclude-drafts
```

An option first means `list`.

Show one release of another repository, then the latest release:

```sh
hub release -R cli/cli show v2.0.0
# => gh release -R cli/cli view v2.0.0
hub release show
# => gh release view
```

`show` is the original hub's word for `view`. Without a tag, gh shows the
latest release.

Create a release and attach an asset with a display label after `#`:

```sh
hub release create v1.2.0 'dist/hello-1.2.0.tar.gz#Hello World' --title v1.2.0 --notes 'First release'
# => gh release create v1.2.0 dist/hello-1.2.0.tar.gz#Hello\ World --title v1.2.0 --notes First\ release
```

If the tag does not exist, gh creates it from the default branch.

Create a draft with the notes from a file, and the tag at another branch:

```sh
hub release create -d v1.2.0 --title 'will_paginate 1.2.0' --notes-file message.txt --target my-branch
# => gh release create -d v1.2.0 --title will_paginate\ 1.2.0 --notes-file message.txt --target my-branch
```

Publish a draft:

```sh
hub release edit v1.2.0 --draft=false
# => gh release edit v1.2.0 --draft=false
```

The original hub used the same `--draft=false`.

Attach a file to an existing release, and replace an asset of the same name:

```sh
hub release upload v1.2.0 hello-1.2.0.tar.gz --clobber
# => gh release upload v1.2.0 hello-1.2.0.tar.gz --clobber
```

Download the assets that match a glob into the current directory:

```sh
hub release download v1.2.0 -p '*amd64*'
# => gh release download v1.2.0 -p \*amd64\*
```

The original hub spelled the option `-i`.

Print the download URLs of the assets:

```sh
hub release show v1.2.0 --json assets --jq '.assets[].url'
# => gh release view v1.2.0 --json assets --jq .assets\[\].url
```

The original hub had `show --show-downloads`.

Open a release in the web browser:

```sh
hub release show v1.2.0 -w
# => gh release view v1.2.0 -w
```

The original hub had `create -o`.

Delete a release without the confirmation prompt:

```sh
hub release delete v1.2.0 --yes
# => gh release delete v1.2.0 --yes
```

The git tag stays unless you add `--cleanup-tag`.

Read the notes from the standard input:

```sh
git log --oneline v1.1.0..v1.2.0 | hub release edit v1.2.0 --title 'Version 1.2' --notes-file -
# => gh release edit v1.2.0 --title Version\ 1.2 --notes-file -
```

hub passes each argument to gh as one word and connects the standard input to
gh.

Pass an original hub spelling, which hub does not translate:

```sh
hub release download v1.0.0 -i '*.tgz'
# => gh release download v1.0.0 -i \*.tgz
```

gh rejects `-i` here. Use gh's spelling from [Options](#options).

## Options

hub has no options of its own for `release`, apart from `-h` and `--help`
before the subcommand. The table gives the original hub's options in gh's
spelling.

| Original hub | gh's spelling | What it does |
|---|---|---|
| `release -d`, `--include-drafts` | `gh release list`. gh lists drafts by default, and `--exclude-drafts` hides them. | List the drafts too. |
| `release -p`, `--exclude-prereleases` | `gh release list --exclude-pre-releases` | Hide the prereleases. |
| `release -L LIMIT` | `gh release list -L LIMIT` | List at most `LIMIT` releases. gh's default is 30. |
| `release -f FORMAT`, `show -f FORMAT` | `--json FIELDS` with `--jq EXPR` or `-t TEMPLATE` | Format the output. |
| `release show --show-downloads` | `gh release view TAG --json assets` | List the assets of a release. |
| `release create\|edit -a FILE`, `--attach FILE` | `gh release create TAG FILE...`, or `gh release upload TAG FILE...` | Attach a file as an asset. |
| `release create\|edit -m MESSAGE`, `--message` | `--title TITLE --notes TEXT` | Set the title and the notes. In the original hub, the text up to the first blank line was the title. |
| `release create\|edit -F FILE`, `--file` | `--notes-file FILE`, with `--title TITLE` | Read the notes from `FILE`. |
| `release create\|edit -t TARGET`, `--commitish` | `--target TARGET` (gh's `-t` is the title) | Pick where a new tag goes. |
| `release create -o`, `--browse` | `gh release view TAG -w` afterwards | Open the release in the web browser. |
| `release download TAG -i GLOB`, `--include` | `gh release download TAG -p GLOB` | Download only the assets that match `GLOB`. |

Every other argument goes to `gh release` unchanged. `-h` or `--help` before
the subcommand prints hub's manual. After the subcommand, it is gh's help for
that subcommand. The meaning of each option is in gh's manual, linked under
[See also](#see-also).

## How it works

hub applies these rules in order:

1. hub reads `-R VALUE`, `-RVALUE`, `--repo VALUE` and `--repo=VALUE` at the
   start of the command line and keeps them in front.
2. If the next word is `-h` or `--help`, hub prints its manual and stops. If
   `-R` or `--repo` takes `-h` or `--help` as its value and no subcommand
   follows, hub also prints its manual. For example, `hub release -R --help`
   prints the manual, and `hub release -R --help list` goes to gh.
3. If the next word is `show`, hub writes `view` in its place.
4. If the next word is an option, or there is no next word, hub inserts
   `list`. hub does not look past an option for a subcommand. So
   `hub release -O show` runs `gh release list -O show`, and `show` stays the
   value of `-O`. `hub release -- v1.0.0` runs `gh release list -- v1.0.0`.
5. hub runs `gh release` with the arguments unchanged and connects the
   standard input to gh. A `-R` without its value goes to gh unchanged, and gh
   reports it.

Every other subcommand and option goes to gh unchanged. This includes the
original hub's spellings, which hub does not translate.

hub adds no repository and no host. gh picks the repository by its own rules:
`-R`, `GH_REPO`, `gh repo set-default`, or the remotes of the current git
repository. `GH_HOST` picks the host. `hub release` works outside a git
repository when `-R` or `GH_REPO` names the repository. If `GITHUB_HOST` is
set and `GH_HOST` is not, gh sees it as `GH_HOST`. See
[Hosts and login](../guide/hosts-and-login.md).

`hub --noop` prints the gh command and does not run it. For example,
`hub --noop release show 'v1 beta'` prints `gh release view v1\ beta`.

## Exit status

`hub release` exits with gh's status, and gh's messages reach you unchanged.
For example, a missing release gives gh's message and gh's status. hub needs
gh. Without it, hub prints the following message and exits with status 1:

```text
hub release: this command needs the GitHub CLI, gh (https://cli.github.com)
```

`hub --noop release ...` exits with 0 when gh is on `PATH`. Without gh, it
prints the message above and exits with 1, even under `--noop`.

## Differences from the original hub

| Original hub | This hub |
|---|---|
| No subcommand listed releases. `show`, `create`, `edit`, `download` and `delete` were subcommands. | Same, with gh's options and output. |
| The list hid drafts, and `-d` included them. | gh lists drafts. Add `--exclude-drafts` to hide them. |
| `-p` excluded prereleases. | `-p` is now `--exclude-pre-releases`. |
| `-f FORMAT` with placeholders such as `%T`, `%U` and `%as`. | `--json FIELDS` with `--jq` or `-t TEMPLATE`. The URL, body and assets are fields of `view` only. |
| `--color` on `list` and `show`. | Not supported. gh has no such option. |
| `show --show-downloads` added a Downloads section. | `view TAG --json assets`, or `--json tarballUrl,zipballUrl` for the archives. |
| `show`, `create`, `edit` and `download` without a tag were usage errors. | gh's rules apply. `show` without a tag shows the latest release. |
| `create -a FILE`, repeated, with `FILE#LABEL` for a label. | Files after the tag: `create TAG FILE#LABEL...`. |
| `edit -a FILE` attached assets. | `gh release upload TAG FILE...`. `--clobber` replaces an asset of the same name. |
| `-m MESSAGE`: the text up to the first blank line was the title, the rest the body. Repeated `-m` were joined with a blank line. | `--title TITLE --notes TEXT`. |
| `-F FILE` read the title and the body, `-` for the standard input. | `--notes-file FILE` (`-F`) reads only the notes. Add `--title`. |
| `-e`, `--edit` opened an editor. | Not supported. Use `--notes` or `--notes-file`. `create` also has `--generate-notes`. |
| `-t TARGET`, `--commitish` set where a new tag went. | `--target TARGET`. gh's `-t` is the title. A new tag starts at the default branch. |
| `create -o` opened the new release in the browser. | Not supported. Run `gh release view TAG -w` afterwards. |
| `create -c` copied the URL. | Not supported. Pipe it to `pbcopy`, `wl-copy` or `xclip`: `hub release view TAG --json url --jq .url \| pbcopy`. |
| `download -i PATTERN`, `--include`. | `-i` is now `-p GLOB` (`--pattern`). gh also has `-D DIR`, `-O FILE`, `-A FORMAT` and `--skip-existing`. |
| `delete TAG` deleted the release and its assets, and kept the git tag. | `delete TAG` asks first. `--yes` skips the prompt, and `--cleanup-tag` deletes the tag. |
| `-d` meant `--include-drafts` on the list, `--show-downloads` on `show`, and `--draft` on `create` and `edit`. | `-d` is `--draft` on `create` only. |
| `GITHUB_HOST` chose the GitHub Enterprise host. | It reaches gh as `GH_HOST` when `GH_HOST` is not set. |
| hub printed its own messages and output formats. | gh's messages, output and exit status. |

hub does not translate the original hub's spellings. gh receives them
unchanged, so use gh's spelling from [Options](#options).

## See also

- [hub pr](pr.md), [hub issue](issue.md), [hub gist](gist.md) and
  [hub api](api.md): the other gh commands.
- [How hub works](../guide/how-hub-works.md), for the three kinds of command
  and `--noop`.
- [Hosts and login](../guide/hosts-and-login.md), for `GH_HOST`, `GITHUB_HOST`
  and `gh auth login`.
- [Browser and clipboard](../guide/browser-and-clipboard.md), for opening a
  release with `-w` and copying its URL.
- [hub and gh](../compatibility/hub-vs-gh.md).
- [Coming from the original hub](../compatibility/README.md).
- The original hub's manual:
  [hub-release(1)](https://hub.github.com/hub-release.1.html)
- gh's manual: [gh release](https://cli.github.com/manual/gh_release),
  [list](https://cli.github.com/manual/gh_release_list),
  [view](https://cli.github.com/manual/gh_release_view),
  [create](https://cli.github.com/manual/gh_release_create),
  [edit](https://cli.github.com/manual/gh_release_edit),
  [upload](https://cli.github.com/manual/gh_release_upload),
  [download](https://cli.github.com/manual/gh_release_download) and
  [delete](https://cli.github.com/manual/gh_release_delete)
- This hub's manual: [hub release](https://brc-dd.github.io/hub/release.html)
