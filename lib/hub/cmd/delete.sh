# shellcheck shell=bash
# Summary: Delete a repository on GitHub.
# Usage: hub delete [-y] [OWNER/]NAME
#
# Deletes the GitHub repository OWNER/NAME with `gh repo delete`; a bare NAME
# means your own repository, and HOST/OWNER/NAME names the host (otherwise it
# is gh's default host: GH_HOST, which hub sets from old hub's GITHUB_HOST).
# gh asks you to type the repository name to confirm unless -y is given.
# Local clones and remotes are not touched.
#
# Deleting needs the delete_repo scope, which `gh auth login` does not ask
# for. Grant it once with:
#
#   gh auth refresh -s delete_repo
#
# Options:
#   -y, --yes   Delete without asking for confirmation.
#
#   $ hub delete -y dotfiles
#   > gh repo delete mislav/dotfiles --yes

hub_cmd_delete() {
  local name='' proj
  local -a flags=()
  while (($#)); do
    case $1 in
      -y | --yes) flags=(--yes) ;;
      -h | --help) hub::usage ;;
      -*) hub::die "hub delete: unknown option: $1" ;;
      *)
        [[ -z $name ]] || hub::die "Usage: hub delete [-y] [OWNER/]NAME"
        name=$1
        ;;
    esac
    shift
  done
  [[ -n $name ]] || hub::die "Usage: hub delete [-y] [OWNER/]NAME"
  proj=$(hub::expand_project "$name") || exit 1
  hub::exec_gh repo delete "$proj" "${flags[@]}"
}
