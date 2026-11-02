---
title: Configuration
description: Every setting hub reads, from the environment, gh and git config.
---

# Configuration

This page is for anyone who wants to change the host, the repository, the
protocol or the browser that hub uses. It explains every setting hub reads:
environment variables, the settings of GitHub CLI (gh), and git's
configuration. hub has no configuration file and no token of its own. The
examples use `hub` and run in a clone of OWNER/REPO. With the
[alias](../getting-started/alias.md), `git` runs the same commands.

## Change settings with environment variables

Set a variable for one command, or export it in your shell's startup file.

| Variable | Read by | What it does | Example |
|---|---|---|---|
| `GH_HOST` | hub and gh | The default host for `OWNER/REPO` and `REPO`: `GH_HOST`, else the one host gh is logged in to, else github.com. hub stops with an error if the value is not a host name. | `GH_HOST=ghe.example.com hub clone OWNER/REPO` |
| `GITHUB_HOST` | hub | The name the original hub (mislav/hub 2.x) used for `GH_HOST`. When `GH_HOST` is unset, hub exports it as `GH_HOST`, so gh sees it too. | `GITHUB_HOST=ghe.example.com hub clone OWNER/REPO` |
| `GH_REPO` | hub and gh | The project, as `OWNER/REPO`, `HOST/OWNER/REPO` or a URL, instead of the remotes. Any other value stops hub with `GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL`. | `GH_REPO=cli/cli hub browse -- issues` |
| `GH_TOKEN`, `GITHUB_TOKEN` | hub and gh | gh uses the token for github.com and `*.ghe.com`. When any token variable is set, hub asks the API whose token it is instead of reading gh's stored login. | `GH_TOKEN=TOKEN hub clone REPO` |
| `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN` | hub and gh | The same, for a GitHub Enterprise Server host. | `GH_ENTERPRISE_TOKEN=TOKEN GH_HOST=ghe.example.com hub clone REPO` |
| `GH_CONFIG_DIR` | hub and gh | The directory of gh's `hosts.yml`. Unset, it is `$XDG_CONFIG_HOME/gh`, else `~/.config/gh`. | `GH_CONFIG_DIR=$HOME/work-gh hub clone REPO` |
| `GH_BROWSER` | hub | The browser for `browse`, `compare` and `-o`. It takes precedence over gh's `browser` setting and `BROWSER`. It can include arguments, and hub adds the URL after them. | `GH_BROWSER=firefox hub browse` |
| `BROWSER` | hub | The browser when neither `GH_BROWSER` nor gh's `browser` setting is set. Then hub tries `open`, then `xdg-open`. | `BROWSER=w3m hub browse` |
| `GH_PROMPT_DISABLED` | hub and gh | When it is set, gh does not prompt. If you run `pull-request` with `-e`, or without `-m`, `-F` or `--no-edit`, hub then stops before it pushes. | `GH_PROMPT_DISABLED=1 hub --noop pull-request -f` |
| `GIT_CONFIG` | ignored | hub's commands unset it, so they read the configuration that `git push` reads. | `GIT_CONFIG=other.cfg hub push origin,fork` |
| `HUB_NOOP` | ignored | Only the `--noop` flag turns on the dry run. | `hub --noop fork` |
| `SHELL` | `hub alias` | The shell `hub alias` writes for, when you name none. | `SHELL=/bin/zsh hub alias -s` |
| `TMPDIR` | `am`, `apply` | The directory for downloaded patches. Unset, it is `/tmp`. | `TMPDIR=$HOME/tmp hub am https://github.com/OWNER/REPO/pull/1` |

## Change settings through gh

hub reads these from gh's configuration: the settings through `gh config get`,
and the host names straight from `hosts.yml`. Change them with `gh config set`
or `gh auth login`. See [gh config](https://cli.github.com/manual/gh_config).

| Setting | Read by | What it does | Example |
|---|---|---|---|
| `git_protocol` | `clone`, `remote`, `fetch`, `fork`, `create`, `merge`, `cherry-pick` | `ssh` gives ssh URLs to `clone`, `remote add`, `remote set-url`, `fetch`, `fork` and `create`, and to the URL `merge` and `cherry-pick` fetch from when no remote has the repository. Anything else, or no gh, gives https. A per-host value counts for that host. | `gh config set git_protocol ssh` |
| `browser` | `browse`, `compare`, `-o` | The browser after `GH_BROWSER`. hub does not ask for it under `--noop`. | `gh config set browser firefox` |
| `prompt` | `pull-request` | When it is `disabled`, `pull-request` stops where gh would prompt, as with `GH_PROMPT_DISABLED`. | `gh config set prompt disabled` |
| The hosts file (`hosts.yml`) | hub | Its hosts are the known hosts. With one host, it is the default host. Its `user` for a host is your login there. | `gh auth login -h ghe.example.com` |

## Change how hub reads git config

hub reads git's configuration as git does, so `hub -c KEY=VALUE` works too.
See [Project and remotes](project-and-remotes.md) for the order of the push
rules.

| Setting | Read by | What it does | Example |
|---|---|---|---|
| `branch.NAME.pushRemote` | `pull-request`, `browse`, `compare` | The remote the branch pushes to. Set but empty, or set to a URL, it gives no push remote. | `git config branch.topic.pushRemote fork` |
| `remote.pushDefault` | `pull-request`, `browse`, `compare` | The same, for every branch without `pushRemote`. | `git config remote.pushDefault fork` |
| `branch.NAME.remote`, `branch.NAME.merge` | `pull-request`, `browse`, `compare` | If the branch tracks a branch of the same name, hub takes the remote of that upstream as the push remote. | `git branch -u fork/topic` |
| `branch.NAME.gh-merge-base` | `pull-request` (through gh 2.64 and later) | The base branch of the pull request when you give no `-b`. | `git config branch.topic.gh-merge-base develop` |
| `remote.NAME.push`, `remote.NAME.mirror` | `push REMOTE1,REMOTE2` | If the remote sets its own push refspecs or is a mirror, hub runs `git push REMOTE` without adding `HEAD`. | `git config remote.fork.mirror true` |
| `remotes.GROUP` | `fetch` | hub fetches a remote group as git does. hub does not add a remote for a GitHub user of that name. | `git config remotes.mine "origin fork"` |
| `url.BASE.insteadOf` | `push`, `fetch`, `remote` | If git rewrites a remote name or URL, hub passes it to git unchanged and does not read it as `OWNER/REPO`. hub does not read `pushInsteadOf`. | `git config url.git@github.com:.insteadOf gh:` |
| `protocol.file.allow`, `GIT_ALLOW_PROTOCOL` | `sync` | Not applied. `sync` updates local branches with a fetch from the local repository into itself, and these settings do not block that fetch. | `git config protocol.file.allow never` |

On the branch `topic`, with your fork as the remote `fork`:

```sh
hub -c remote.pushDefault=fork compare -u
# => https://github.com/OWNER/REPO/compare/LOGIN:topic
hub -c remote.fork.mirror=true --noop push origin,fork
# => git push origin HEAD
# => git push fork
```

## Move from the original hub's settings

The original hub had a login and settings of its own. hub reads only
`GITHUB_HOST`, `GITHUB_TOKEN` and `BROWSER` of them.

| Original hub | This hub |
|---|---|
| `git config hub.protocol ssh`, `HUB_PROTOCOL=ssh` | `gh config set git_protocol ssh`. hub ignores `hub.protocol` and `HUB_PROTOCOL`. |
| `HUB_PROTOCOL=git` (`git://` URLs) | No such protocol. Use ssh or https. |
| `git config --add hub.host HOST` | `gh auth login -h HOST`, and `GH_HOST` for the default host. |
| `GITHUB_HOST` | `GH_HOST`. `GITHUB_HOST` still works when `GH_HOST` is unset. |
| `GITHUB_TOKEN` | Still works: gh uses it for github.com and `*.ghe.com`, and hub then asks the API for your login. For a GitHub Enterprise Server host, use `GH_ENTERPRISE_TOKEN` (the table above). |
| `GITHUB_USER`, `GITHUB_PASSWORD` | `gh auth login`. |
| `HUB_CONFIG`, `~/.config/hub` | Gone. gh's login and `hosts.yml` replace them. |
| `HUB_VERBOSE` | Gone. `hub --noop` prints the git and gh commands that change something instead of running them. |
| `BROWSER` | `GH_BROWSER`, gh's `browser`, then `BROWSER`. |
| `HUB_RETRY_TIMEOUT` | Not read. |

## Set up common cases

### Use ssh everywhere

Set gh's protocol once, for every host or for one host. `-p` on `clone` and
`remote add` uses ssh for that one command. After setting it:

```sh
gh config set git_protocol ssh
gh config set git_protocol ssh --host ghe.example.com
hub --noop clone rails/rails
# => git clone git@github.com:rails/rails.git
hub --noop remote add USER
# => git remote add USER git@github.com:USER/REPO.git
```

With `git_protocol` unset:

```sh
hub --noop clone -p rails/rails
# => git clone git@github.com:rails/rails.git
```

### Work with a GitHub Enterprise host

Log in to the host with gh. If it is the only host gh knows, hub uses it for
shorthands. If gh knows more than one host, hub takes github.com unless you
set `GH_HOST`. With ghe.example.com as the only host:

```sh
gh auth login -h ghe.example.com
hub --noop clone OWNER/REPO
# => git clone https://ghe.example.com/OWNER/REPO.git
GH_HOST=github.com hub --noop clone rails/rails
# => git clone https://github.com/rails/rails.git
```

### Use a token in CI

Export the token for gh. hub clones `OWNER/REPO` without calling the API. For
`REPO` alone, hub needs your login, so it runs
`gh api --hostname github.com user --jq .login` to ask the API whose token it
is. That lookup still runs under `--noop`. With the token exported:

```sh
export GH_TOKEN="$CI_GITHUB_TOKEN"
hub --noop clone rails/rails
# => git clone https://github.com/rails/rails.git
hub --noop clone REPO
# => git clone https://github.com/LOGIN/REPO.git
```

If the API does not answer, hub stops before git runs, with this message:

```text
hub clone: could not determine your GitHub login for github.com (run: gh auth login -h github.com)
```

## See also

- [Hosts and login](hosts-and-login.md)
- [Project and remotes](project-and-remotes.md)
- [Browser and clipboard](browser-and-clipboard.md)
- [Coming from the original hub](../compatibility/README.md)
- [gh help environment](https://cli.github.com/manual/gh_help_environment)
