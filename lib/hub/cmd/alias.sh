# shellcheck shell=bash
# Summary: Show how to make git run hub.
# Usage: hub alias [-s] [SHELL]
#
# hub's own command: these are all of its options. Prints the line that makes the interactive
# shell run hub for git, and the startup file it goes in. SHELL defaults to the name of $SHELL:
# bash, zsh, sh, ksh, dash, fish, csh or tcsh. Nothing is written anywhere.
#
# Options:
#   -s   Print only the alias, for eval.
#
#   $ hub alias zsh
#   # Add this line to ~/.zshrc, after the lines that set up PATH:
#   eval "$(hub alias -s zsh)"
#   $ hub alias -s zsh
#   alias git=hub

hub_cmd_alias() {
  local script=0 rc alias='alias git=hub' line
  local -a shells=()
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -s) script=1 ;;
      -h | --help) hub::usage ;;
      --) shift && shells+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $(hub::shown "$1")" ;;
      *) shells+=("$1") ;;
    esac
    shift
  done
  ((${#shells[@]} <= 1)) || hub::usage_error "unexpected argument: $(hub::shown "${shells[1]}")"
  set -- "${shells[0]:-${SHELL##*/}}"
  [[ -n $1 ]] || hub::die 'cannot tell your shell from SHELL (name it: hub alias SHELL)'
  line="eval \"\$(hub alias -s $1)\""
  # shellcheck disable=SC2088  # the ~ is for the reader
  case $1 in
    bash | zsh | ksh) rc="~/.${1}rc" ;;
    sh | dash) rc='~/.profile' ;;
    fish) rc='~/.config/fish/config.fish' line='hub alias -s fish | source' ;;
    csh | tcsh) rc="~/.${1}rc" alias='alias git hub' line="eval \"\`hub alias -s $1\`\"" ;;
    *)
      local known='bash, zsh, sh, ksh, dash, fish, csh, tcsh'
      hub::die "unsupported shell: $(hub::shown "$1") (use one of $known)"
      ;;
  esac
  if ((script)); then
    printf '%s\n' "$alias"
  else
    printf '# Add this line to %s, after the lines that set up PATH:\n%s\n' "$rc" "$line"
  fi
}
