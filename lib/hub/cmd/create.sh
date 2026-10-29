# shellcheck shell=bash
# Summary: Create a GitHub repository for the current project and add it as a remote.
# Usage: hub create [--public | -p | --private | --internal] [-d DESC] [-h URL] [--remote-name NAME] [-o] [[ORG/]NAME]
#
# Creates the repository on GitHub with `gh repo create --source=.` and adds it
# as the remote "origin" (or NAME). The repository is named after the top
# directory of the work tree unless NAME is given; ORG/NAME creates it in an
# organization. hub must run inside the work tree, and stops before creating
# anything when the remote already exists.
#
# New repositories are PRIVATE unless --public is given. (Old hub made them
# public by default; -p/--private is still accepted and is the default.)
#
# Nothing is pushed unless you add --push. Other `gh repo create` options are
# passed through; give their values as --option=VALUE (--license=mit).
#
# Options:
#       --public            Make the repository public.
#   -p, --private           Make the repository private (the default).
#       --internal          Make an organization repository internal.
#   -d, --description DESC  The repository description.
#   -h, --homepage URL      The repository home page.
#       --remote-name NAME  Name of the remote to add (default: origin).
#   -o, --browse            Open the new repository in the browser.
#       --push              Push the current branch to the new repository.
#
#   $ hub create
#   > gh repo create --source=. --remote=origin --private
#   $ hub create --public -d 'My dotfiles' myorg/dotfiles
#   > gh repo create myorg/dotfiles --source=. --remote=origin --public -d My\ dotfiles

hub_cmd_create() {
  local visibility=--private remote=origin browse=0 name='' top url=''
  local -a opts=() extra=()
  while (($#)); do
    case $1 in
      --public) visibility=--public ;;
      -p | --private) visibility=--private ;;
      --internal) visibility=--internal ;;
      -d | --description)
        (($# >= 2)) || hub::die "hub create: $1 needs a value"
        opts+=(-d "$2")
        shift
        ;;
      --description=*) opts+=(-d "${1#*=}") ;;
      -h | --homepage)
        (($# >= 2)) || hub::die "hub create: $1 needs a value"
        opts+=(-h "$2")
        shift
        ;;
      --homepage=*) opts+=(-h "${1#*=}") ;;
      --remote-name)
        (($# >= 2)) || hub::die "hub create: $1 needs a value"
        remote=$2
        shift
        ;;
      --remote-name=*) remote=${1#*=} ;;
      -o | --browse) browse=1 ;;
      --help) hub::usage ;;
      -*) extra+=("$1") ;;
      *)
        [[ -z $name ]] || hub::die "Usage: hub create [--public] [-d DESC] [-h URL] [--remote-name NAME] [-o] [[ORG/]NAME]"
        name=$1
        ;;
    esac
    shift
  done
  [[ -n $remote ]] || hub::die "hub create: --remote-name needs a value"

  hub::require_repo
  top=$(hub::git_query rev-parse --show-toplevel) || hub::die "Aborted: could not find the top of the work tree."
  if hub::git_query remote get-url "$remote" >/dev/null; then
    hub::die "Aborted: a remote named '$remote' already exists; pick another name with --remote-name NAME."
  fi
  if ((browse)); then url=$(_hub_create_url "$name" "$top") || exit 1; fi

  # `gh repo create --source=.` only accepts the top of the work tree.
  cd "$top" || exit 1
  hub::gh repo create ${name:+"$name"} --source=. --remote="$remote" "$visibility" "${opts[@]}" "${extra[@]}" || exit
  if ((browse)); then hub::open_url "$url"; fi
}

# _hub_create_url [[HOST/]OWNER/]NAME TOPDIR : web URL of the repository gh creates for NAME.
_hub_create_url() {
  local name=$1 host owner
  case $name in
    */*/*) host=${name%%/*} name=${name#*/} ;;
    *) host=$(hub::host) ;;
  esac
  case $name in
    */*) owner=${name%%/*} name=${name#*/} ;;
    *) owner=$(hub::current_user "$host") || exit 1 ;;
  esac
  [[ -n $name ]] || name=${2##*/}
  # Like GitHub (and gh), turn anything but letters, digits, '_', '.' and '-' into '-'.
  name=$(LC_ALL=C sed -E 's/[^A-Za-z0-9_.-]+/-/g' <<<"$name")
  printf 'https://%s/%s/%s\n' "$host" "$owner" "${name%.git}"
}
