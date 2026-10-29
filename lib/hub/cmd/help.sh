# shellcheck shell=bash
# Summary: Show help for hub and the commands it adds to git.
# Usage: hub help [COMMAND]
#
# Without arguments, prints git's usage followed by the list of hub commands.
# With a COMMAND that hub provides or extends, prints that command's manual
# (the comment block at the top of its module). Anything else goes to `git help`.

hub_cmd_help() {
  local topic=${1-} file
  if [[ -n $topic ]]; then
    for file in "$HUB_LIB/cmd/$topic.sh" "$HUB_LIB/ext/$topic.sh"; do
      [[ -f $file ]] || continue
      hub::module_doc "$file"
      return 0
    done
    hub::exec_git help "$@"
  fi
  "$HUB_GIT" help 2>&1 || true
  printf '\nGitHub commands provided or extended by hub (hub help <command> for details):\n\n'
  hub::list_commands
}

# hub::list_commands : one line per module, from each module's "# Summary:" line.
hub::list_commands() {
  local file name summary group
  for group in ext cmd; do
    case $group in
      ext) printf '  Extended git commands:\n' ;;
      cmd) printf '\n  New commands:\n' ;;
    esac
    for file in "$HUB_LIB/$group"/*.sh; do
      [[ -f $file ]] || continue
      name=$(basename "$file" .sh)
      summary=$(sed -n 's/^# Summary: //p' "$file" | head -n 1)
      printf '    %-14s %s\n' "$name" "$summary"
    done
  done
}
