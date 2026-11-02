---
title: hub fetch
description: Fetch from GitHub users' copies of the project, adding their remotes.
kind: git command hub extends
original: https://hub.github.com/hub-fetch.1.html
---

# hub fetch

`hub fetch` is `git fetch` with one addition: it also accepts a GitHub login
where git expects a remote, and adds that user's copy of the project as a
remote when no remote has that name. Every other command line goes to
`git fetch` unchanged. Use it to look at a contributor's branches without
typing their repository URL. The most common use is `hub fetch USER`, which
adds the remote `USER` and fetches it.

```sh
hub fetch alice
# => git remote add alice https://github.com/alice/dotfiles.git
# => git fetch alice
```

## Usage

```text
hub fetch [GIT-FETCH-OPTIONS...] USER [REFSPEC...]
hub fetch [GIT-FETCH-OPTIONS...] USER,USER... [GIT-FETCH-ARGS...]
```

`USER` is a GitHub login. hub fetches the repository `USER/REPO`, where `REPO`
is the name of [the project](../guide/project-and-remotes.md), on the project's
host. `USER,USER...` is a comma-separated list of logins, remotes and remote
groups, and each name in the list is a member. Every other word is git's:
options, refspecs, and the operands that follow a list.

## Examples

The examples write `hub`. With the alias from
[Make git run hub](../getting-started/alias.md), `git fetch` is the same
command. Each `# =>` line is what `hub --noop` prints: the git command that hub
runs. Each `# runs:` line is a lookup that hub runs even under `--noop`. The
examples run in a clone of mislav/dotfiles, and `alice` and `bob` have copies
of that repository on GitHub.

Fetch a user's copy of the project:

```sh
hub fetch alice
# runs: gh repo view github.com/alice/dotfiles --json name
# => git remote add alice https://github.com/alice/dotfiles.git
# => git fetch alice
```

hub checks that the copy exists, adds the remote `alice`, then fetches it.

Fetch from several users at once:

```sh
hub fetch --prune alice,origin
# => git remote add alice https://github.com/alice/dotfiles.git
# => git fetch --multiple --prune alice origin
```

hub adds each missing remote, then fetches all members with `--multiple`. A
member that is already a remote stays as it is.

Fetch one branch of a user's copy into a local branch:

```sh
hub fetch --no-tags alice topic:refs/heads/alice-topic --quiet
# => git remote add alice https://github.com/alice/dotfiles.git
# => git fetch --no-tags alice topic:refs/heads/alice-topic --quiet
```

The refspec and the options stay where you wrote them.

Set up a remote without downloading anything:

```sh
hub fetch --dry-run alice
# => git remote add alice https://github.com/alice/dotfiles.git
# => git fetch --dry-run alice
```

With `--dry-run`, hub still adds the remote, and git fetches nothing.

Write the list after `--`, with other operands after it:

```sh
hub fetch --prune -- alice,origin bob
# => git remote add alice https://github.com/alice/dotfiles.git
# => git fetch --multiple --prune -- alice origin bob
```

hub puts `--multiple` first and the members where the list was. Words after the
list go to git as written, so here `bob` must already be a remote. A list after
another operand, as in `hub fetch origin alice,bob`, is plain `git fetch`.

Check what hub would do without changing anything:

```sh
hub --noop fetch alice
```

```text
git remote add alice https://github.com/alice/dotfiles.git
git fetch alice
```

`hub --noop` prints the commands and does not run them. hub still asks gh
whether `alice/dotfiles` exists.

Fetch a user's copy over ssh, when gh's `git_protocol` for the host is `ssh`
(see [Hosts and login](../guide/hosts-and-login.md)):

```sh
hub fetch alice
# => git remote add alice git@github.com:alice/dotfiles.git
# => git fetch alice
```

Fetch a remote, a URL, or every remote:

```sh
hub fetch origin
# => git fetch origin
hub fetch https://github.com/rails/rails.git main
# => git fetch https://github.com/rails/rails.git main
hub fetch --all
# => git fetch --all
```

These command lines are plain `git fetch`. hub asks gh nothing. A command line
with `--all`, `--multiple` or `--no-multiple` is plain `git fetch` too.

Read git's manual:

```sh
hub fetch alice --help
# => git fetch alice --help
```

`--help`, `--help-all` and `-h` are git's.

Fetch a user who has no copy of the project:

```sh
hub fetch carol
```

```text
hub fetch: carol is not a remote, and github.com/carol/dotfiles does not exist
```

hub stops before it adds any remote.

Fetch a login that differs from a remote's name only in upper and lower case:

```sh
hub fetch Alice
```

```text
hub fetch: Alice is not a remote, but alice is (use alice)
```

Use the remote's spelling.

## Options

`hub fetch` has no options of its own. Every option of `git fetch` stays as it
is and reaches git in its place. hub reads these options only to find the
operands:

| Option | What it does |
|---|---|
| `--depth`, `-j`, `--jobs`, `-o`, `--server-option` and the other options that take a value | Take the next word as the option's value, never as the `USER` operand. `hub fetch --depth 5 -j 3 alice` fetches `alice`. |
| `--multiple`, `--no-multiple`, `--all` | Make the whole command line plain `git fetch`. hub adds no remote. Abbreviations such as `--mul` and short clusters with `m` such as `-qm` count too. |
| `--submodule-prefix`, `--recurse-submodules-default` | Make the whole command line plain `git fetch`. `--recurse-submodules=VALUE` is an ordinary option. |
| `--dry-run` | Add the missing remotes, then let git fetch nothing. |
| `-h`, `--help`, `--help-all` | Print git's usage or manual. hub adds no remote. |

For hub's manual, run `hub help fetch`.

## How it works

hub applies these rules in order:

1. hub reads the first operand, the first word that is not an option or an
   option's value.
2. If the command line has `-h`, `--help` or `--help-all`, it is plain
   `git fetch`. If hub cannot tell which word is the operand, the command line
   is plain `git fetch` too. Examples are `--dep 1 alice` (an abbreviated
   option that takes a value), `-qj 2 alice`, and a value-taking option as the
   last word.
3. If there is no operand, the command line is plain `git fetch`.
4. If the command line has `--multiple`, `--no-multiple`, `--all`,
   `--submodule-prefix` or `--recurse-submodules-default`, it is plain
   `git fetch`.
5. Outside a repository, the command line is plain `git fetch`.
6. If the operand is a remote, a remote group, a URL, a `host:path` word, a
   path that exists, a local repository, or a word that git rewrites through
   `url.BASE.insteadOf`, the command line is plain `git fetch`.
7. If the operand has commas, hub splits it into members. hub refuses a list
   with an empty name or an option.
8. A member that is a remote or a remote group stays as it is. If another
   member is not a GitHub login, or is a local repository, the command line is
   plain `git fetch`. Examples are `hub fetch not.a.login` and
   `hub fetch alice,not.a.login`.
9. hub refuses a login or group that matches a remote or a remote group except
   for case. A remote group counts only by its lowercase name. hub also
   refuses one user written in two cases. GitHub logins ignore case, and git's
   remote names do not, so these refusals keep you from getting two remotes
   for one user.
10. hub takes the host and the repository name from
    [the project](../guide/project-and-remotes.md), which `GH_REPO` can set.
    Without a GitHub remote, hub uses
    [the default host](../guide/hosts-and-login.md) and the name of the top
    directory, with each character other than `A-Za-z0-9_.-` replaced by `-`.
    A clone in `my project` fetches `alice/my-project`.
11. hub runs `gh repo view HOST/USER/REPO --json name` for every missing user.
    If a copy does not exist, hub stops before it adds any remote. If gh fails
    for another reason, such as bad credentials, hub prints gh's message and
    stops.
12. hub adds each missing remote with `git remote add USER URL`. The URL is
    https, or ssh when gh's `git_protocol` for the host is `ssh` (see
    [Hosts and login](../guide/hosts-and-login.md)). A user named twice, as in
    `alice,alice`, gets one remote.
13. Last, hub runs `git fetch` with your command line. For a list, hub runs
    `git fetch --multiple` with the members in the list's place.

Refspecs after a list are git's. `git fetch --multiple` reads them as remotes,
so `hub fetch alice,bob topic` adds both remotes and then fails with git's
`no such remote or remote group: topic`.

## Exit status

`hub fetch` exits with git's status. A remote that hub added stays when git
fails: `hub fetch alice no-such-branch` exits 128 with git's
`couldn't find remote ref no-such-branch`, and the remote `alice` remains.
hub's own refusals exit with status 1, and so do gh's failures, before hub
adds any remote. hub needs gh. Without it, hub prints
`hub fetch: this command needs the GitHub CLI, gh (https://cli.github.com)`.

| Message | What to do |
|---|---|
| `hub fetch: empty name in the list: alice,,bob` | Remove the empty name from the list. |
| `hub fetch: not a remote name: --prune (write options outside the list)` | Write the option before or after the list. |
| `hub fetch: Alice is not a remote, but alice is (use alice)` | Use the remote's spelling. |
| `hub fetch: Friends is not a remote group, but friends is (use friends)` | Use the remote group's lowercase name. |
| `hub fetch: alice is listed twice as Alice (use one spelling)` | Write the user once, in one spelling. |
| `hub fetch: carol is not a remote, and github.com/carol/dotfiles does not exist` | Check the login. The user has no copy of the project. |

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub fetch USER` added a remote for the user's copy, then ran `git fetch USER`. | Same. |
| `hub fetch USER1,USER2` added the missing remotes, then ran one `git fetch --multiple`. | Same. Members that are remotes or remote groups stay as they are. |
| The original hub fetched existing remotes, remote groups and URLs with refspecs unchanged. | Same. A `host:path` word, and a word git rewrites through `url.BASE.insteadOf`, are plain `git fetch` too. |
| A local git bundle named like the user won, and no remote was added. | Same, for any path that exists or that git reads as a local repository. |
| `hub fetch --multiple USER1 USER2` added remotes for names that looked like users and existed on GitHub, then ran the command line unchanged. | Plain `git fetch`, so git refuses a name that is not a remote. Write `hub fetch USER1,USER2`. The original manual's `hub fetch --multiple jingweno mislav` is now `hub fetch jingweno,mislav`. |
| If the user had no copy, the original hub added no remote and ran `git fetch USER` unchanged. | hub refuses with `USER is not a remote, and HOST/USER/REPO does not exist` and adds no remote. |
| The URL was https, or `git://` and ssh URLs with `HUB_PROTOCOL=git`. | https, or ssh when gh's `git_protocol` is `ssh`. `HUB_PROTOCOL` is not read. |
| The repository name came from the current repository. | Same, and without a GitHub remote, from the top directory's name. |

This hub also refuses a login that matches a remote or a remote group except
for upper and lower case, and a list that names one user in two cases. Use one
spelling. gh checks that each copy exists, so gh must be installed and logged
in.

## See also

- [hub push](push.md): push to a comma-separated list of remotes.
- [hub remote](remote.md): add a user's copy without fetching it.
- [hub fork](fork.md): make your own copy of the project.
- [hub sync](sync.md): update your local branches from their remotes.
- [The project and its remotes](../guide/project-and-remotes.md)
- [Repositories and URLs](../guide/repositories-and-urls.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [How hub works](../guide/how-hub-works.md)
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual: [hub-fetch(1)](https://hub.github.com/hub-fetch.1.html)
- git's manual: [git fetch](https://git-scm.com/docs/git-fetch)
