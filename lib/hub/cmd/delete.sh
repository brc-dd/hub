# shellcheck shell=bash
# Summary: Delete a repository on GitHub.
# Usage: hub delete [-y] [[HOST/]OWNER/]NAME
#
# hub's own command: these are all of its options. Deletes the repository with gh repo delete,
# which asks you to type its name first unless -y is given. A bare NAME is yours: your login on
# the default host. NAME may also be a repository URL. Deleting needs the delete_repo scope;
# grant it once with `gh auth refresh -s delete_repo`. The exit status is gh's.
#
# Options:
#   -y, --yes   Delete without asking for confirmation.
#
#   $ hub delete -y dotfiles
#   > gh repo delete github.com/mislav/dotfiles --yes
#   $ hub delete octo-org/old-site
#   > gh repo delete github.com/octo-org/old-site

hub_cmd_delete() {
  local host owner='' repo=''
  local -a operands=() yes=()
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -y | --yes) yes=(--yes) ;;
      -h | --help) hub::usage ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $1" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} > 0)) || hub::usage_error 'name the repository to delete'
  ((${#operands[@]} == 1)) || hub::usage_error "unexpected argument: ${operands[1]}"
  if [[ ${operands[0]} == */* ]]; then
    read -r host owner repo < <(hub::parse_project "${operands[0]}")
  elif hub::is_shorthand "${operands[0]%.git}"; then
    host=$(hub::host) || exit 1
    repo=${operands[0]%.git}
  fi
  if [[ -z $repo ]]; then
    hub::die "not a repository: ${operands[0]}" \
      '(use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)'
  fi
  [[ -n $owner ]] || owner=$(hub::login "$host") || exit 1
  hub::exec_gh repo delete "$host/$owner/$repo" "${yes[@]}"
}
