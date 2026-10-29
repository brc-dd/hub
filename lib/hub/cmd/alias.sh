# shellcheck shell=bash
# Summary: Show how to make `git` run hub.
# Usage: hub alias [-s] [SHELL]
#
# Prints what to add to your shell's startup file so that typing `git` runs
# hub. With -s, prints only the code to evaluate:
#
#   $ hub alias -s zsh
#   alias git=hub
#
#   eval "$(hub alias -s)"          # ~/.bashrc, ~/.zshrc
#   hub alias -s fish | source      # ~/.config/fish/config.fish
#
# SHELL defaults to the basename of $SHELL. Supported: bash, zsh, sh, ksh,
# dash, fish, csh and tcsh.
#
# Aliasing git to hub is safe: hub acts only on its own commands and on GitHub
# URLs and OWNER/REPO shorthands given to the git commands it extends (clone,
# fetch, push, ...), and runs the real git, untouched, for everything else.
# A shell alias works where a git alias cannot: git ignores aliases that
# shadow its built-in commands, but the shell swaps the word `git` for `hub`
# before git ever runs.

hub_cmd_alias() {
  local script=0 shell='' rc line
  while (($#)); do
    case $1 in
      -s) script=1 ;;
      -h | --help) hub::usage ;;
      -*) hub::die "hub alias: unknown option: $1" ;;
      *)
        [[ -z $shell ]] || hub::die "Usage: hub alias [-s] [SHELL]"
        shell=$1
        ;;
    esac
    shift
  done
  if [[ -z $shell ]]; then
    shell=${SHELL:-}
    shell=${shell##*/}
    [[ -n $shell ]] || hub::die "hub alias: can't tell your shell from \$SHELL; name it, e.g. hub alias -s bash"
  fi

  # shellcheck disable=SC2088  # the ~ is meant for the reader, not for expansion
  case $shell in
    bash) rc='~/.bashrc' ;;
    zsh) rc='~/.zshrc' ;;
    ksh) rc='~/.kshrc' ;;
    sh | dash) rc='~/.profile' ;;
    csh) rc='~/.cshrc' ;;
    tcsh) rc='~/.tcshrc' ;;
    fish) rc='~/.config/fish/config.fish' ;;
    *) hub::die "hub alias: unsupported shell: $shell (supported: bash, zsh, sh, ksh, dash, fish, csh, tcsh)" ;;
  esac

  if ((script)); then
    case $shell in
      csh | tcsh) printf 'alias git hub\n' ;;
      *) printf 'alias git=hub\n' ;;
    esac
    return 0
  fi
  case $shell in
    csh | tcsh) line="eval \"\`hub alias -s $shell\`\"" ;;
    fish) line="hub alias -s fish | source" ;;
    *) line="eval \"\$(hub alias -s $shell)\"" ;;
  esac
  printf '# Make git run hub: add this line to %s\n%s\n' "$rc" "$line"
}
