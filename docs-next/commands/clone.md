---
title: hub clone
description: Clone a GitHub repository by its [OWNER/]REPO name.
kind: git command hub extends
original: https://hub.github.com/hub-clone.1.html
---

# hub clone

`hub clone` clones a GitHub repository by its short name, `OWNER/REPO`, or
`REPO` alone for one of your own repositories. It is `git clone` with one
addition: hub turns the short name into a clone URL and keeps every other
argument where you put it. A command line without a short name goes to
`git clone` unchanged. The most common use is `hub clone OWNER/REPO`, which
clones that repository without typing its URL.

```sh
hub clone rails/rails
# => git clone https://github.com/rails/rails.git
```

## Usage

```text
hub clone [-p] [GIT-CLONE-OPTIONS...] [OWNER/]REPO [DIR]
```

`OWNER/REPO` is any repository on the default host. `REPO` alone is a
repository that your GitHub login owns. `OWNER/REPO.wiki` is the repository's
wiki. `DIR` is the directory to clone into, as in `git clone`.
`GIT-CLONE-OPTIONS` is any option of `git clone`.
[Repositories and URLs](../guide/repositories-and-urls.md) lists every short
name and URL hub accepts.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git clone` is the same command. Each `# =>` line is what `hub --noop` prints:
the git or gh command that hub runs. The examples assume that the GitHub CLI
(gh) has `git_protocol` set to `https` for the host, the default. `LOGIN`
stands for your GitHub login.

Clone a repository by its owner and name:

```sh
hub clone rails/rails
# => git clone https://github.com/rails/rails.git
```

Clone your own repository by its name alone. hub asks gh for your login:

```sh
hub clone dotfiles
# => git clone https://github.com/LOGIN/dotfiles.git
```

Clone over ssh this time, whatever gh's `git_protocol` says:

```sh
hub clone -p rails/rails
# => git clone git@github.com:rails/rails.git
```

Add git's own options before or after the name. hub keeps them in place:

```sh
hub clone rails/rails --depth 1 --single-branch
# => git clone https://github.com/rails/rails.git --depth 1 --single-branch
hub clone -o upstream -b main rails/rails
# => git clone -o upstream -b main https://github.com/rails/rails.git
```

Put `-p` anywhere before `--`, even after the directory or inside a cluster of
flags. hub takes it out of the command line, so git never sees it:

```sh
hub clone --depth 1 rails/rails -p myrails
# => git clone --depth 1 git@github.com:rails/rails.git myrails
hub clone -qp cli/cli
# => git clone -q git@github.com:cli/cli.git
```

Clone a wiki, or a repository whose name has dots in it:

```sh
hub clone rails/rails.wiki
# => git clone https://github.com/rails/rails.wiki.git
hub clone LOGIN.github.io
# => git clone https://github.com/LOGIN/LOGIN.github.io.git
hub clone .github
# => git clone https://github.com/LOGIN/.github.git
```

Leave a trailing `.git` on the name. hub drops it before it builds the URL:

```sh
hub clone rails/rails.git
# => git clone https://github.com/rails/rails.git
```

Clone from GitHub Enterprise. Set `GH_HOST` (or `GITHUB_HOST`) to the host:

```sh
GH_HOST=ghe.example.com hub clone kim/tool
# => git clone https://ghe.example.com/kim/tool.git
```

Clone over ssh from a `*.ghe.com` host. `-p` uses the first part of the host
name as the ssh user, so for `acme.ghe.com` the ssh user is `acme`:

```sh
GH_HOST=acme.ghe.com hub clone -p kim/tool
# => git clone acme@acme.ghe.com:kim/tool.git
```

Give a URL or `HOST/OWNER/REPO`, and it goes to `git clone` unchanged:

```sh
hub clone git@github.com:rails/rails.git
# => git clone git@github.com:rails/rails.git
hub clone github.com/rails/rails
# => git clone github.com/rails/rails
```

Git reads `github.com/rails/rails` as a local path and fails, because no such
directory exists. To clone from another host, run
`GH_HOST=HOST hub clone OWNER/REPO`, or give the URL.

Clone a local repository whose name looks like a short name. Write `./NAME`:

```sh
hub clone ./proj copy
# => git clone ./proj copy
```

Write `--depth 1` or `-q -b main` in full. When hub cannot read the command
line with certainty, it hands the whole command line to git:

```sh
hub clone --dep 1 rails/rails
# => git clone --dep 1 rails/rails
hub clone -qb main rails/rails
# => git clone -qb main rails/rails
hub clone rails/rails --depth
# => git clone rails/rails --depth
```

Git then reports that `--depth` requires a value. With `--depth 1` or
`-q -b main`, hub expands the name.

## Options

`hub clone` has one option of its own, `-p`. Every option of `git clone` stays
as it is and reaches git in its place. hub reads these options only to find
the operands:

| Option | What it does |
|---|---|
| `-p` | Clone over ssh this time (`git@HOST:OWNER/REPO.git`). hub takes `-p` out of the command line wherever it stands before `--` or `--end-of-options`, alone or in a cluster such as `-qp`. A `-p` that is the value of an option, or that follows `--`, stays git's: `hub clone -o -p rails/rails` names the remote `-p`. Default: gh's `git_protocol` for the host, else https. |
| `-o`, `--origin`, `-b`, `--branch`, `-u`, `--upload-pack`, `--reference`, `--reference-if-able`, `--separate-git-dir`, `--depth`, `--shallow-since`, `--shallow-exclude`, `-j`, `--jobs`, `--template`, `-c`, `--config`, `--filter`, `--bundle-uri`, `--server-option`, `--ref-format`, `--revision` | git's options that take a separate value. hub reads the next word as the value, so in `hub clone -b main rails/rails`, `main` is never the repository. hub also reads a value joined to its option, as in `--branch=main` or `-omine`. |
| `--`, `--end-of-options` | End the options. The next word is still the repository, and hub expands it. |
| `-h`, `--help` | Print git's help. hub drops `-p` here too, so `hub clone -p --help` also prints git's help. |

Every other option is git clone's, and hub hands it to git unchanged. Run
`git clone --help` for git's manual.

## How it works

hub applies these rules in order:

1. hub takes `-p` out of the command line, as [Options](#options) describes.
2. hub finds the repository operand: the first word that is neither an option
   nor an option's value.
3. If there is no repository operand, hub runs `git clone` with the rest of the
   command line, and git prints its own usage error.
4. If the operand is not a short name, hub runs `git clone` with the command
   line unchanged. That covers URLs, `git@HOST:` addresses, `HOST/OWNER/REPO`,
   and words that are not GitHub names, such as `o/r/`, `owner__x/r`, or
   `x/..git` (whose name is `.` once `.git` is dropped).
5. If git would read the operand as a local repository, hub runs `git clone`
   unchanged. That is an existing path of that name (file or directory), a
   `NAME.git` that holds a repository or a work tree, or a `NAME.bundle` file.
   An empty `NAME.git` directory does not count.
6. Otherwise hub builds the URL on the default host and runs `git clone` with
   the URL in place of the operand. Every other word stays where it was.

If hub cannot read the command line with certainty, it hands the whole
command line to git before it looks anything up. That happens for an
abbreviated long option (`--dep 1`), a cluster in which an option that takes a
value follows another letter (`-qb main`), and an option that needs a value as
the last word (`--depth` at the end).

The host is `GH_HOST`, else the only host gh is logged in to, else github.com.
`GITHUB_HOST` counts as `GH_HOST` when `GH_HOST` is not set. hub writes the
host in lowercase and refuses a value that is not a host name. See
[Hosts and login](../guide/hosts-and-login.md).

The owner comes from `OWNER/REPO`. For `REPO` alone, hub runs
`gh config get user -h HOST` for your login. If `GH_TOKEN`, `GITHUB_TOKEN`,
`GH_ENTERPRISE_TOKEN` or `GITHUB_ENTERPRISE_TOKEN` is set, hub runs
`gh api --hostname HOST user --jq .login` instead, because the token can
belong to another account.

With `-p`, the protocol is ssh. Without `-p`, hub runs
`gh config get git_protocol -h HOST`: `ssh` gives an ssh URL, anything else
gives https. To make ssh the default, run `gh config set git_protocol ssh`.

hub looks up nothing else on GitHub. It does not check that the repository or
its wiki exists. Git reports that when it clones. Without gh installed,
`OWNER/REPO` still works over https, and `-p` over ssh. `REPO` alone needs gh
for your login.

hub runs `git clone` in the current directory, even inside another
repository. With `hub -C DIR clone`, hub runs the clone from `DIR`, as
`git -C DIR clone` does. hub prints nothing of its own when the clone works.
The output is git's.

## Exit status

`hub clone` exits with git's status and shows git's messages, for example for
a repository that does not exist. hub's own refusals exit with status 1 and
clone nothing. These are hub's messages:

```text
hub clone: could not determine your GitHub login for github.com (run: gh auth login -h github.com)
hub clone: this command needs the GitHub CLI, gh (https://cli.github.com)
hub clone: not a host name: -oProxyCommand=x
```

The first message means that gh has no login for the host. With a token
variable set, it means that `gh api ... user` returned no login. To fix it,
check the token, or run `gh auth login -h HOST`. hub needs gh for `REPO`
alone, and the second message appears when gh is not installed. The third
appears when `GH_HOST` holds something other than a host name.

## Differences from the original hub

The table compares `hub clone` with the original hub (mislav/hub 2.x).

| Original hub | This hub |
|---|---|
| `hub clone [-p] [OPTIONS] [USER/]REPOSITORY [DESTINATION]` | Same. The synopsis is now `hub clone [-p] [GIT-CLONE-OPTIONS...] [OWNER/]REPO [DIR]`. |
| `REPO` alone was your own repository. | Same. Your login comes from gh. |
| `OWNER/REPO.wiki` cloned the wiki. | Same. |
| Names with dots worked (`hook.js`, `.vim`). | Same. |
| URLs, `git@host:` addresses, local paths, repositories at that path and bundles went to git unchanged. | Same. |
| Every other git clone option passed through. | Same, in place. |
| `hub --noop clone` printed the git command and cloned nothing. | Same. |
| The protocol came from `HUB_PROTOCOL` or `hub.protocol` (`https`, `ssh` or `git`). With `git`, public repositories got `git://` URLs. | Not read. Use gh's `git_protocol`: `gh config set git_protocol ssh`. URLs are https or ssh only. |
| `-p` was deprecated. With the default https protocol it still gave https. | `-p` clones over ssh, for this command only. |
| The default host was github.com, changed with `GITHUB_HOST`. Enterprise hosts were listed in `hub.host`. | `GH_HOST`, else the only host gh is logged in to, else github.com. `GITHUB_HOST` still works. Use `gh auth login -h HOST` instead of `hub.host`. |
| hub asked the API for the repository (`GET /repos/OWNER/REPO`) and cloned its canonical name, which fixed case and followed renames. | No lookup: the URL uses the name as you typed it. |
| A missing repository printed `Error: repository mislav/dotfiles doesn't exist`. | git's own message, and git's exit status. |
| A missing wiki printed `Error: RTomayko/ronin doesn't have a wiki`. | No check. Git reports the failure. |
| A directory of the same name without `.git` did not stop the expansion. | Any existing path of that name goes to git unchanged. Clone by URL, or run the command in another directory. |
| `HOST/OWNER/REPO` worked as a short name. | It is a path for git. Use `GH_HOST=HOST hub clone OWNER/REPO`, or the URL. |
| A git alias such as `alias.c "clone --bare"` was expanded: `hub c rtomayko/ronn` turned the name into its URL and cloned it as a bare repository. | A git alias goes to git unchanged: `hub c rails/rails` runs `git c rails/rails`. Type `hub clone --bare rails/rails`. |
| hub kept its own login and token. | gh's login, or `GH_TOKEN`. |

## See also

- [hub fork](fork.md), [hub remote](remote.md) and [hub fetch](fetch.md): add
  a fork or another user's copy as a remote after you clone.
- [Repositories and URLs](../guide/repositories-and-urls.md): every short name
  and URL hub accepts.
- [Hosts and login](../guide/hosts-and-login.md): `GH_HOST`, GitHub Enterprise
  and `gh auth login`.
- [Configuration](../guide/configuration.md): `git_protocol` and the
  environment variables.
- [How hub works](../guide/how-hub-works.md): `--noop` and the git commands hub
  extends.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-clone(1)](https://hub.github.com/hub-clone.1.html)
- gh's manual: [gh repo clone](https://cli.github.com/manual/gh_repo_clone)
- git's manual: [git clone](https://git-scm.com/docs/git-clone)
- This hub's manual: [hub clone](https://brc-dd.github.io/hub/clone.html)
