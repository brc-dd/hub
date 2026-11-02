---
title: hub push
description: Push to several remotes at once.
kind: git command hub extends
original: https://hub.github.com/hub-push.1.html
---

# hub push

`hub push` is `git push` with one addition: it also accepts a comma-separated
list of remotes and runs `git push` once for each remote. A command line
without a list goes to `git push` unchanged, with git's own options and
output. Use it to keep the same branch on several remotes, such as a fork and
a staging server. The most common use is `hub push origin,staging`, which
pushes the current branch to both remotes under its own name:

```sh
hub push origin,staging
# => git push origin HEAD
# => git push staging HEAD
```

## Usage

```text
hub push REMOTE1,REMOTE2[,...] [GIT-PUSH-ARGS...]
```

`REMOTE1,REMOTE2[,...]` is the repository operand of `git push`, written as a
list of remote names with commas and no spaces. Every name must be a remote of
the repository. `GIT-PUSH-ARGS` are git push's own options and refspecs. They
can come before or after the list, and hub gives them to every push.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git push` is the same command. Each `# =>` line is what `hub --noop` prints:
the git command that hub runs. Without `--noop`, hub runs the pushes one after
the other.

Push one branch to three remotes:

```sh
hub push origin,staging,qa bert_timeout
# => git push origin bert_timeout
# => git push staging bert_timeout
# => git push qa bert_timeout
```

When refspecs follow the list, hub adds nothing and gives the refspecs to each
push.

Force-push `main` to the `release` branch of two remotes:

```sh
hub push -f origin,staging main:release
# => git push -f origin main:release
# => git push -f staging main:release
```

Options stay where you wrote them.

Push several refspecs to each remote:

```sh
hub push origin,staging main feature
# => git push origin main feature
# => git push staging main feature
```

Push the current branch and set its upstream:

```sh
hub push origin,staging --set-upstream
# => git push origin --set-upstream HEAD
# => git push staging --set-upstream HEAD
```

The list is still the only operand, so hub adds `HEAD` after the option. The
last push sets the upstream, so the branch tracks `staging`.

Push all tags:

```sh
hub push --tags origin,staging
# => git push --tags origin
# => git push --tags staging
```

`--tags` chooses the refs itself, so hub adds no `HEAD`.

Delete a branch on every remote:

```sh
hub push origin,staging --delete feature
# => git push origin --delete feature
# => git push staging --delete feature
```

Pass a push option to the server:

```sh
hub push -o ci.variable=a,b origin,staging
# => git push -o ci.variable=a\,b origin HEAD
# => git push -o ci.variable=a\,b staging HEAD
```

hub reads the word after `-o` as its value, so a comma in the value does not
start a list. `--noop` quotes each word so that you can paste the command line
back into a shell, which is why the comma shows as `\,`.

Put `--` before the list:

```sh
hub push -o ci.skip -- origin,staging
# => git push -o ci.skip -- origin HEAD
# => git push -o ci.skip -- staging HEAD
```

`--` and `--end-of-options` work as in git.

Push to one remote:

```sh
hub push origin
# => git push origin
```

Without a comma, the command line goes to `git push` unchanged, and git's
`push.default` decides what to push.

Push to a URL that contains a comma:

```sh
hub push https://github.com/OWNER/a,b.git feature
# => git push https://github.com/OWNER/a\,b.git feature
```

A URL, a path, or a remote whose name contains a comma is one destination.

Mistype a name in the list, here `stagng` for `staging`:

```sh
hub push origin,stagng
```

```text
hub push: not a remote: stagng
```

hub stops before it pushes anything.

## Options

`hub push` has no options of its own. Every option of `git push` stays as it
is and reaches each push in its place. hub reads these options only to find
the list, and some of them change what hub adds to a list push:

| Option | What it does |
|---|---|
| `--all`, `--branches`, `--mirror`, `--tags`, `-d`, `--delete` | Choose the refs, so hub adds no `HEAD`. hub also knows git's abbreviations, such as `--mirr` for `--mirror`. A later `--no-FLAG` (for example `--all --no-all`) cancels the option, and hub adds `HEAD` again. |
| `-o`, `--push-option`, `--repo`, `--receive-pack`, `--exec`, `--recurse-submodules` | Take the next word as the value. That word is never the list, so `--repo origin,staging` is plain `git push`. |
| `--`, `--end-of-options` | Treat every word after them as an operand. The list can follow them. |
| `-h`, `--help` | Print git's usage and git's manual. Use `hub help push` for hub's own summary of push. |

## How it works

hub reads the command line the way git does and applies these rules in order:

1. If hub cannot tell which word is the list, the command line goes to
   `git push` unchanged. That is the case with an abbreviated option that
   takes a value (such as `--recu no`), with grouped short options that have
   `o` after another letter (such as `-qo ci.skip`), with an option that takes
   a value as the last word, and with `-h` or `--help`.
2. If the command line has no operand, or the first operand has no comma or
   contains a colon, hub runs `git push` with the command line unchanged.
3. Outside a repository, git prints its own message.
4. If the first operand is a remote, an existing path (from the current
   directory or the top of the work tree), or a word git rewrites through
   `url.BASE.insteadOf`, it is one destination. hub runs plain `git push`.
   hub does not read `url.BASE.pushInsteadOf`. It splits such a word as a list
   of remotes. To push to that destination, add it as a remote or write the
   URL.
5. hub splits the list and checks every name before it pushes anything. An
   empty name, an option, or a name that is not a remote stops hub with a
   message (see [Exit status](#exit-status)).
6. hub runs `git push` once per remote, in the list's order. Each push gets the
   whole command line with that remote in the list's place.
7. hub adds `HEAD` only when the list is the only operand, no option chooses
   the refs, and the remote has no `remote.NAME.push` refspec and no
   `remote.NAME.mirror`. For other remotes, git decides what to push, as with
   `git push REMOTE`.

hub reads `remote.NAME.push` and `remote.NAME.mirror` from the repository's
own configuration, as git push does. A `GIT_CONFIG` file does not change them.
See [How hub works](../guide/how-hub-works.md).

## Exit status

`hub push` exits with git's status. With a list, it exits with 0 when every
push succeeds. Otherwise hub stops at the first push that fails and exits with
its status, and the remotes before it keep what they received. For example, if
the repository of a remote does not exist on the server, git exits with status
128.

hub's own refusals exit with status 1, before anything is pushed. These are
the messages:

```text
hub push: empty name in the list: origin,,staging
hub push: not a remote name: -f (write options outside the list)
hub push: not a remote: staging
```

A name with a space or a control character shows quoted, for example
`hub push: not a remote: x\ y`.

If you pass `--delete` and the list but no branch, hub adds no `HEAD`. The
first push then fails with git's message:

```text
fatal: --delete doesn't make sense without any refs
```

If `HEAD` is detached, the first push fails with git's message
`You must fully qualify the ref`.

## Differences from the original hub

| Original hub | This hub |
|---|---|
| The synopsis was `hub push REMOTE[,REMOTE2...] [REF]`. | `hub push REMOTE1,REMOTE2[,...] [GIT-PUSH-ARGS...]`. git push options can come before or after the list. |
| Had no options of its own. | Same. |
| Ran one `git push REMOTE REFS...` per remote, in order. | Same. |
| Gave several refs to each push. | Same. |
| Without a comma, ran plain git push. | Same. |
| Without a ref, the manual said `HEAD`, but the original hub pushed the current branch by name (`git push origin cool-feature`). | Without a ref, `HEAD`, which pushes the current branch under its own name even when a tag has the same name. |
| The manual showed `hub push origin` as `git push origin HEAD`. | `hub push origin` has no comma, so it is plain `git push origin`, and `push.default` decides. Write `hub push origin HEAD` to push the current branch. |
| Did not document what happened when one push failed. | hub stops at the first failure with its status. Earlier remotes keep what they got. |
| The manual did not describe a check of the names. | Every name must be a remote before anything is pushed. |
| The manual did not describe options or remote settings that choose the refs. | No `HEAD` with `--all`, `--branches`, `--mirror`, `--tags`, `--delete`, or for a remote with `remote.NAME.push` or `remote.NAME.mirror`. |
| The manual did not describe a destination with a comma. | A remote, path or URL with a comma, or a word git rewrites through `url.BASE.insteadOf`, is one destination. |

## See also

- [hub fetch](fetch.md): fetch from a comma-separated list of users.
- [hub sync](sync.md): bring local branches up to date with their remotes.
- [hub pull-request](pull-request.md): open a pull request for the pushed
  branch.
- [Project and remotes](../guide/project-and-remotes.md): which remote a branch
  pushes to.
- [How hub works](../guide/how-hub-works.md): `--noop`, the git commands hub
  extends, and exit status.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-push(1)](https://hub.github.com/hub-push.1.html)
- git's manual: [git push](https://git-scm.com/docs/git-push)
- This hub's manual: [hub push](https://brc-dd.github.io/hub/push.html)
