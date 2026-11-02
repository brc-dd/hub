---
title: hub create
description: Create a GitHub repository for this repository and add it as a remote.
kind: hub's own command
original: https://hub.github.com/hub-create.1.html
---

# hub create

`hub create` creates a repository on GitHub for the local repository you are
in, and adds it as the remote `origin`. hub runs `gh repo create` of the GitHub
CLI (gh), then `git remote add`. Use it for a project that starts on your
machine and needs a home on GitHub. The most common use is `hub create` in a
new repository, which creates a private repository of yours named after the
directory:

```sh
hub create
# => gh repo create github.com/LOGIN/dotfiles --private
# => git remote add -- origin https://github.com/LOGIN/dotfiles.git
```

## Usage

```text
hub create [-p | --public | --internal] [-d DESCRIPTION] [-h HOMEPAGE]
           [--remote-name NAME] [--push] [-o] [-c] [[[HOST/]OWNER/]NAME]
```

`NAME` is the name of the new repository. Without `NAME`, hub uses the name of
the project's repository on GitHub, if the project has one (see
[The project and its remotes](../guide/project-and-remotes.md)), else the name
of the top directory of the work tree. `OWNER/NAME` creates the repository
under the organization `OWNER`, not under your login. `HOST/OWNER/NAME`, or a
repository URL, also names the GitHub host. hub drops a `.git` suffix from
every form.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git create` is the same command. Each `# =>` line is what `hub --noop` prints:
the git or gh command that hub runs. The examples run in a repository whose
top directory is `dotfiles`, and `LOGIN` stands for your GitHub login.

Create a private repository named after the directory:

```sh
hub create
# => gh repo create github.com/LOGIN/dotfiles --private
# => git remote add -- origin https://github.com/LOGIN/dotfiles.git
```

Create a public repository, push the current branch to it and track it:

```sh
hub create --public --push dotfiles
# => gh repo create github.com/LOGIN/dotfiles --public
# => git remote add -- origin https://github.com/LOGIN/dotfiles.git
# => git push --set-upstream origin HEAD
```

Create the repository under an organization:

```sh
hub create rails/tools
# => gh repo create github.com/rails/tools --private
# => git remote add -- origin https://github.com/rails/tools.git
```

Give a description and a home page, and name the remote `gh` instead of
`origin`:

```sh
hub create -d 'My tools' -h https://example.com --remote-name gh
# => gh repo create github.com/LOGIN/dotfiles --private --description My\ tools --homepage https://example.com
# => git remote add -- gh https://github.com/LOGIN/dotfiles.git
```

Create a repository that every member of your enterprise can read:

```sh
hub create --internal myorg/kit
# => gh repo create github.com/myorg/kit --internal
# => git remote add -- origin https://github.com/myorg/kit.git
```

Copy the new repository's URL to the clipboard and open it in the browser:

```sh
hub create -c -o
# => gh repo create github.com/LOGIN/dotfiles --private
# => git remote add -- origin https://github.com/LOGIN/dotfiles.git
# => copy https://github.com/LOGIN/dotfiles
# => open https://github.com/LOGIN/dotfiles
```

Under `--noop`, `copy` and `open` stand for the clipboard tool and the browser,
and hub runs neither. See
[Browser and clipboard](../guide/browser-and-clipboard.md).

Name the repository with a URL or with `HOST/OWNER/NAME`. These command lines
all create `myorg/site` on github.com:

```sh
hub create github.com/myorg/site
hub create https://github.com/myorg/site.git
hub create git@github.com:myorg/site.git
# => gh repo create github.com/myorg/site --private
# => git remote add -- origin https://github.com/myorg/site.git
```

Put the owner in front of a name that starts with a hyphen, such as `-app`.
hub reads a bare `-app` as an option:

```sh
hub create octo/-app
# => gh repo create github.com/octo/-app --private
# => git remote add -- origin https://github.com/octo/-app.git
```

Create the repository on a GitHub Enterprise host. hub asks gh for your login
on that host:

```sh
GH_HOST=ghe.example.com hub create gadget
# => gh repo create ghe.example.com/LOGIN/gadget --private
# => git remote add -- origin https://ghe.example.com/LOGIN/gadget.git
```

Give the remote an ssh URL by setting gh's `git_protocol` to `ssh` first:

```sh
gh config set git_protocol ssh
hub create
# => gh repo create github.com/LOGIN/dotfiles --private
# => git remote add -- origin git@github.com:LOGIN/dotfiles.git
```

When `origin` already exists, hub refuses before it asks gh anything:

```sh
hub create
```

```text
hub create: remote already exists: origin (name another with --remote-name NAME)
```

## Options

| Option | What it does |
|---|---|
| `-p`, `--private` | Make the repository private. Default: private. |
| `--public` | Make the repository public. |
| `--internal` | Make the repository readable by every member of the enterprise. |
| `-d`, `--description DESCRIPTION` | Set the repository's description. |
| `-h`, `--homepage HOMEPAGE` | Set the repository's home page URL. |
| `--remote-name NAME` | Name the remote `NAME` instead of `origin`. |
| `--push` | Push the current branch to the new repository and track it. |
| `-o`, `--browse` | Open `https://HOST/OWNER/NAME` in the browser. |
| `-c`, `--copy` | Copy that URL to the clipboard. |

These are all the options. Any other option is a usage error, gh's own
`--clone`, `--source` and `--template` included, and `--help` prints the
manual. When the visibility comes more than once, the last one counts:
`hub create --public -p` creates a private repository. Short options combine
(`-pc`, `-dabc`), and `--description`, `--homepage` and `--remote-name` also
take `--option=VALUE`.

## How it works

hub applies these rules in order:

1. hub checks that gh is on `PATH` and that you are inside a work tree. Any
   directory of the work tree works, and so do a linked work tree
   (`git worktree add`) and a work tree with a separate git directory. A bare
   repository or its `.git` directory gives `not inside a work tree`.
2. hub picks the host: `GH_HOST`, else the one host gh is logged in to, else
   github.com. A `HOST/OWNER/NAME` or a URL names the host itself. See
   [Hosts and login](../guide/hosts-and-login.md).
3. hub picks the name: `NAME` if you give it, else the name of the project
   (see [The project and its remotes](../guide/project-and-remotes.md)), else
   the top directory's name. In a directory name, each character that a
   repository name cannot have becomes `-`, so `my dot+files` gives
   `my-dot-files`.
4. hub checks the name, the remote name and, with `--push`, the current branch.
   No remote of that name can exist yet, in any letter case. For example, a
   remote named `Origin` blocks `origin`. With `--push`, `HEAD` must be on a
   branch that has a commit. A failed check stops hub before gh runs.
5. Without `OWNER`, hub asks gh for your login on the host.
6. hub runs `gh repo create HOST/OWNER/NAME` with the visibility, the
   description and the home page.
7. hub runs `git remote add` with the repository's clone URL. The URL is ssh
   when gh's `git_protocol` for the host is `ssh`, else https.
8. With `--push`, hub runs `git push --set-upstream REMOTE HEAD`.
9. With `-c`, hub copies the web URL. With `-o`, it opens the web URL. A missing
   clipboard tool does not stop the browser. See
   [Browser and clipboard](../guide/browser-and-clipboard.md).

When a step fails, hub stops there. For example, gh fails when the repository
name already exists. gh prints its message, and hub adds no remote, pushes
nothing and opens nothing.

## Exit status

`hub create` exits with git's or gh's status when one of them fails, for
example 128 when the push fails. Otherwise the status is that of the browser
or the clipboard tool. It is 0 when they succeed, and also when you give
neither `-o` nor `-c`. hub's own refusals exit with status 1, and so does a
directory outside a repository, after git's message.

hub prints these messages when it stops before gh creates anything. In them,
`my\ repo` is the name you gave, quoted, and `trunk` is the current branch:

| Message | What to do |
|---|---|
| `hub create: remote already exists: origin (name another with --remote-name NAME)` | Name another remote with `--remote-name`. |
| `hub create: not a repository: my\ repo (use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)` | Give the name in one of those forms. |
| `hub create: not a remote name: -x` | Give `--remote-name` a valid remote name. |
| `hub create: not on a branch (--push pushes the current branch)` | Check out a branch, or leave out `--push`. |
| `hub create: trunk has no commits to push (commit first, or leave out --push)` | Commit first, or leave out `--push`. |
| `hub create: could not determine your GitHub login for github.com (run: gh auth login -h github.com)` | Run `gh auth login -h github.com`. |
| `hub create: this command needs the GitHub CLI, gh (https://cli.github.com)` | Install gh. |

## Differences from the original hub

| Original hub | This hub |
|---|---|
| Created a public repository unless you gave `-p`. It had no `--public` or `--internal`. | Creates a private repository unless you give `--public` or `--internal`. `-p` still means private. |
| Took `[ORGANIZATION/]NAME`. | Takes `NAME`, `OWNER/NAME`, `HOST/OWNER/NAME` or a repository URL. |
| Created the repository with its own API call. | Runs `gh repo create`. Log in with `gh auth login`. |
| Used github.com unless `GITHUB_HOST` named another host. | Uses `GH_HOST`, else the one host gh is logged in to, else github.com. `GITHUB_HOST` still works without `GH_HOST`. |
| Added the remote with `git remote add -f`, which fetched it. | Runs `git remote add` without `-f`. Run `git fetch` yourself. |
| Took the remote's protocol from `hub.protocol` or `HUB_PROTOCOL`. | Not read. Use `gh config set git_protocol ssh`. |
| Reused an existing repository (`Existing repository detected`), but refused a public one with `-p`. | gh fails on an existing repository, and hub adds no remote. Add it with `git remote add`. |
| Kept an existing `origin` and succeeded, with a warning when it pointed to another repository. | Refuses an existing remote before it creates anything. Use `--remote-name`. |
| Named the remote's URL after the name GitHub returned, following redirects. | Uses the name you asked for. |
| Did not push. You ran `git push -u origin HEAD` afterwards. | Same by default. `--push` pushes the current branch and tracks it. |
| Printed the new repository's web URL. `-c` copied it instead. | Prints no URL of its own. `-c` copies it, and `-o` opens it. |
| Turned spaces in the directory name into dashes. | Same, and every other character a name cannot have. |
| Took `-o`, `--remote-name`, `-d` and `-h`. | Same. |
| Failed in a bare repository with `unable to determine git working directory`, and outside a repository with `'create' must be run from inside a git repository`. | Fails in a bare repository with `not inside a work tree`, and outside a repository with git's `fatal: not a git repository` message. |
| Gave `invalid hostname: "{}"` for an invalid host. | Gives `not a host name: VALUE` for an invalid `GH_HOST`. |
| Logged the API requests under `HUB_VERBOSE`. | Not read. Use `hub --noop` to see the command lines hub runs. |
| Skipped the API request under `--noop`. | `--noop` prints the `gh` and `git` command lines instead of running them. |

hub's `-p` and `-c` differ from gh's: in `gh repo create`, `-p` is
`--template` and `-c` is `--clone`. hub does not use gh's `--source`, because
gh refuses a linked work tree and a separate git directory.

## See also

- [hub fork](fork.md): fork an existing repository.
- [hub push](push.md) and [hub pull-request](pull-request.md): the next steps.
- [hub init](init.md): not supported, and how to start a new repository
  instead.
- [hub delete](delete.md): delete a repository.
- [The project and its remotes](../guide/project-and-remotes.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [Browser and clipboard](../guide/browser-and-clipboard.md)
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-create(1)](https://hub.github.com/hub-create.1.html)
- gh's manual: [gh repo create](https://cli.github.com/manual/gh_repo_create)
