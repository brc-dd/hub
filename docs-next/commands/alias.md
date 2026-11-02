---
title: hub alias
description: Show how to make git run hub.
kind: hub's own command
original: https://hub.github.com/hub-alias.1.html
---

# hub alias

`hub alias` prints the line that makes your interactive shell run hub when you
type `git`, and names the startup file that the line goes in. hub writes no
file: you copy the line into that file yourself. Use it once, after you install
hub. The most common use is `hub alias zsh`, which prints the line for
`~/.zshrc`.

```sh
hub alias zsh
# => # Add this line to ~/.zshrc, after the lines that set up PATH:
# => eval "$(hub alias -s zsh)"
```

## Usage

```text
hub alias [-s] [SHELL]
```

`SHELL` is the name of your shell: `bash`, `zsh`, `sh`, `ksh`, `dash`, `fish`,
`csh` or `tcsh`. Without it, hub takes the last part of the `SHELL` environment
variable, so `/bin/zsh` counts as `zsh`.

## Examples

The examples write `hub`, because the alias they set up does not exist yet.
Each `# =>` line is what the command prints. The examples run in zsh, with the
`SHELL` environment variable set to `/bin/zsh`.

Print the instructions for the shell that `SHELL` names:

```sh
hub alias
```

```text
# Add this line to ~/.zshrc, after the lines that set up PATH:
eval "$(hub alias -s zsh)"
```

Print only the alias, the text that the startup line evaluates:

```sh
hub alias -s zsh
# => alias git=hub
```

Set up fish. Its line pipes the alias to `source` instead of using `eval`:

```sh
hub alias fish
```

```text
# Add this line to ~/.config/fish/config.fish, after the lines that set up PATH:
hub alias -s fish | source
```

The other shells print the same two lines as zsh, with their own startup file.
`sh` and `dash` both use `~/.profile`. The table under
[How it works](#how-it-works) lists the file and the line for each shell.

Print the alias for csh or tcsh. Put `-s` before or after the shell name:

```sh
hub alias -s csh
# => alias git hub
hub alias csh -s
# => alias git hub
```

These shells have no `=` in their alias, and their startup line uses
backquotes: ``eval "`hub alias -s tcsh`"``. `--` ends the options, so
`hub alias -- fish` is the same as `hub alias fish`.

Take the shell from a full path in `SHELL`. hub uses only the name after the
last `/`:

```sh
SHELL=/usr/local/bin/tcsh hub alias
```

```text
# Add this line to ~/.tcshrc, after the lines that set up PATH:
eval "`hub alias -s tcsh`"
```

Check that the alias works in a new zsh session:

```sh
alias git
# => git=hub
```

In bash, `type git` prints ``git is aliased to `hub'``.

Run it with an empty `SHELL` and no operand:

```sh
SHELL= hub alias
```

```text
hub alias: cannot tell your shell from SHELL (name it: hub alias SHELL)
```

hub cannot tell your shell. Name it as an operand: `SHELL= hub alias zsh`
prints the zsh instructions.

Pass a path or a word with a space instead of a shell name:

```sh
hub alias /bin/zsh
hub alias 'fi sh'
```

```text
hub alias: unsupported shell: /bin/zsh (use one of bash, zsh, sh, ksh, dash, fish, csh, tcsh)
hub alias: unsupported shell: fi\ sh (use one of bash, zsh, sh, ksh, dash, fish, csh, tcsh)
```

hub refuses a path or an unknown name. In a message, it quotes a word that has
spaces or control characters.

Name a second shell:

```sh
hub alias bash zsh
```

```text
hub alias: unexpected argument: zsh
Usage: hub alias [-s] [SHELL]
```

## Options

| Option | What it does |
|---|---|
| `-s` | Print only the alias, for `eval`: `alias git=hub`, or `alias git hub` for csh and tcsh. Default: print the startup file and the line for it. |
| `-h`, `--help` | Print this command's manual. |

These are all the options. Any other option is a usage error, and `-h` or
`--help` prints the manual.

## How it works

hub applies these rules in order:

1. hub takes the shell from the `SHELL` operand. Without one, it takes the name
   after the last `/` in the `SHELL` environment variable.
2. hub looks up the shell in the table of shells after this list. An unknown
   name stops it with `unsupported shell`.
3. With `-s`, hub prints the alias. Without `-s`, it prints a comment line that
   names the startup file, then the line to add to that file.

| Shell | Startup file | Line to add | `-s` prints |
|---|---|---|---|
| bash | `~/.bashrc` | `eval "$(hub alias -s bash)"` | `alias git=hub` |
| zsh | `~/.zshrc` | `eval "$(hub alias -s zsh)"` | `alias git=hub` |
| ksh | `~/.kshrc` | `eval "$(hub alias -s ksh)"` | `alias git=hub` |
| sh | `~/.profile` | `eval "$(hub alias -s sh)"` | `alias git=hub` |
| dash | `~/.profile` | `eval "$(hub alias -s dash)"` | `alias git=hub` |
| fish | `~/.config/fish/config.fish` | `hub alias -s fish \| source` | `alias git=hub` |
| csh | `~/.cshrc` | ``eval "`hub alias -s csh`"`` | `alias git hub` |
| tcsh | `~/.tcshrc` | ``eval "`hub alias -s tcsh`"`` | `alias git hub` |

The startup line runs `hub` each time the shell starts. Put it after the lines
that set up `PATH`, so that the shell can find hub. `hub alias` writes no file,
and it works outside a git repository.

hub needs a shell alias because git ignores a git alias that hides one of its
own commands: `alias.clone` never runs for `git clone`. Only interactive shells
read the alias. Scripts keep running plain git. Do not install hub under the
name `git`: hub refuses to run when the first `git` on `PATH` is hub itself.

Under the alias, hub passes each command that it does not handle to git. This
adds about 15 ms, the time that hub needs to start. A git alias of yours with
the name of a hub command, such as `alias.pr`, no longer runs: hub's command
runs instead. See [How hub works](../guide/how-hub-works.md) for the commands
that hub handles and the commands it passes to git.

Like every hub command, `hub alias` needs bash 5 or newer. See
[Check the requirements](../getting-started/install.md#check-the-requirements).
hub runs every command through git. If git cannot read the repository's
configuration, `hub alias` prints git's `fatal:` message and stops. Fix the
configuration, or run `hub alias` outside the repository.

## Exit status

`hub alias` exits with status 0 when it prints the alias or the instructions.
hub's own refusals exit with status 1: an empty `SHELL` environment variable
with no operand, an unsupported shell, an extra word or an unknown option. So
do bash older than 5 and a first `git` on `PATH` that is hub itself. These are
the messages of `hub alias`:

```text
hub alias: cannot tell your shell from SHELL (name it: hub alias SHELL)
hub alias: unsupported shell: NAME (use one of bash, zsh, sh, ksh, dash, fish, csh, tcsh)
hub alias: unexpected argument: WORD
hub alias: unknown option: OPTION
```

Inside a repository whose configuration git cannot read, `hub alias` exits with
git's status, 128.

## Differences from the original hub

The synopsis `hub alias [-s] [SHELL]` is the same, and so is the default: the
name of the shell in the `SHELL` environment variable.

| Original hub | This hub |
|---|---|
| Supported bash, zsh, sh, ksh, csh, tcsh, fish and rc. | bash, zsh, sh, ksh, dash, fish, csh and tcsh. `dash` is new. `rc` is not supported. |
| bash used `~/.bash_profile`. | `~/.bashrc`. |
| ksh used `~/.profile`. | `~/.kshrc`. |
| sh used "your profile". | `~/.profile`. |
| zsh used `~/.zshrc`, csh `~/.cshrc` and tcsh `~/.tcshrc`. | Same. |
| fish used a `git` function in `~/.config/fish/functions/git.fish` that ran `hub $argv`. | `hub alias -s fish \| source` in `~/.config/fish/config.fish`. |
| The line was `eval "$(hub alias -s)"`, or ``eval "`hub alias -s`"`` for csh and tcsh. | The line names the shell: `eval "$(hub alias -s zsh)"`. |
| The comment said `# Wrap git automatically by adding the following to PROFILE:`, then a blank line, then the line. | `# Add this line to FILE, after the lines that set up PATH:`, then the line, with no blank line. |
| `-s` printed `alias git=hub`, or `alias git hub` for csh and tcsh. | Same, fish included. |
| An unsupported shell printed `hub alias: unsupported shell` and a `supported shells:` line, exit 1. | `hub alias: unsupported shell: NAME (use one of ...)` on one line, exit 1. |
| An empty `SHELL` environment variable printed ``Error: couldn't detect shell type. Please specify your shell with `hub alias <shell>` `` (`hub alias -s <shell>` when `-s` was given), exit 1. | `hub alias: cannot tell your shell from SHELL (name it: hub alias SHELL)`, exit 1. |
| The README showed `Set-Alias git hub` for PowerShell. | Not supported. Use one of the supported shells. |

The original example `hub alias` with `SHELL=/bin/bash` named
`~/.bash_profile`. In this hub, it names `~/.bashrc` and prints
`eval "$(hub alias -s bash)"`.

## See also

- [hub help](help.md): print the manual of any command.
- [hub version](version.md): check the install.
- [Make git run hub](../getting-started/alias.md): the alias for each shell,
  step by step, and its caveats.
- [Install hub](../getting-started/install.md) and
  [shell completion](../getting-started/completions.md).
- [How hub works](../guide/how-hub-works.md): which commands hub handles and
  which it hands to git.
- [Coming from the original hub](../compatibility/README.md).
- The original hub's manual:
  [hub-alias(1)](https://hub.github.com/hub-alias.1.html).
- This hub's manual: [hub alias](https://brc-dd.github.io/hub/alias.html).
