# shellcheck shell=bash
# Summary: Delete a repository on GitHub.
# Usage: hub delete [-y] [OWNER/]NAME
#
# Deletes the repository with `gh repo delete`; a bare NAME is yours, and HOST/OWNER/NAME names
# the host. gh asks you to type the name to confirm unless -y is given. Deleting needs the
# delete_repo scope; grant it once with `gh auth refresh -s delete_repo`.
#
# Options:
#   -y, --yes   Delete without asking for confirmation.
#
#   $ hub delete -y dotfiles
#   > gh repo delete mislav/dotfiles --yes

hub_cmd_delete() {
  local proj
  local -a names=() yes=()
  while (($#)); do
    case $1 in
      -y | --yes) yes=(--yes) ;;
      -h | --help) hub::usage ;;
      -*) hub::die "hub delete: unknown option: $1" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  ((${#names[@]} == 1)) || hub::die "Usage: hub delete [-y] [OWNER/]NAME"
  proj=$(hub::expand_project "${names[0]}") || exit 1
  hub::exec_gh repo delete "$proj" "${yes[@]}"
}
