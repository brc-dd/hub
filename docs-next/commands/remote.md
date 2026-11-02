---
title: hub remote
description: Add or change a remote by its GitHub OWNER[/REPO] name.
kind: git command hub extends
original: https://hub.github.com/hub-remote.1.html
---

# hub remote

`hub remote` adds or changes a remote by its GitHub name. It is `git remote`
with one addition: in `add` and `set-url`, it also accepts a GitHub `OWNER` or
`OWNER/REPO` where git expects a URL, and puts the clone URL in its place. A
command line without such a name goes to `git remote` unchanged. The most
common use is `hub remote add alice`, which adds alice's copy of the current
repository as the remote `alice`.

```sh
hub remote add alice
# => git remote add alice https://github.com/alice/dotfiles.git
```

## Usage

```text
hub remote add [-p] [GIT-REMOTE-ADD-OPTIONS...] NAME OWNER[/REPO]
hub remote add [-p] [GIT-REMOTE-ADD-OPTIONS...] USER
hub remote set-url [-p] [--push] [--add] NAME OWNER[/REPO]
```

`NAME` is the name of the remote. `OWNER[/REPO]` is the repository on GitHub.
Without `/REPO`, hub takes the repository name of the current project (see
[Project and remotes](../guide/project-and-remotes.md)). `USER` alone names
both the remote and the owner, and `origin` alone means your own copy of the
repository.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git remote` is the same command. Each `# =>` line is what `hub --noop` prints:
the git command that hub runs. The examples run in a clone of OWNER/dotfiles,
where the setting `git_protocol` of the GitHub CLI (gh) is https. With
`gh config set git_protocol ssh`, hub writes `git@github.com:OWNER/REPO.git`
instead. `LOGIN` stands for your GitHub login.

Add a collaborator's copy of the repository, named after the collaborator:

```sh
hub remote add alice
# => git remote add alice https://github.com/alice/dotfiles.git
```

Add your own copy as `origin`. hub asks gh for your login on the project's
host:

```sh
hub remote add origin
# => git remote add origin https://github.com/LOGIN/dotfiles.git
```

Give the remote a name of your choice, and name another repository:

```sh
hub remote add work alice
# => git remote add work https://github.com/alice/dotfiles.git
hub remote add upstream github/hub.git
# => git remote add upstream https://github.com/github/hub.git
```

Write an ssh URL for this command only with `-p`. `-p` can come before or
after the operands:

```sh
hub remote set-url -p upstream github/hub
# => git remote set-url upstream git@github.com:github/hub.git
hub remote add bob carol/tools -p
# => git remote add bob git@github.com:carol/tools.git
```

Combine hub's `-p` with git's options. hub passes git's options to git in the
place you typed them. In a cluster such as `-fp`, hub removes the `p` and keeps
`-f`:

```sh
hub remote add -f -t main --no-tags alice
# => git remote add -f -t main --no-tags alice https://github.com/alice/dotfiles.git
hub remote add -fp alice
# => git remote add -f alice git@github.com:alice/dotfiles.git
```

Point an existing remote somewhere else, or set only its push URL:

```sh
hub remote set-url origin alice
# => git remote set-url origin https://github.com/alice/dotfiles.git
hub remote set-url --push origin alice
# => git remote set-url --push origin https://github.com/alice/dotfiles.git
hub remote set-url --add --push origin bob
# => git remote set-url --add --push origin https://github.com/bob/dotfiles.git
```

Pass a URL, a local path or any other subcommand. These command lines are
plain `git remote`:

```sh
hub remote add up https://example.com/x.git
# => git remote add up https://example.com/x.git
hub remote add rel ../x
# => git remote add rel ../x
hub remote add three ghe.example.com/o/r
# => git remote add three ghe.example.com/o/r
hub remote set-url --delete --push origin alice
# => git remote set-url --delete --push origin alice
hub remote set-url origin alice dotfiles
# => git remote set-url origin alice dotfiles
hub remote rename origin alice
# => git remote rename origin alice
hub remote -v
# => git remote -v
```

In each, git receives the words exactly as typed. `hub remote` does not expand
`HOST/OWNER/REPO`. With `--delete`, git reads `alice` as a pattern. With three
operands, git reads `NEWURL OLDURL`. The last two are another subcommand and
no subcommand.

Name the remote when you give `OWNER/REPO`. When `OWNER/REPO` is the only
operand of `add`, hub does not expand it. git gets the command line and prints
its usage (status 129):

```sh
hub remote add alice/dots
# => git remote add alice/dots
hub remote add alice alice/dots
# => git remote add alice https://github.com/alice/dots.git
```

Ask for help. `--help` and `-h` are git's:

```sh
hub remote add alice --help
# => git remote add alice --help
```

`hub help remote` prints hub's manual of this command.

## Options

`hub remote` has one option of its own, `-p`. Every option of `git remote add`
and `git remote set-url` (`-f`, `-t`, `-m`, `--mirror`, `--tags`, `--no-tags`,
`--push`, `--add`) stays as git defines it and reaches git in the place you
typed it. hub reads these options only to find the operands:

| Option | What it does |
|---|---|
| `-p` | Use an ssh URL (`git@HOST:OWNER/REPO.git`). hub removes `-p` before it runs git. Default: gh's `git_protocol` for the host (`gh config set git_protocol ssh`), else https. |
| `-t`, `-m` | Take the next word, or the rest of the cluster, as the option's value. A `p` there stays git's. |
| `--`, `--end-of-options` | Read `-p` after it as a word for git. |
| `-h`, `--help` | Hand the whole command line to git. |

## How it works

hub applies these rules in order. The first rule that hands the command line
to git ends the work, and hub runs `git remote` with your words unchanged.

1. Before the subcommand, hub skips git's `-v`, `--verbose` and
   `--no-verbose`, and their abbreviations such as `--verb`. hub passes any
   other word there to git. For example, git rejects `hub remote -x add carol`
   with status 129. In `hub remote -v add work alice`, hub skips `-v` and
   replaces `alice` with its clone URL.
2. A subcommand other than `add` or `set-url` goes to git.
3. hub removes `-p` wherever it stands before `--`, also in a cluster such as
   `-fp` or `-pt main`. A `p` that is the value of `-t` or `-m` stays git's.
   In `hub remote add -tp dave`, `p` is the branch to track. After `--` or
   `--end-of-options`, `-p` is a word for git.
4. If hub cannot read the command line with certainty, it goes to git
   unchanged. This happens with an abbreviated option that takes a value, as
   in `add --tra main zed alice`, where git adds the remote `zed` with the URL
   `alice`. It also happens with a value option as the last word, as in
   `add bob alice -t`. `-h` and `--help` go to git too.
5. `set-url --delete`, abbreviated too, goes to git, because its operand is a
   pattern.
6. Outside a git repository, the command line goes to git, and git prints its
   `not a git repository` error (status 128).
7. With one operand after `add`, hub expands it only if it is a valid GitHub
   owner name: letters, digits and single hyphens. With two operands after
   `add` or `set-url`, hub expands the second one. With any other count, git
   gets the command line. This includes `set-url NAME NEWURL OLDURL`.
8. hub keeps the second operand as typed when it is not an `OWNER[/REPO]`
   shorthand, when git can read it as a local path (from the current directory
   or from the top of the work tree), or when it has no `/` and is not a valid
   owner name. `alice/.git` and `alice/..git` stay paths.
9. With two operands, a second operand that git rewrites through
   `url.BASE.insteadOf` stays as typed, even when it also names a remote. That
   includes a `-c` value such as
   `hub -c url.git@corp.example.test:.insteadOf=corp/ remote add up corp/proj`.
   A rewrite set only through `url.BASE.pushInsteadOf` does not count: hub
   expands that word. A lone `USER` after `add` is expanded even when git
   rewrites it.

When hub expands the word, it builds the URL from four parts:

- The repository is the `REPO` you typed, with `.git` removed. Without
  `/REPO`, it is the project's repository name, from `GH_REPO` or from the
  first GitHub remote among `upstream`, `github`, `origin` and then the
  others, else the name of the repository's directory. hub replaces each
  character outside `A-Za-z0-9_.-` with `-`, so `my project` becomes
  `my-project`, and a bare `tool.git` becomes `tool`.
- The host is the project's host, else the default host (`GH_HOST`, else the
  one host gh is logged in to, else github.com). See
  [Hosts and login](../guide/hosts-and-login.md).
- `origin` alone becomes your login on that host. `hub remote add NAME origin`
  and `hub remote add origin OWNER` take `origin` as a plain name.
- The protocol is ssh with `-p`, else gh's `git_protocol` for the host, else
  https. Without gh, hub uses https, and only `origin` alone needs gh.

hub does not ask GitHub whether the repository exists. It writes the URL as
you typed the owner and repository. [Project and
remotes](../guide/project-and-remotes.md) explains the project and its remotes.

## Exit status

`hub remote` exits with git's status. hub's own refusals exit with status 1
and change no remote:

```text
hub remote: this command needs the GitHub CLI, gh (https://cli.github.com)
hub remote: could not determine your GitHub login for github.com (run: gh auth login -h github.com)
hub remote: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL
hub remote: not a host name: HOST
```

The first two come from `origin` alone, without gh or without a known login.
The last two come from a `GH_REPO` or `GH_HOST` value that hub cannot read.
git's own errors reach you unchanged. For example, `hub remote add origin bob`
in a repository that has `origin` prints `error: remote origin already
exists.` with status 3.

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub remote add USER/REPO` added the remote `USER`. | Not supported. git gets the command line. Name the remote: `hub remote add OWNER OWNER/REPO`. |
| `hub remote add USER`, `NAME USER[/REPO]`, `origin`, and `set-url NAME USER[/REPO]` expanded the name. | Same. |
| `-p` was deprecated. The protocol came from `HUB_PROTOCOL` or `hub.protocol`, https by default. Under the default, `-p` still gave https. | `-p` is ssh for this one command. Otherwise gh's `git_protocol` decides: `gh config set git_protocol ssh`. `HUB_PROTOCOL` and `hub.protocol` are not read. |
| hub looked the repository up through the API. A missing one exited 1 with `Error: repository OWNER/dotfiles doesn't exist`. | No lookup. hub writes the URL for the name you typed. |
| Your own login was matched without regard to case and written with GitHub's spelling (`login` became `Login`). | The owner is written as typed. Only `origin` alone asks gh for your login. |
| `REPOSITORY` defaulted to the current directory's name, by the manual. | The project's repository name first (`GH_REPO`, then `upstream`, `github`, `origin`), else the directory's name. |
| The GitHub Enterprise host came from the existing remote, with the host listed in `hub.host`. | The project's host, else the default host. Use `gh auth login -h HOST` and `GH_HOST` in place of `hub.host`. |
| URLs, local paths and `host:path` words passed through. | Same. Also `HOST/OWNER/REPO`, a word without `/` that is not a valid owner name, and a second operand that git rewrites through `url.BASE.insteadOf`, even when it names a remote. |
| Too many operands (`hub --noop remote add a b carol`) printed the command line unchanged. | Same. |
| `hub -C DIR remote add origin` ran in `DIR`. | Same. git applies its global options. |
| Printed nothing on success. | Same. git's own output, if any. |

## See also

- [hub fetch](fetch.md): add a missing user's remote, then fetch.
- [hub fork](fork.md): fork the repository and add the fork as a remote.
- [hub clone](clone.md): clone a repository by its `OWNER/REPO` name.
- [hub push](push.md): push to several remotes at once.
- [Repositories and URLs](../guide/repositories-and-urls.md): the shorthands
  and the URLs hub builds.
- [Project and remotes](../guide/project-and-remotes.md): the project and its
  remotes.
- [Hosts and login](../guide/hosts-and-login.md): the host and your login.
- [Configuration](../guide/configuration.md): gh's `git_protocol` and the
  other settings.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-remote(1)](https://hub.github.com/hub-remote.1.html)
- git's manual: [git remote](https://git-scm.com/docs/git-remote)
