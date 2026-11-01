# shellcheck shell=bash
# Summary: Show git's help and hub's commands.
# Usage: hub help [COMMAND]
#        hub help GIT-HELP-ARGS...
#
# hub's own command: any other arguments go to git help. Without arguments, prints git's help,
# then the commands hub provides or extends. With one of them alone, prints its manual; for a git
# command hub extends, git NAME --help prints git's instead. Any other line is plain git help.
#
#   $ hub help pull-request
#   Summary: Open a pull request for the current branch.
#   $ hub help -a
#   > git help -a

hub_cmd_help() {
  local file name
  case ${1-} in
    -h | --help) hub::usage ;;
  esac
  if (($# == 1)) && [[ $1 =~ ^[a-z][a-z0-9-]*$ && -f $HUB_LIB/cmd/$1.sh ]]; then
    hub::module_doc "$HUB_LIB/cmd/$1.sh"
    return 0
  fi
  (($# == 0)) || hub::exec_git help "$@"
  git help
  printf '\nGitHub commands provided or extended by hub (hub help COMMAND for details):\n\n'
  for file in "$HUB_LIB"/cmd/*.sh; do
    name=${file##*/}
    printf '   %-14s %s\n' "${name%.sh}" "$(sed -n 's/^# Summary: //p' "$file")"
  done
}
