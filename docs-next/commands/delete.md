---
title: hub delete
description: Delete a repository on GitHub.
kind: hub's own command
original: https://hub.github.com/hub-delete.1.html
---

# hub delete

`hub delete` deletes a repository on GitHub. hub expands the name to
`HOST/OWNER/NAME` and runs `gh repo delete` from the GitHub CLI (gh). Use it to
remove a repository you own or one of your organization's. The most common use
is `hub delete NAME`, which deletes your repository NAME after gh asks you to
confirm.

```sh
hub delete dotfiles
# => gh repo delete github.com/LOGIN/dotfiles
```

> [!CAUTION]
> Run `hub delete` only on a repository you want to lose. GitHub deletes the
> repository and its issues. You cannot restore them with hub.

## Usage

```text
hub delete [-y] [[HOST/]OWNER/]NAME
```

`NAME` alone is your repository on the default host: `GH_HOST`, else the one
host gh is logged in to, else github.com. `OWNER/NAME` is a repository of that
user or organization on the default host. `HOST/OWNER/NAME` names the host too,
for example a GitHub Enterprise host. HOST must contain a dot or be a host gh is
logged in to. A repository URL (`https://`, `ssh://` or `git@HOST:OWNER/NAME`)
works in place of any of these when its host is github.com, `GH_HOST` or a host
gh is logged in to. See [Hosts and login](../guide/hosts-and-login.md) and
[Repositories and URLs](../guide/repositories-and-urls.md).

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md), `git
delete` is the same command. Each `# =>` line is what `hub --noop` prints: the
gh command that hub runs. `LOGIN` stands for your GitHub login.

Delete one of your repositories:

```sh
hub delete dotfiles
# => gh repo delete github.com/LOGIN/dotfiles
```

gh asks you to type the repository name before it deletes anything.

Delete without the confirmation prompt:

```sh
hub delete -y dotfiles
# => gh repo delete github.com/LOGIN/dotfiles --yes
hub delete dotfiles --yes
# => gh repo delete github.com/LOGIN/dotfiles --yes
```

`-y` passes `--yes` to gh. The option can come before or after the name.

Delete an organization's repository:

```sh
hub delete octo-org/old-site
# => gh repo delete github.com/octo-org/old-site
```

With an owner, hub does not look up your login.

Delete a repository by its clone URL or its web URL:

```sh
hub delete https://github.com/octo/site.git
# => gh repo delete github.com/octo/site
hub delete git@github.com:octo/site.git
# => gh repo delete github.com/octo/site
hub delete https://GitHub.com/octo/site
# => gh repo delete github.com/octo/site
hub delete dotfiles.git --yes
# => gh repo delete github.com/LOGIN/dotfiles --yes
```

hub drops a trailing `.git` and lowercases the host.

See what hub would run, and run nothing:

```sh
hub --noop delete -y octo/site
# => gh repo delete github.com/octo/site --yes
hub --noop delete dotfiles
# => gh repo delete github.com/LOGIN/dotfiles
```

`hub --noop` prints the command and does not run it. Read-only lookups still
run, so for a bare `NAME` hub still asks gh for your login.

Delete a repository on GitHub Enterprise:

```sh
GH_HOST=ghe.example.com hub delete -y tools
# => gh repo delete ghe.example.com/LOGIN/tools --yes
hub delete ghe.example.com/octo/tools
# => gh repo delete ghe.example.com/octo/tools
```

`GH_HOST` makes the host the default, and a bare `NAME` belongs to your login
on that host. To name the host once, put it in the operand.

Name a repository that starts with a dash:

```sh
hub delete -- octo/-y
# => gh repo delete github.com/octo/-y
```

`--` stops hub from reading the name as an option.

Leave out the repository, and hub refuses:

```sh
hub delete
```

```text
hub delete: name the repository to delete
Usage: hub delete [-y] [[HOST/]OWNER/]NAME
```

hub prints a message, exits with status 1 and runs nothing. A usage error also
prints the `Usage:` line. The same holds for two operands, an unknown option
and an operand that is not a repository:

```sh
hub delete -y octo/a octo/b
hub delete --force octo/site
hub delete octo/site/tree
```

```text
hub delete: unexpected argument: octo/b
Usage: hub delete [-y] [[HOST/]OWNER/]NAME
hub delete: unknown option: --force
Usage: hub delete [-y] [[HOST/]OWNER/]NAME
hub delete: not a repository: octo/site/tree (use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)
```

## Options

| Option | What it does |
|---|---|
| `-y`, `--yes` | Delete without asking for confirmation (gh's `--yes`). Default: gh asks you to type the repository name. |
| `-h`, `--help` | Print the manual of `hub delete` and delete nothing. |

These are all the options. Any other option, such as `-f`, `--confirm` or
`--yes=1`, is a usage error, and `-h` or `--help` prints the manual. hub
splits bundled short options, so `-yf` is read as `-y -f` and refused as
`unknown option: -f`. `--` ends the options.

## How it works

hub applies these rules in order:

1. hub checks the command line. It needs exactly one operand and accepts no
   option other than `-y` (`--yes`).
2. hub needs gh. Without it, hub prints
   `hub delete: this command needs the GitHub CLI, gh (https://cli.github.com)`.
3. hub reads the default host. This is `GH_HOST` if it is set. If gh is logged
   in to exactly one host, it is that host. Otherwise it is github.com. This
   step fails only when `GH_HOST` is not a host name. See
   [Hosts and login](../guide/hosts-and-login.md).
4. hub reads the operand. A word with a `/` is `OWNER/NAME`, `HOST/OWNER/NAME`
   or a URL, read as
   [Repositories and URLs](../guide/repositories-and-urls.md) describes. A word
   without a `/` is a bare `NAME`. hub refuses anything else and does not run
   gh.
5. For a bare `NAME`, hub asks gh for your login on the host with
   `gh config get user -h HOST`. If `GH_TOKEN`, `GITHUB_TOKEN`,
   `GH_ENTERPRISE_TOKEN` or `GITHUB_ENTERPRISE_TOKEN` is set, it asks
   `gh api --hostname HOST user --jq .login` instead. Without an answer, hub
   stops.
6. hub runs `gh repo delete HOST/OWNER/NAME`, with `--yes` when you gave `-y`.

hub never chooses the current repository. A bare `NAME` is always your
repository. This holds inside a clone of someone else's repository and when
`GH_REPO` names another repository. `hub delete` also works outside a git
repository.

To delete a repository, gh must have the `delete_repo` scope. Grant the scope
once with `gh auth refresh -s delete_repo`.

## Exit status

`hub delete` exits with gh's status. When gh refuses, its message reaches you
unchanged, for example `HTTP 403: Must have admin rights to Repository.` with
status 1. hub's own refusals exit with status 1 before gh runs:

| Message | What to do |
|---|---|
| `hub delete: name the repository to delete` | Name one repository. The usage follows. |
| `hub delete: unexpected argument: octo/b` | Delete one repository per command line. The usage follows. |
| `hub delete: unknown option: --force` | Use `-y` (`--yes`) or no option. The usage follows. |
| `hub delete: not a repository: octo/site/tree (use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)` | Use one of the forms the message lists. |
| `hub delete: this command needs the GitHub CLI, gh (https://cli.github.com)` | Install gh. |
| `hub delete: not a host name: a\ b` | Set `GH_HOST` to a host name. |
| `hub delete: could not determine your GitHub login for github.com (run: gh auth login -h github.com)` | Run the `gh auth login` command the message names, or give `OWNER/NAME`. |

## Differences from the original hub

The command line you typed for the original hub (mislav/hub 2.x) still works:
`hub delete NAME`, `hub delete ORGANIZATION/NAME` and `-y`/`--yes` are the
same.

| Original hub | This hub |
|---|---|
| `hub delete [-y] [ORGANIZATION/]NAME`. | `hub delete [-y] [[HOST/]OWNER/]NAME`. A host and repository URLs are accepted too. |
| Deleted the repository with hub's own GitHub token. | Runs `gh repo delete HOST/OWNER/NAME [--yes]`. gh must be installed and logged in. |
| Asked `Really delete repository 'OWNER/NAME' (yes/N)?`. Only the word `yes` went on, and any other answer printed `Please type 'yes' for confirmation.` | gh asks you to type the repository name. `-y` skips the question, as before. |
| Printed `Deleted repository 'OWNER/NAME'.` | Prints what gh prints. |
| On HTTP 403, told you to edit the token at `https://github.com/settings/tokens` and enable the `delete_repo` scope. | Prints gh's error. Grant the scope with `gh auth refresh -s delete_repo`. |
| No argument printed the usage and exited 1, also inside a repository. | Same. hub prints `name the repository to delete`, then the usage, and exits 1. |
| A bare `NAME` was your own account's. | Same. It is your login on the default host. |
| `--noop` printed `Would delete repository 'OWNER/NAME'.` | `--noop` prints the gh command, for example `gh repo delete github.com/octo/site --yes`. |
| `GITHUB_HOST` set the default host instead of github.com. | `GH_HOST` chooses it. `GITHUB_HOST` still works: hub passes it to gh as `GH_HOST` when `GH_HOST` is not set. |

## See also

- [hub create](create.md): make a repository.
- [hub fork](fork.md): make a fork of a repository.
- [Hosts and login](../guide/hosts-and-login.md): the default host, your
  login, tokens.
- [Repositories and URLs](../guide/repositories-and-urls.md): the forms
  `OWNER/NAME`, `HOST/OWNER/NAME` and URLs.
- [How hub works](../guide/how-hub-works.md): `--noop` and exit statuses.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-delete(1)](https://hub.github.com/hub-delete.1.html)
- gh's manual: [gh repo delete](https://cli.github.com/manual/gh_repo_delete)
- This hub's manual: [hub delete](https://brc-dd.github.io/hub/delete.html)
