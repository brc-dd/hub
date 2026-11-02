---
title: hub browse
description: Open a GitHub repository in the web browser.
kind: hub's own command
original: https://hub.github.com/hub-browse.1.html
---

# hub browse

`hub browse` opens a page of a GitHub repository in your web browser. hub
builds the URL from the current project or from a repository you name, and it
can print or copy the URL instead. Use it to reach the issues, pull requests
or files of a project, or the branch you pushed. The most common use is
`hub browse`, which opens the current project on GitHub.

```sh
hub browse
# => open https://github.com/OWNER/REPO
```

## Usage

```text
hub browse [-u] [-c] [[[HOST/]OWNER/]REPO | --] [SUBPAGE]
```

`OWNER/REPO` is the repository to open. It can also be `HOST/OWNER/REPO` or a
repository URL, and `REPO` alone is the repository of that name under your
login. Without a repository, or with `--` in its place, hub uses the current
project, as [The project and its remotes](../guide/project-and-remotes.md)
explains. `SUBPAGE` is the rest of the URL path, such as `issues`, `pulls`,
`wiki` or `settings/branches`.

## Examples

The examples write `hub`. With the alias from [hub alias](alias.md),
`git browse` is the same command. Each `# =>` line is what `hub --noop`
prints: `open URL` where hub opens the browser, and `copy URL` where it copies
the URL. With `-u`, the `# =>` line is the URL that hub prints. Unless an
example says otherwise, it runs in a clone of mislav/dotfiles on its default
branch.

Open the front page of the current project:

```sh
hub browse
# => open https://github.com/mislav/dotfiles
```

Open a subpage of the current project. The `--` stands for the current
project, so hub reads the next word as the subpage:

```sh
hub browse -- issues
# => open https://github.com/mislav/dotfiles/issues
hub browse -- settings/branches
# => open https://github.com/mislav/dotfiles/settings/branches
```

Open a page of another repository:

```sh
hub browse rails/rails pulls
# => open https://github.com/rails/rails/pulls
```

Print the URL instead of opening it. Nothing opens:

```sh
hub browse -u cli/cli releases
# => https://github.com/cli/cli/releases
```

Copy the URL to the clipboard. hub prints nothing:

```sh
hub browse -c cli/cli issues
# => copy https://github.com/cli/cli/issues
```

Print the URL and copy it, with both options:

```sh
hub browse -uc cli/cli
# => https://github.com/cli/cli
# => copy https://github.com/cli/cli
```

On a branch `feature` that you pushed to `origin`, open the front page or the
commits of that branch. Other subpages stay on the project:

```sh
hub browse
# => open https://github.com/mislav/dotfiles/tree/feature
hub browse -- commits
# => open https://github.com/mislav/dotfiles/commits/feature
hub browse -- issues
# => open https://github.com/mislav/dotfiles/issues
```

In a clone of octo/proj, add your fork as a remote and push `feature` to it
with `-u`. The branch pages then open in the fork, and the other pages open in
octo/proj:

```sh
git remote add LOGIN https://github.com/LOGIN/proj.git
git push -u LOGIN feature
hub browse -u -- commits
# => https://github.com/LOGIN/proj/commits/feature
hub browse -u -- issues
# => https://github.com/octo/proj/issues
```

Open a repository of your own by its name. hub asks the GitHub CLI (gh) for
your login:

```sh
hub browse -u dotfiles
# => https://github.com/LOGIN/dotfiles
```

Name the host, or paste a clone URL:

```sh
hub browse -u ghe.example.com/Octo/Proj wiki
# => https://ghe.example.com/Octo/Proj/wiki
hub browse -u git@github.com:cli/cli.git pulls
# => https://github.com/cli/cli/pulls
hub browse -u https://github.com/cli/cli.git
# => https://github.com/cli/cli
```

Open a file tree, a commit or a comparison. hub appends the subpage as you
type it:

```sh
hub browse cli/cli tree/main/lib
# => open https://github.com/cli/cli/tree/main/lib
hub browse rails/rails commit/4173c3b
# => open https://github.com/rails/rails/commit/4173c3b
hub browse -- compare/main...feature
# => open https://github.com/mislav/dotfiles/compare/main...feature
```

Set `GH_REPO` to make another repository the current project, for example in
a script:

```sh
GH_REPO=cli/cli hub browse -- releases
# => open https://github.com/cli/cli/releases
```

See [Point hub at another
repository](../guide/project-and-remotes.md#point-hub-at-another-repository).

Name a word that is not a repository. hub stops with a message and status 1:

```sh
hub browse cli/cli/issues
```

```text
hub browse: not a repository: cli/cli/issues (use REPO, OWNER/REPO, HOST/OWNER/REPO or a repository URL)
```

## Options

| Option | What it does |
|---|---|
| `-u`, `--url` | Print the URL instead of opening it. |
| `-c`, `--copy` | Copy the URL to the clipboard instead of opening it. With `-u`, print and copy. |

These are all the options. Any other option is a usage error, and `-h` or
`--help` prints the manual.

## How it works

hub applies these rules in order:

1. The repository: `REPO` alone is `LOGIN/REPO` on the default host, where
   `LOGIN` is your login as gh knows it. `OWNER/REPO`, `HOST/OWNER/REPO` and
   repository URLs read as in
   [Repositories and URLs](../guide/repositories-and-urls.md). Without a
   repository, or with `--`, hub uses the current project: `GH_REPO` when it
   is set, else the first GitHub remote among `upstream`, `github` and
   `origin`, else any other GitHub remote.
2. The subpage: hub appends `SUBPAGE` to `https://HOST/OWNER/REPO/` as given.
   `tree` alone is the front page. hub drops a trailing `.git` from the
   repository.
3. The branch page: if you name no repository, `GH_REPO` is not set and the
   subpage is empty, `tree` or `commits`, hub looks at the current branch. If
   that branch is not the default branch and exists on the remote it pushes
   to, hub opens `tree/BRANCH` or `commits/BRANCH` in the repository of that
   remote. Unpushed commits do not matter. An unpushed branch, a detached
   `HEAD` and an unborn branch open the project with no branch name.
4. The default branch: hub reads `refs/remotes/REMOTE/HEAD` of the project's
   remote, as the last fetch or clone recorded it, and does not ask GitHub. If
   that ref is missing or points at a missing branch, every pushed branch
   counts as non-default, so a pushed `main` opens as `tree/main`. To record
   the default branch, run `git remote set-head origin --auto`.
5. The push remote: hub follows `branch.NAME.pushRemote`, then
   `remote.pushDefault`, then an upstream of the same branch name, such as one
   set by `git push -u`. It does not follow an upstream with another name,
   such as `origin/main` after `--track origin/main`. Without any of these,
   hub takes the only remote, else your fork among the remotes, else `origin`.
   If the push URL of that remote is not a GitHub repository, hub opens the
   project with no branch name. See [Find where a branch
   pushes](../guide/project-and-remotes.md#find-where-a-branch-pushes).
6. The branch name: hub escapes it for the URL and keeps its slashes.
   `topic/a#b+c` becomes `tree/topic/a%23b%2Bc`.
7. Where the URL goes: `-u` prints it, `-c` copies it, and otherwise hub
   opens it. The browser is `GH_BROWSER`, else gh's `browser` setting, else
   `BROWSER`, else `open`, else `xdg-open`. The clipboard tool is `pbcopy`,
   else `wl-copy`, else `xclip -selection clipboard`. See
   [Browser and clipboard](../guide/browser-and-clipboard.md).

hub builds the URL from git's configuration and runs gh for three things only.
It reads your login when you name `REPO` alone, and to tell your fork among
several remotes when the branch names no push remote. Without gh or a login
there, hub stays on the project. It also reads gh's `browser` setting. With
`GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN` or `GITHUB_ENTERPRISE_TOKEN`
set, hub asks the API for your login instead of gh's configuration.

## Exit status

When hub opens or copies the URL, it exits with the status of the browser or
the clipboard tool. With `-u` alone, it exits with 0. hub's own refusals exit
with status 1 and print one of these messages:

| Message | What to do |
|---|---|
| `hub browse: unknown option: --urls` | Use only `-u` and `-c`. The `Usage:` line follows the message. |
| `hub browse: unexpected argument: extra` | Give at most two words, or one word after `--`. The `Usage:` line follows the message. |
| `hub browse: unexpected argument: --` | Write `--` only in place of the repository. The `Usage:` line follows the message. |
| `hub browse: not a repository: a/b/c/d (use REPO, OWNER/REPO, HOST/OWNER/REPO or a repository URL)` | Name a shorthand or a GitHub URL. |
| `hub browse: no GitHub remote found (looked for upstream, github, origin)` | Name a repository, or add a remote that points at GitHub. |
| `hub browse: this command needs the GitHub CLI, gh (https://cli.github.com)` | Install gh to name `REPO` alone, or write `OWNER/REPO`. |
| `hub browse: could not determine your GitHub login for github.com (run: gh auth login -h github.com)` | Run the `gh auth login` command it names, or write `OWNER/REPO`. |
| `hub browse: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL` | Set `GH_REPO` to one of these forms. |
| `hub browse: not a host name: a\ b` | Set `GH_HOST` to a host name. |
| `hub browse: no browser found to open URL (set GH_BROWSER or BROWSER)` | Set `GH_BROWSER` or `BROWSER`, or install `open` or `xdg-open`. |
| `hub browse: no clipboard tool found (install pbcopy, wl-copy or xclip)` | Install `pbcopy`, `wl-copy` or `xclip` to use `-c`. |

## Differences from the original hub

| Original hub | This hub |
|---|---|
| `hub browse [-uc] [[USER/]REPOSITORY\|--] [SUBPAGE]` | Same. The repository can also be `HOST/OWNER/REPO` or a URL. |
| `-u, --url` and `-c, --copy`. `-c` printed nothing. | Same. `-u -c` prints and copies. |
| `REPO` alone was your repository, also inside another repository. | Same. Your login comes from gh. |
| The project was the first GitHub remote among `upstream`, `github`, `origin`. | Same. `GH_REPO` comes first. |
| Without a GitHub remote, it printed `Aborted: could not find any git remote pointing to a GitHub repository`. Without a repository and with no argument, it printed the usage line, status 1. | `no GitHub remote found (looked for upstream, github, origin)`, status 1, inside or outside a repository. |
| The front page on a pushed branch opened `tree/BRANCH`, where BRANCH was the push target. With `push.default` set to `upstream`, that was the upstream's name, for example `tree/experimental`. | `tree/BRANCH` with the branch's own name, in the repository the branch pushes to. `push.default` and push refspecs are not read. An upstream with another name is not followed. |
| Off a pushed branch, `commits` opened `commits/master`, the default branch by name. `hub browse mislav/dotfiles commits` did the same. | `commits` of the repository, with no branch name. |
| The default branch came from `refs/remotes/REMOTE/HEAD` of the main remote. | Same, from the project's remote. Without it, every pushed branch counts as non-default. |
| Other subpages ignored the branch and used the project, not your fork. | Same. |
| Branch names were escaped per path segment: `fix-bug-#123` became `fix-bug-%23123`. | Same. For example `topic/a#b+c` becomes `topic/a%23b%2Bc`. |
| A wiki repository (`OWNER/REPO.wiki.git`) mapped to `/wiki`, `/wiki/_history` and `/wiki/_pages`. | Not supported. Use `hub browse -- wiki`. |
| `hub compare` opened a compare page for a renamed fork. | Open it as a subpage: `hub browse -- compare/BASE...OWNER:FORK:BRANCH`. |
| SSH host aliases in `~/.ssh/config` were resolved. | Same, through `ssh -G`. |
| A GitHub Enterprise host counted after `git config --global --add hub.host HOST`. `GITHUB_HOST` set the default host. | Not read. In a remote or URL, a host counts when gh is logged in to it or `GH_HOST` names it. A named `HOST/OWNER/REPO` with a dot in HOST always counts. `GITHUB_HOST` still works as `GH_HOST`. |
| A host configured as `http://git.my.org` got `http` URLs. | Every URL is `https`. |
| Without a known username, `-u` prompted for one. | hub fails with the login message and names `gh auth login`. `OWNER/REPO` needs no login. |
| The browser was `BROWSER`, else `open` on macOS, else the first of `xdg-open` and a list of others. | `GH_BROWSER`, gh's `browser` setting, `BROWSER`, then `open` or `xdg-open`. Without one: `no browser found to open URL (set GH_BROWSER or BROWSER)`. |

## See also

- [hub compare](compare.md): open a comparison of two branches.
- [hub pull-request](pull-request.md): open a pull request, with `-o` to open
  it in the browser.
- [Browser and clipboard](../guide/browser-and-clipboard.md) and
  [Configuration](../guide/configuration.md): `GH_BROWSER`, `BROWSER` and
  `GH_REPO`.
- [The project and its remotes](../guide/project-and-remotes.md) and
  [Repositories and URLs](../guide/repositories-and-urls.md): which repository
  hub opens.
- [Coming from the original hub](../compatibility/README.md)
- The original hub's manual:
  [hub-browse(1)](https://hub.github.com/hub-browse.1.html)
- gh's manual: [gh browse](https://cli.github.com/manual/gh_browse)
- This hub's manual: [hub browse](https://brc-dd.github.io/hub/browse.html)
