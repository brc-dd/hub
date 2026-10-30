# shellcheck shell=bash
# Summary: List, view, create, edit and download releases (gh release).
# Usage: hub release [-R REPO] [SUBCOMMAND] [gh release options]
#
#   hub release [OPTIONS]               gh release list [OPTIONS]
#   hub release show TAG                gh release view TAG
#   hub release create TAG -a FILE      gh release create TAG FILE
#   hub release edit TAG -a FILE        gh release upload TAG FILE, after any other edit
#   hub release download TAG -i GLOB    gh release download TAG -p GLOB
#
# Options for create and edit:
#   -a, --attach FILE[#LABEL]   Upload FILE, or the files a quoted glob matches; repeat for more.
#   --clobber                   edit -a: replace assets of the same name (gh deletes them first).
#   -m, --message MESSAGE       The title, then the notes after a blank line; repeat to add paragraphs.
#   -F, --file FILE             The same as -m, read from FILE ("-" for standard input).
#   -t, --commitish REF         gh's --target REF.
#   -d, -p                      Draft and prerelease (--draft and --prerelease for edit).
#
# gh's own -t and -F are --title and --notes-file. hub checks every -a file before it runs gh.
# create sends empty notes rather than let gh prompt; edit leaves out an empty title or notes.
# Other subcommands and options go to gh unchanged.
#
#   $ hub release edit v1.2.0 -m "Version 1.2" -a dist/app.tgz
#   > gh release edit v1.2.0 --title "Version 1.2"
#   > gh release upload v1.2.0 dist/app.tgz

hub_cmd_release() {
  case ${1-} in -h | --help) hub::usage ;; esac
  local -a repo=()
  local n
  while [[ ${1-} == -R* || ${1-} == --repo || ${1-} == --repo=* ]]; do # gh takes -R before the subcommand too
    n=1
    [[ $1 != -R && $1 != --repo ]] || n=2
    (($# >= n)) || break
    repo+=("${@:1:n}")
    shift "$n"
  done
  [[ ${1--} == -* ]] && set -- list "$@"
  local sub=$1
  shift
  case $sub in
    show) hub::exec_gh release view "${repo[@]}" "$@" ;;
    create | edit | download) "_hub_release_$sub" "${repo[@]}" "$@" ;;
    *) hub::exec_gh release "$sub" "${repo[@]}" "$@" ;;
  esac
}

_hub_release_create() {
  local -a args=() assets=() messages=() title=()
  local opt val n file='' at='' notes=1 tag=0
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        args+=("$@")
        (($# == 1)) || tag=1
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[aFmt]=?*) opt=${1:0:2} val=${1:3} ;; # gh reads -X=VALUE as -X VALUE
      -[aFmntR]?*) opt=${1:0:2} val=${1:2} ;;
      -[aFmntR] | --attach | --message | --file | --commitish | --notes | --notes-file | --notes-start-tag | \
        --target | --title | --discussion-category | --repo)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        val=$2 n=2
        ;;
    esac
    case $opt in
      -h | --help) hub::usage ;;
      -a | --attach) assets+=("$val") ;;
      -m | --message) messages+=("$val") at=${at:-${#args[@]}} ;;
      -F | --file) file=$val at=${at:-${#args[@]}} ;;
      -t | --commitish) args+=(--target "$val") ;;
      -n | --notes | --notes-file | --generate-notes | --notes-from-tag) notes=0 args+=("${@:1:n}") ;;
      -?*) args+=("${@:1:n}") ;;
      *) tag=1 args+=("$1") ;;
    esac
    shift "$n"
  done
  # Without a TAG, gh would take the first file for it.
  ((tag || ! ${#assets[@]})) || hub::die "Usage: hub release create TAG [-a FILE]... [gh release create options]"
  _hub_release_check_assets "${assets[@]}"
  if [[ -n $at ]]; then
    hub::message "$file" "${messages[@]}"
    title=(--title "$HUB_MSG_TITLE")
    if [[ -n $HUB_MSG_BODY ]] || ((notes)); then title+=(--notes "$HUB_MSG_BODY"); fi
    args=("${args[@]:0:at}" "${title[@]}" "${args[@]:at}")
  fi
  hub::exec_gh release create "${args[@]}" "${assets[@]}"
}

_hub_release_edit() {
  local -a args=() assets=() messages=() title=() repo=() clobber=()
  local opt val n file='' at='' tag='' new_tag=''
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[aFmt]=?*) opt=${1:0:2} val=${1:3} ;; # gh reads -X=VALUE as -X VALUE
      -[aFmntR]?*) opt=${1:0:2} val=${1:2} ;;
      -[aFmntR] | --attach | --message | --file | --commitish | --notes | --notes-file | --tag | --target | --title | \
        --discussion-category | --repo)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        val=$2 n=2
        ;;
    esac
    case $opt in
      -h | --help) hub::usage ;;
      -a | --attach) assets+=("$val") ;;
      --clobber) clobber=("$1") ;;
      -m | --message) messages+=("$val") at=${at:-${#args[@]}} ;;
      -F | --file) file=$val at=${at:-${#args[@]}} ;;
      -t | --commitish) args+=(--target "$val") ;;
      -d) args+=(--draft) ;;
      -p) args+=(--prerelease) ;;
      -R | --repo) repo+=("${@:1:n}") args+=("${@:1:n}") ;;
      --tag) new_tag=$val args+=("${@:1:n}") ;;
      -?*) args+=("${@:1:n}") ;;
      *) tag=${tag:-$1} args+=("$1") ;;
    esac
    shift "$n"
  done
  if [[ -n $at ]]; then
    hub::message "$file" "${messages[@]}"
    [[ -z $HUB_MSG_TITLE ]] || title+=(--title "$HUB_MSG_TITLE")
    [[ -z $HUB_MSG_BODY ]] || title+=(--notes "$HUB_MSG_BODY")
    args=("${args[@]:0:at}" "${title[@]}" "${args[@]:at}")
  fi
  ((${#assets[@]})) || hub::exec_gh release edit "${args[@]}" "${clobber[@]}"
  [[ -n $tag ]] || hub::die "Usage: hub release edit TAG [-a FILE]... [--clobber] [gh release edit options]"
  _hub_release_check_assets "${assets[@]}"
  # Edit first when there is more to change than the TAG and -R name.
  if ((${#args[@]} > ${#repo[@]} + 1)); then hub::gh release edit "${args[@]}" || exit; fi
  hub::exec_gh release upload "${new_tag:-$tag}" "${assets[@]}" "${clobber[@]}" "${repo[@]}"
}

_hub_release_check_assets() {
  local asset file bad=''
  local -a files
  for asset; do
    if [[ $asset == *'#'* ]]; then # FILE#LABEL, as gh splits it: FILE is taken literally
      file=${asset%%#*}
      files=("${file:-$asset}")
    else # a glob pattern, which gh expands, dotfiles included
      mapfile -t files < <(shopt -s dotglob && compgen -G "$asset")
      ((${#files[@]})) || files=("$asset")
    fi
    for file in "${files[@]}"; do
      [[ -f $file && -r $file ]] || bad+="${bad:+, }$(hub::quote "$file")"
    done
  done
  [[ -z $bad ]] || hub::die "Aborted: cannot read $bad"
}

_hub_release_download() {
  local -a args=()
  while (($#)); do
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      -h | --help) hub::usage ;;
      -i | --include)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        args+=(-p "$2")
        shift
        ;;
      -i=?*) args+=(-p "${1:3}") ;; # gh reads -X=VALUE as -X VALUE
      -i?*) args+=(-p "${1:2}") ;;
      --include=*) args+=(-p "${1#*=}") ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  hub::exec_gh release download "${args[@]}"
}
