# shellcheck shell=bash
# Summary: Delete a repository on GitHub.
# Usage: hub delete [-y] [OWNER/]NAME
#
# Deletes the repository with `gh repo delete`, which asks you to type its name first unless -y
# is given. A bare NAME is yours (your login on the default host); OWNER/NAME, HOST/OWNER/NAME
# and a repository URL are passed to gh as they are. Deleting needs the delete_repo scope; grant
# it once with `gh auth refresh -s delete_repo`. The exit status is gh's.
#
# Options:
#   -y, --yes   Delete without asking for confirmation.
#
#   $ hub delete -y dotfiles
#   > gh repo delete mislav/dotfiles --yes

hub_cmd_delete() {
  local proj
  local -a names=() yes=()
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -y | --yes) yes=(--yes) ;;
      -h | --help) hub::usage ;;
      --)
        shift
        names+=("$@")
        break
        ;;
      -?*) _hub_delete_usage_error "unknown option: $1" ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  ((${#names[@]} == 1)) || _hub_delete_usage_error "name one repository"
  if [[ ${names[0]} == */* ]]; then
    hub::parse_project "${names[0]}" || _hub_delete_usage_error "not a repository: ${names[0]}"
    proj=${names[0]}
  else
    hub::is_project_name "${names[0]}" || _hub_delete_usage_error "not a repository name: ${names[0]}"
    proj=$(hub::expand_project "${names[0]}") || exit 1
  fi
  hub::exec_gh repo delete "$proj" "${yes[@]}"
}

_hub_delete_usage_error() {
  hub::die "hub delete: $1"$'\n'"Usage: hub delete [-y] [OWNER/]NAME"
}
