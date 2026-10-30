# shellcheck shell=bash
# Summary: Create a GitHub repository for the current project and add it as a remote.
# Usage: hub create [--public | -p | --private | --internal] [-d DESC] [-h URL] [--remote-name NAME] [-o] [-c] [[ORG/]NAME]
#
# Creates the repository from the current work tree with `gh repo create --source=.` and adds it
# as the remote "origin" (or NAME). It is named after the top directory unless NAME is given, and
# is private unless --public is. hub stops before creating anything when that remote exists.
# Other gh repo create options go to gh (give their values as --option=VALUE), except those that
# gh refuses with --source.
#
# Options:
#   --public                Make the repository public.
#   -p, --private           Make the repository private (the default).
#   --internal              Make an organization repository internal.
#   -d, --description DESC  The repository description.
#   -h, --homepage URL      The repository home page.
#   --remote-name NAME      Name the remote NAME; gh's -r, --remote NAME is the same.
#   -o, --browse            Open the new repository in the browser.
#   -c, --copy              Copy the new repository's URL to the clipboard (not gh's --clone).
#   --push                  Push the current branch to the new repository.
#
#   $ hub create --public -d 'My dotfiles' myorg/dotfiles
#   > gh repo create myorg/dotfiles --source=. --remote=origin --public -d My\ dotfiles

hub_cmd_create() {
  local visibility=--private remote=origin browse=0 copy=0 name='' top url='' opt
  local -a opts=()
  while (($#)); do
    case $1 in
      --public | --internal) visibility=$1 ;;
      -p | --private) visibility=--private ;;
      -d | --description | -h | --homepage)
        (($# >= 2)) || hub::die "hub create: $1 needs a value"
        opts+=("$1" "$2")
        shift
        ;;
      --remote-name | -r | --remote) # gh's -r too: the remote checked must be the one gh adds
        (($# >= 2)) || hub::die "hub create: $1 needs a value"
        remote=$2
        shift
        ;;
      --remote-name=* | --remote=*) remote=${1#*=} ;;
      -r=?*) remote=${1:3} ;; # gh reads -X=VALUE as -X VALUE
      -r?*) remote=${1:2} ;;
      -o | --browse) browse=1 ;;
      -c | --copy) copy=1 ;;
      --help) hub::usage ;;
      -[sgl]* | --source* | --clone* | --template* | --include-all-branches* | --gitignore* | --license* | --add-readme*)
        opt=${1%%=*}
        [[ $opt == --* ]] || opt=${opt:0:2}
        hub::die "Aborted: $opt can't be used with hub create, which makes the repository from the current work tree (gh repo create --source=.)."
        ;;
      -*) opts+=("$1") ;;
      *)
        [[ -z $name ]] || hub::die "Usage: hub create [--public] [-d DESC] [-h URL] [--remote-name NAME] [-o] [-c] [[ORG/]NAME]"
        name=$1
        ;;
    esac
    shift
  done
  [[ -n $remote ]] || hub::die "hub create: --remote-name needs a value"
  hub::require_repo
  top=$(hub::git_query rev-parse --show-toplevel)
  if hub::git_query remote get-url "$remote" >/dev/null; then
    hub::die "Aborted: a remote named '$remote' already exists; pick another name with --remote-name NAME."
  fi
  if ((browse || copy)); then url=$(_hub_create_url "$name" "${top##*/}") || exit 1; fi
  cd "$top" || exit 1 # gh repo create --source=. only takes the top of the work tree
  hub::gh repo create ${name:+"$name"} --source=. --remote="$remote" "$visibility" "${opts[@]}" || exit
  if ((copy)); then hub::copy "$url"; fi
  if ((browse)); then hub::open_url "$url"; fi
}

_hub_create_url() { # [[HOST/]OWNER/]NAME DIRNAME
  local name=$1 host owner
  case $name in
    */*/*) host=${name%%/*} name=${name#*/} ;;
    *) host=$(hub::host) ;;
  esac
  case $name in
    */*) owner=${name%%/*} name=${name#*/} ;;
    *) owner=$(hub::current_user "$host") || exit 1 ;;
  esac
  name=$(LC_ALL=C sed -E 's/[^A-Za-z0-9_.-]+/-/g' <<<"${name:-$2}") # as GitHub (and gh) name it
  printf 'https://%s/%s/%s\n' "$host" "$owner" "${name%.git}"
}
