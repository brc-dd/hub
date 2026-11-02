---
title: Make git run hub
description: Add one line to your shell's startup file so that git runs hub.
---

# Make git run hub

This page is for people who have installed hub and want to type `git` instead
of `hub`. After you add one line to your shell's startup file,
`git clone rails/rails` clones https://github.com/rails/rails, and every other
git command runs as before. If hub is not installed yet, start with
[Install hub](install.md). In the examples, `# =>` marks the command hub runs.

## Add the alias to your shell

Run `hub alias`. It prints the line for your shell (the last part of `$SHELL`,
such as `zsh`) and the startup file the line goes in. It writes nothing
anywhere.

```sh
hub alias
```

In zsh, it prints:

```text
# Add this line to ~/.zshrc, after the lines that set up PATH:
eval "$(hub alias -s zsh)"
```

Add the line after the lines that set up `PATH`, because the line runs hub.
Then open a new terminal. To get the line for another shell, name the shell:

```sh
hub alias fish
```

```text
# Add this line to ~/.config/fish/config.fish, after the lines that set up PATH:
hub alias -s fish | source
```

The table shows the file and the line for each shell.

| Shell | Startup file | The line `hub alias SHELL` prints |
|---|---|---|
| bash | `~/.bashrc` | `eval "$(hub alias -s bash)"` |
| zsh | `~/.zshrc` | `eval "$(hub alias -s zsh)"` |
| fish | `~/.config/fish/config.fish` | `hub alias -s fish \| source` |
| ksh | `~/.kshrc` | `eval "$(hub alias -s ksh)"` |
| sh, dash | `~/.profile` | `eval "$(hub alias -s sh)"`, `eval "$(hub alias -s dash)"` |
| csh, tcsh | `~/.cshrc`, `~/.tcshrc` | ``eval "`hub alias -s csh`"``, ``eval "`hub alias -s tcsh`"`` |

The `-s` option prints only the alias, for the shell to evaluate. It is
`alias git=hub` in every shell but csh and tcsh, where it is `alias git hub`.

```sh
hub alias -s tcsh
```

```text
alias git hub
```

If `$SHELL` is empty, name the shell as an argument. hub refuses a shell that
is not in the table:

```sh
hub alias nushell
```

```text
hub alias: unsupported shell: nushell (use one of bash, zsh, sh, ksh, dash, fish, csh, tcsh)
```

The [hub alias](../commands/alias.md) page has every message.

## How the alias works

With the alias, your shell runs hub for every `git` you type. hub's own
commands, such as `sync` and `browse`, run in hub. The git commands hub
extends, such as `clone` and `push`, change only a line that uses one of hub's
forms: a [GitHub shorthand](../guide/repositories-and-urls.md) or URL, a user
name for fetch, or a comma-separated list of remotes for push. Any other line
goes to git untouched. The gh commands, such as `pr` and `issue`, go to the
GitHub CLI (gh). hub hands every other command line to git untouched, with
git's output, messages and exit status.

hub needs a shell alias, not a git alias. git ignores a git alias with the name
of one of its own commands. For example, git never runs `alias.clone` for
`git clone`. Each `git` command takes about 15 ms longer, because hub starts
first.

To see what hub does with a command line, put `--noop` before the command. hub
prints the git and gh commands that change something instead of running them.
Read-only lookups still run. A git command that hub does not handle comes back
as the git command line, with each argument quoted the way bash quotes it:

```sh
git --noop commit -m 'Fix the build'
# => git commit -m Fix\ the\ build
```

With the alias, a git command that hub extends needs bash 5, also for a line
that hub hands to git. See
[Check the requirements](install.md#check-the-requirements), and
[How hub works](../guide/how-hub-works.md) for the full dispatch rules.

> [!IMPORTANT]
> Use the alias, not a file named `git` that points to hub, such as a symlink in
> `~/bin`. hub refuses to run when the first `git` on `PATH` is hub itself.

## Check that the alias works

In a new terminal, ask the shell what `git` is:

| Shell | Run | It prints |
|---|---|---|
| bash | `type git` | ``git is aliased to `hub'`` |
| zsh, ksh and dash | `type git` | `git is an alias for hub` |
| csh and tcsh | `alias git` | `hub` |
| fish | `type git` | the `git` function that calls hub |

In bash, `which git` does not see aliases. It prints the path of git.

To check that hub answers, run a hub command through `git`. It prints the
alias, which is `alias git hub` in csh and tcsh:

```sh
git alias -s
```

```text
alias git=hub
```

If git answers that `alias` is not a git command, the shell did not load the
alias. Check the startup file, then open a new terminal.

## Use hub without the alias

The alias is optional. Every command works as `hub NAME`:

```sh
hub --noop clone rails/rails
# => git clone https://github.com/rails/rails.git
hub --noop tag v1.0
# => git tag v1.0
```

To run git without hub while the alias is active, put `command` before `git`.
This works in bash, zsh, ksh and dash:

```sh
command git status  # runs git, not hub
```

## Caveats

- Only your interactive shell has the alias. Scripts, git GUIs, editors and
  other programs that start git run plain git. Write `hub` in a script that
  needs hub's commands.
- In zsh, hub's completion completes both `hub` and `git`. With
  `setopt complete_aliases`, zsh completes `git` with git's own completion.
  Without it, zsh completes `git` with hub's completion. See
  [Shell completion](completions.md).
- hub does not expand your git aliases. With `alias.co=checkout`,
  `git co PULL-REQUEST-URL` goes to git untouched, so hub's checkout of a pull
  request does not happen. Type the full command name for hub's behavior.
- A git alias with the name of a hub command, such as `alias.pr`, never runs:
  hub's command runs instead.
- A git alias that starts with `!` runs a shell command, which can call hub:

  ```sh
  git config alias.web '!hub browse'
  git web -- issues
  # => open https://github.com/OWNER/REPO/issues
  ```

  `hub browse -- issues` opens the issues page of the current repository. The
  `--` means no repository is named. See [hub browse](../commands/browse.md).

## Differences from the original hub

For what changed since the original hub (mislav/hub 2.x), see
[hub alias](../commands/alias.md#differences-from-the-original-hub).

## See also

- [Install hub](install.md): the requirements, including bash 5.
- [Shell completion](completions.md): complete hub's commands for `hub` and
  `git`.
- [How hub works](../guide/how-hub-works.md): the full dispatch rules.
- [hub alias](../commands/alias.md): every option and message of `hub alias`.
- [Coming from the original hub](../compatibility/README.md): what else changed
  since the original hub.
- [hub manuals](https://brc-dd.github.io/hub/): this hub's manual pages.
