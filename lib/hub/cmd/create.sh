# shellcheck shell=bash
# Summary: Create a GitHub repository for this repository and add it as a remote.
# Usage: hub create [-p | --public | --internal] [-d DESCRIPTION] [-h HOMEPAGE]
#                   [--remote-name NAME] [--push] [-o] [-c] [[[HOST/]OWNER/]NAME]
#
# hub's own command: these are all of its options. Creates the repository on GitHub with gh repo
# create from the top of the work tree and adds it as the remote origin. The repository is
# private unless --public or --internal says otherwise, named after the project or the top
# directory unless NAME is given (a .git suffix is dropped), owned by you unless OWNER/NAME names
# an organization, and created on the default host (GH_HOST, else gh's only host) unless
# HOST/OWNER/NAME or a repository URL names one. The remote's URL follows gh's git_protocol. The
# name, the remote and, with --push, the current branch are checked before gh runs.
#
# Options:
#   -p, --private                  Make the repository private (the default).
#       --public                   Make it public.
#       --internal                 Make it visible to its organization only.
#   -d, --description DESCRIPTION  The repository's description.
#   -h, --homepage HOMEPAGE        The repository's home page URL.
#       --remote-name NAME         Name the remote NAME instead of origin.
#       --push                     Push the current branch there and track it.
#   -o, --browse                   Open https://HOST/OWNER/NAME in the browser.
#   -c, --copy                     Copy that URL to the clipboard.
#
#   $ hub create --public --push dotfiles
#   > gh repo create github.com/LOGIN/dotfiles --source=TOP --remote=origin --public
#   > git push --set-upstream origin HEAD

hub_cmd_create() {
  local visibility=--private description='' homepage='' remote=origin push=0 browse=0 copy=0
  local top host owner='' repo url current branch rc=0
  local -a operands=() cmd
  hub::normalize_opts dh '--description --homepage --remote-name' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -p | --private) visibility=--private ;;
      --public | --internal) visibility=$1 ;;
      -d | --description | -h | --homepage | --remote-name)
        (($# >= 2)) || hub::usage_error "$1 needs a value"
        case $1 in
          -d | --description) description=$2 ;;
          -h | --homepage) homepage=$2 ;;
          *) remote=$2 ;;
        esac
        shift
        ;;
      --push) push=1 ;;
      -o | --browse) browse=1 ;;
      -c | --copy) copy=1 ;;
      --help) hub::usage ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $1" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} <= 1)) || hub::usage_error "unexpected argument: ${operands[1]}"

  hub::require_gh
  hub::require_repo
  top=$(hub::toplevel)
  if ((${#operands[@]} == 0)); then
    host=$(hub::host) && repo=$(hub::repo_name) || exit 1
  else
    # The default host first: a bad GH_HOST is the only message.
    host=$(hub::host) || exit 1
    if [[ ${operands[0]} == */* ]]; then
      read -r host owner repo < <(hub::parse_project "${operands[0]}")
    else
      repo=${operands[0]%.git}
    fi
  fi
  if ! hub::is_shorthand "$repo"; then
    hub::die "not a repository: $(hub::shown "${operands[0]-$repo}")" \
      '(use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)'
  fi
  hub::require_new_remote "$remote"
  if ((push)); then
    branch=$(hub::current_branch) || hub::die 'not on a branch (--push pushes the current branch)'
    git rev-parse --verify --quiet HEAD >/dev/null \
      || hub::die "$branch has no commits to push (commit first, or leave out --push)"
  fi
  [[ -n $owner ]] || owner=$(hub::login "$host") || exit 1
  url=$(hub::clone_url "$host" "$owner" "$repo")

  cmd=(repo create "$host/$owner/$repo" --source="$top" --remote="$remote" "$visibility")
  [[ -z $description ]] || cmd+=(--description "$description")
  [[ -z $homepage ]] || cmd+=(--homepage "$homepage")
  hub::gh "${cmd[@]}" || exit
  if current=$(hub::git_query remote get-url -- "$remote") && [[ $current != "$url" ]]; then
    hub::git remote set-url -- "$remote" "$url" || exit
  fi
  # Not gh's --push: from some layouts it mirrors every ref.
  if ((push)); then hub::git push --set-upstream "$remote" HEAD || exit; fi
  url=https://$host/$owner/$repo
  # Subshells, so that a missing clipboard tool or browser does not cancel the other action.
  if ((copy)); then (hub::copy "$url") || rc=$?; fi
  if ((browse)); then (hub::open_url "$url") || rc=$?; fi
  return "$rc"
}
