# shellcheck shell=bash
# Summary: Show how to make `git` run hub.
# Usage: hub alias [-s] [SHELL]
#
# Prints the line to add to your shell's startup file so that `git` runs hub; with -s, only the
# code it evaluates. SHELL defaults to the basename of $SHELL: bash, zsh, sh, ksh, dash, fish,
# csh or tcsh.
#
# Aliasing git is safe: hub acts only on its own commands and on GitHub URLs and OWNER/REPO
# shorthands in the git commands it extends, and runs the real git, untouched, for everything else.
#
#   $ hub alias -s zsh
#   alias git=hub

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
  shell=${shell:-${SHELL##*/}}
  [[ -n $shell ]] || hub::die "hub alias: can't tell your shell from \$SHELL; name it, e.g. hub alias -s bash"
  # shellcheck disable=SC2088  # the ~ is for the reader
  case $shell in
    bash | zsh | ksh | csh | tcsh) rc="~/.${shell}rc" ;;
    sh | dash) rc='~/.profile' ;;
    fish) rc='~/.config/fish/config.fish' ;;
    *) hub::die "hub alias: unsupported shell: $shell (supported: bash, zsh, sh, ksh, dash, fish, csh, tcsh)" ;;
  esac
  if ((script)); then
    if [[ $shell == *csh ]]; then printf 'alias git hub\n'; else printf 'alias git=hub\n'; fi
    return 0
  fi
  case $shell in
    *csh) line="eval \"\`hub alias -s $shell\`\"" ;;
    fish) line="hub alias -s fish | source" ;;
    *) line="eval \"\$(hub alias -s $shell)\"" ;;
  esac
  printf '# Make git run hub: add this line to %s, after the lines that set up PATH\n%s\n' "$rc" "$line"
}
