---
title: Not supported
description: What hub leaves out of the original hub, and what to do instead.
---

# Not supported

This page is for people who used the original hub (mislav/hub 2.x) and want to
know what to type in place of a form that hub no longer takes. Each section
says what the original did and what to type instead. hub keeps the commands
people typed, not every flag or output format. The GitHub CLI (gh) does the
GitHub work, and hub has no token or settings file of its own. With
[the alias](../getting-started/alias.md), `git` runs the same commands.

## `hub init -g`

The original `hub init -g` ran `git init` and added the remote `origin` for
`LOGIN/DIR`, where `LOGIN` is your GitHub login and `DIR` is the directory
name. It did not create the repository on GitHub. hub has no `init`. Run
`hub create`, which creates the repository and adds the remote. See
[hub init](../commands/init.md).

```sh
git init widgets && cd widgets
hub --noop create
# => gh repo create github.com/LOGIN/widgets --private
# => git remote add -- origin https://github.com/LOGIN/widgets.git
```

## `hub submodule add OWNER/REPO`

The original `hub submodule add mojombo/grit vendor/grit` added the submodule
from `https://github.com/mojombo/grit.git`. hub has no `submodule`, so it hands
the line to git unchanged. Write the full URL. See
[hub submodule](../commands/submodule.md).

```sh
git submodule add https://github.com/OWNER/REPO.git vendor/REPO
```

## `OWNER/REPO` alone in `remote add`

The original `hub remote add mislav/dotfilez.js` added the remote `mislav` for
`https://github.com/mislav/dotfilez.js.git`. hub hands a lone `OWNER/REPO` to
git unchanged. Name the remote before `OWNER/REPO`. `hub remote add USER`
still adds the remote `USER` for `USER/REPO`, where `REPO` is the current
repository's name.

```sh
hub --noop remote add USER USER/REPO   # => git remote add USER https://github.com/USER/REPO.git
hub --noop remote add USER             # => git remote add USER https://github.com/USER/REPO.git
```

## Gist URLs in `am` and `apply`

The original `hub am https://gist.github.com/8da7fb575debd88c54cf` applied the
gist's file. hub downloads pull request, commit and comparison URLs only, and
hands a gist URL to git unchanged. Clone the gist, then apply its file.

```sh
gh gist clone 8da7fb575debd88c54cf fix
git am fix/FILE.patch
```

`gh gist clone` clones the gist into the directory `fix`, and `FILE` is the
name of the gist's file.

## `USER@SHA` in `cherry-pick`

The original `hub cherry-pick mislav@a319d88` fetched the commit from the
remote `mislav` and cherry-picked it. hub hands `USER@SHA` to git unchanged.
Use the commit's URL, or, if you have the remote, fetch it and cherry-pick the
commit with git. See [hub cherry-pick](../commands/cherry-pick.md).

```sh
hub cherry-pick https://github.com/OWNER/REPO/commit/SHA
# => gh api --hostname github.com repos/OWNER/REPO/commits/SHA --jq .sha
# => git fetch --quiet --no-tags --refmap= --no-write-fetch-head -- https://github.com/OWNER/REPO.git FULL-SHA
# => git cherry-pick FULL-SHA

git fetch USER && git cherry-pick SHA
```

## `-i ISSUE` in `pull-request`

The original `hub pull-request -i 123` turned issue 123 into a pull request.
hub stops with `-i is not supported`. Open a new pull request and write
`Closes #123` in its body. The first `-m` sets the title and the second `-m`
sets the body.

```sh
hub --noop pull-request -m 'Fix the login bug' -m 'Closes #123'
# => gh pr create ... --title Fix\ the\ login\ bug --body Closes\ #123
```

## Milestones by number

The original `hub pull-request -M 3` accepted a milestone number. hub hands the
value to `gh pr create --milestone`, which reads it as a name. Pass the
milestone's name.

```sh
hub --noop pull-request -M v2.0 -m 'Fix the login bug'   # => gh pr create ... --milestone v2.0
```

## `-f FORMAT` placeholders

The original `hub pr list -f '%I %t%n'` printed each pull request through
placeholders such as `%I`, `%t` and `%U`, as did `issue`, `release` and
`ci-status`. Select fields with `--json` and shape them with `--jq` or
`--template`. In place of `hub ci-status -f`, run `gh pr checks` with the same
flags.

```sh
hub pr list --json number,title --jq '.[] | "\(.number) \(.title)"'
gh pr checks 12 --json state,name,link --jq '.[] | "\(.state): \(.name) (\(.link))"'
```

## The `-c` clipboard flag outside four commands

The original `hub gist create --copy build.log` put the gist's URL on the
clipboard. hub copies only in `browse`, `compare`, `create` and
`pull-request`. Elsewhere, pipe the URL that gh prints to a clipboard tool,
such as `pbcopy`. See
[Browser and clipboard](../guide/browser-and-clipboard.md).

```sh
hub gist create build.log | pbcopy
```

## `pr show -c`

The original `hub pr show -c 12` copied the URL. hub runs `gh pr view -c 12`,
and gh's `-c` is `--comments`, so gh prints the comments. To copy the URL,
print it with `--json url --jq .url` and pipe it to `pbcopy`.

```sh
hub pr show 12 --json url --jq .url | pbcopy   # => gh pr view 12 --json url --jq .url
```

## `--color`

The original `hub sync --color` and `hub ci-status --color` colored output
outside a terminal. hub stops with `unknown option: --color`. Remove the flag.
For a colored view of checks, run `gh pr checks`, which colors its output in a
terminal.

```sh
gh pr checks 12
```

## Wiki pages in `browse` and `compare`

In a wiki's clone, the original `hub browse` opened the wiki and `hub compare`
opened `/wiki/_compare/RANGE`. hub treats a wiki's clone like any repository:
there, `hub browse` opens `https://github.com/OWNER/REPO.wiki`. To open a wiki
page, run `hub browse` in the main repository's clone with the page's path
after `--`.

```sh
hub browse -- wiki/_history   # => open https://github.com/OWNER/REPO/wiki/_history
```

## Branches on renamed forks in `compare`

The original `hub compare` wrote a branch on a fork as `FORKOWNER:BRANCH`, and
hub writes it the same way. If the fork has a different name from its parent,
GitHub needs `FORKOWNER:FORK:BRANCH`, which `hub compare` does not write. Open
that comparison with `hub browse` and a path.

```sh
hub browse -- compare/main...FORKOWNER:FORK:BRANCH
# => open https://github.com/OWNER/REPO/compare/main...FORKOWNER:FORK:BRANCH
```

## `HOST/OWNER/REPO` as a `clone` shorthand

The original hub chose another host with `GITHUB_HOST`, as in
`GITHUB_HOST=git.my.org hub clone myorg/myrepo`. hub hands `HOST/OWNER/REPO`
to git unchanged, and git reads it as a path. Set `GH_HOST` (`GITHUB_HOST`
still works), or write the URL.

```sh
GH_HOST=ghe.example.com hub clone acme/widgets   # => git clone https://ghe.example.com/acme/widgets.git
hub clone https://ghe.example.com/acme/widgets.git
```

## `hub.protocol` and `HUB_PROTOCOL`

With `hub.protocol` set to `ssh`, the original `hub clone rtomayko/tilt` cloned
`git@github.com:rtomayko/tilt.git`. hub reads gh's `git_protocol` setting
instead. Set it once, or pass `-p` to `clone` and `remote` for one command.

```sh
gh config set git_protocol ssh --host github.com
hub clone -p OWNER/REPO   # => git clone git@github.com:OWNER/REPO.git
```

## `hub.host`

The original hub recognized a GitHub Enterprise host after
`git config --global --add hub.host my.git.org`. hub recognizes the hosts gh is
logged in to. Log in to the host with gh, and set `GH_HOST` to make it the
default host. hub ignores a port in a remote's URL and uses the standard port.
If an ssh alias, such as `gh-work`, does not resolve through your ssh
configuration to a host gh is logged in to, write the real host name in the
remote's URL. See [Repositories and URLs](../guide/repositories-and-urls.md).

```sh
gh auth login --hostname ghe.example.com
export GH_HOST=ghe.example.com
git remote set-url origin git@ghe.example.com:OWNER/REPO.git
```

## `HUB_CONFIG` and the config file

The original hub saved a token in `~/.config/hub` (`HUB_CONFIG` moved it). hub
has no token or settings file and does not read that file. Log in with gh, or
set `GH_TOKEN` for gh to use.

```sh
gh auth login
```

## `issue update` and `issue labels`

The original `hub issue update 134 --state closed` closed an issue, and
`hub issue labels` listed the labels. hub renames only `issue show`, to
`gh issue view`. It hands `issue update` and `issue labels` to gh unchanged,
and gh rejects them as unknown commands. Use gh's commands.

```sh
hub issue close 134
hub issue edit 12 --add-label bug
gh label list
```

`hub issue reopen 134` reopens the issue. `hub issue edit` also takes
`--remove-label`, `--title` and `--milestone`.

## `api -t`, `--flat` and the other `api` flags

The original `hub api --flat users/octocat/repos` printed JSON as
`path<TAB>value` lines. `hub api` hands every argument to `gh api` unchanged,
where `-t` is `--template`. Select values with `--jq`. gh has no
`--obey-ratelimit`, so remove the flag, and gh colors JSON in a terminal on its
own, so drop `--color`.

```sh
hub api user --jq .login
hub api --cache 600s repos/cli/cli/releases --jq '.[0].tag_name'
```

The second command prints the latest release's tag and caches the response for
600 seconds.

## `rc` in `alias`

The original `hub alias rc` printed the lines that made the rc shell run hub,
with `fn git { builtin hub $* }` for `-s`. hub prints lines for bash, zsh, sh,
ksh, dash, fish, csh and tcsh only, and stops with `unsupported shell: rc`. In
rc, define the function yourself in `$home/lib/profile`. See
[hub alias](../commands/alias.md).

```rc
fn git { builtin hub $* }
```

## `-f` in `checkout` with a pull request URL

The original `hub checkout -f URL` ran `git checkout -f`, which discards local
changes. hub refuses `-f` and `--force` next to a URL, because gh's `--force`
resets the branch to the pull request. To reset the branch, run gh yourself.
See [hub checkout](../commands/checkout.md).

```sh
gh pr checkout https://github.com/OWNER/REPO/pull/12 --force
```

## See also

- [Coming from the original hub](README.md)
- [hub and gh](hub-vs-gh.md)
- [Configuration](../guide/configuration.md)
- [Hosts and login](../guide/hosts-and-login.md)
- [Browser and clipboard](../guide/browser-and-clipboard.md)
- [Repositories and URLs](../guide/repositories-and-urls.md)
- [hub's manuals](https://brc-dd.github.io/hub/)
- [The original hub's manuals](https://hub.github.com/)
- [gh's manual](https://cli.github.com/manual/)
