# shellcheck shell=bash
# Summary: Show help for hub and the commands it adds to git.
# Usage: hub help [COMMAND]
#
# Without arguments, prints git's usage and the list of hub's commands. With a COMMAND that hub
# provides or extends, prints its manual; with any other, runs `git help COMMAND`.

hub_cmd_help() {
  local file group name
  if [[ -n ${1-} ]]; then
    for file in "$HUB_LIB/cmd/$1.sh" "$HUB_LIB/ext/$1.sh"; do
      [[ -f $file ]] || continue
      hub::module_doc "$file"
      return 0
    done
    hub::exec_git help "$@"
  fi
  git help 2>&1 || true
  printf '\nGitHub commands provided or extended by hub, https://github.com/brc-dd/hub (hub help <command> for details):\n\n'
  for group in ext cmd; do
    if [[ $group == ext ]]; then printf '\n  Extended git commands:\n'; else printf '\n  New commands:\n'; fi
    for file in "$HUB_LIB/$group"/*.sh; do
      name=${file##*/}
      printf '    %-14s %s\n' "${name%.sh}" "$(sed -n 's/^# Summary: //p' "$file" | head -n 1)"
    done
  done
}
