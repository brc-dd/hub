# shellcheck shell=bash
# Summary: Create a GitHub repository for the current project and add it as a remote.
# Usage: hub create [--public | -p | --private | --internal] [-d DESC] [-h URL] [--remote-name NAME] [-o] [-c] [[ORG/]NAME]
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
# Nothing is pushed unless you add --push. Other `gh repo create` options, such
# as --disable-wiki or --team=SLUG, are passed through; give their values as
# --option=VALUE. hub passes --source=. and --remote itself, and stops on the
# options that do not work with --source: --clone, --template,
# --include-all-branches, --gitignore, --license and --add-readme. (Commit a
# README, LICENSE or .gitignore before running hub create instead.)
#
# Options:
#       --public            Make the repository public.
#   -p, --private           Make the repository private (the default).
#       --internal          Make an organization repository internal.
#   -d, --description DESC  The repository description.
#   -h, --homepage URL      The repository home page.
#       --remote-name NAME  Name of the remote to add (default: origin).
#                           gh's -r/--remote NAME means the same.
#   -o, --browse            Open the new repository in the browser.
#   -c, --copy              Copy the URL of the new repository to the clipboard
#                           (as in old hub; this is not gh's -c, --clone).
#       --push              Push the current branch to the new repository.
#
#   $ hub create
#   > gh repo create --source=. --remote=origin --private
#   $ hub create --public -d 'My dotfiles' myorg/dotfiles
#   > gh repo create myorg/dotfiles --source=. --remote=origin --public -d My\ dotfiles

hub_cmd_create() {
  local visibility=--private remote=origin browse=0 copy=0 name='' top url='' opt
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
      # gh's own -r/--remote is taken here too, so that the check below looks at the remote gh adds.
      --remote-name | -r | --remote)
        (($# >= 2)) || hub::die "hub create: $1 needs a value"
        remote=$2
        shift
        ;;
      --remote-name=* | --remote=*) remote=${1#*=} ;;
      -r?*)
        remote=${1#-r}
        remote=${remote#=}
        ;;
      -o | --browse) browse=1 ;;
      -c | --copy) copy=1 ;;
      --help) hub::usage ;;
      -s* | --source | --source=*)
        hub::die "Aborted: hub create always makes the repository from the current work tree (--source=.); to publish another one, run hub -C PATH create."
        ;;
      --clone | --clone=* | --template | --template=* | --include-all-branches | --include-all-branches=* | \
        -g* | --gitignore | --gitignore=* | -l* | --license | --license=* | --add-readme | --add-readme=*)
        opt=${1%%=*}
        [[ $opt == --* ]] || opt=${opt:0:2}
        hub::die "Aborted: $opt can't be used with hub create, which makes the repository from your local commits (gh repo create --source=.). Commit a README, LICENSE or .gitignore instead, or use gh repo create directly to clone or to start from a template."
        ;;
      -*) extra+=("$1") ;;
      *)
        [[ -z $name ]] || hub::die "Usage: hub create [--public] [-d DESC] [-h URL] [--remote-name NAME] [-o] [-c] [[ORG/]NAME]"
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
  if ((browse || copy)); then url=$(_hub_create_url "$name" "$top") || exit 1; fi

  # `gh repo create --source=.` only accepts the top of the work tree.
  cd "$top" || exit 1
  hub::gh repo create ${name:+"$name"} --source=. --remote="$remote" "$visibility" "${opts[@]}" "${extra[@]}" || exit
  if ((copy)); then hub::copy "$url"; fi
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
