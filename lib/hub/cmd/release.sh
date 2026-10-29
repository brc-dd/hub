# shellcheck shell=bash
# Summary: List, view, create, edit and download releases (gh release).
# Usage: hub release [SUBCOMMAND] [gh release options]
#
# Runs `gh release` with gh's own options and behaviour. hub only maps the old
# subcommand names and argument forms that gh doesn't have:
#
#   hub release [OPTIONS]           gh release list [OPTIONS]
#   hub release show TAG            gh release view TAG
#   hub release download TAG -i GLOB
#                                   gh release download TAG -p GLOB
#
# and, for create and edit, hub's options:
#
#   -a, --attach FILE[#LABEL]       Upload FILE as an asset; repeat for more.
#                                   create passes them to gh as asset arguments;
#                                   edit uploads them afterwards with
#                                   gh release upload TAG FILE... --clobber.
#   -m, --message MESSAGE           The first paragraph is the title and the rest
#                                   the notes (gh --title/--notes). Repeat -m to
#                                   add paragraphs. create sends empty notes when
#                                   there are none, so gh doesn't prompt; edit
#                                   leaves out an empty title or empty notes.
#   -F, --file FILE                 The same, read from FILE ("-" for stdin). gh's
#                                   notes-only -F is still there as --notes-file.
#   -t, --commitish REF             gh --target REF. gh's -t is still there as
#                                   --title.
#   -d, -p                          Draft and prerelease, as in gh; for edit, hub
#                                   spells them out as --draft and --prerelease.
#
# Everything else goes to gh unchanged: the other subcommands (delete, upload,
# delete-asset, verify, ...) and all other options, in order. See
# `gh release SUBCOMMAND --help` for them.
#
#   $ hub release create -d -m "v1.2.0" -a dist/app.tgz -a "dist/app.zip#Archive" v1.2.0
#   > gh release create -d --title v1.2.0 --notes "" v1.2.0 dist/app.tgz "dist/app.zip#Archive"
#
#   $ hub release edit v1.2.0 -m "Version 1.2" -a dist/app.tgz
#   > gh release edit v1.2.0 --title "Version 1.2"
#   > gh release upload v1.2.0 dist/app.tgz --clobber

hub_cmd_release() {
  case ${1-} in -h | --help) hub::usage ;; esac
  # Like gh, take -R/--repo before the subcommand word (hub release -R OWNER/REPO create ...).
  local -a repo=()
  while (($#)); do
    case $1 in
      -R | --repo)
        (($# > 1)) || break
        repo+=("$1" "$2")
        shift 2
        ;;
      -R?* | --repo=*)
        repo+=("$1")
        shift
        ;;
      *) break ;;
    esac
  done
  local sub=list
  if (($#)) && [[ $1 != -* ]]; then
    sub=$1
    shift
  fi
  case $sub in
    show) hub::exec_gh release view "${repo[@]}" "$@" ;;
    create) _hub_release_create "${repo[@]}" "$@" ;;
    edit) _hub_release_edit "${repo[@]}" "$@" ;;
    download) _hub_release_download "${repo[@]}" "$@" ;;
    *) hub::exec_gh release "$sub" "${repo[@]}" "$@" ;;
  esac
}

# _hub_release_create ARGS... : gh release create, with hub's -a, -m, -F and -t.
_hub_release_create() {
  local -a args=() assets=() messages=() title=()
  local opt val n file='' at=-1 has_notes=0 positionals=0
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        args+=("$@")
        positionals=$((positionals + $# - 1))
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
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
      -m | --message)
        messages+=("$val")
        ((at >= 0)) || at=${#args[@]}
        ;;
      -F | --file)
        file=$val
        ((at >= 0)) || at=${#args[@]}
        ;;
      -t | --commitish) args+=(--target "$val") ;;
      -n | --notes | --notes-file | --generate-notes | --notes-from-tag)
        has_notes=1
        args+=("${@:1:n}")
        ;;
      -?*) args+=("${@:1:n}") ;;
      *)
        positionals=$((positionals + 1))
        args+=("$1")
        ;;
    esac
    shift "$n"
  done
  if ((${#assets[@]} && ! positionals)); then # gh would take the first file for the tag
    hub::die "Usage: hub release create TAG [-a FILE]... [gh release create options]"
  fi
  if ((at >= 0)); then
    _hub_release_message "$file" "${messages[@]}"
    title=(--title "$HUB_MSG_TITLE")
    if [[ -n $HUB_MSG_BODY ]] || ((! has_notes)); then title+=(--notes "$HUB_MSG_BODY"); fi
    args=("${args[@]:0:at}" "${title[@]}" "${args[@]:at}")
  fi
  hub::exec_gh release create "${args[@]}" "${assets[@]}"
}

# _hub_release_edit ARGS... : gh release edit with hub's -m, -F, -t, -d and -p; then
# gh release upload --clobber for the -a files (alone, when nothing else is edited).
_hub_release_edit() {
  local -a args=() assets=() messages=() title=() repo=()
  local opt val n file='' at=-1 tag='' new_tag='' edits=0
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        args+=("$@")
        edits=1
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
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
      -m | --message)
        messages+=("$val")
        ((at >= 0)) || at=${#args[@]}
        ;;
      -F | --file)
        file=$val
        ((at >= 0)) || at=${#args[@]}
        ;;
      -t | --commitish)
        args+=(--target "$val")
        edits=1
        ;;
      -d)
        args+=(--draft)
        edits=1
        ;;
      -p)
        args+=(--prerelease)
        edits=1
        ;;
      -R | --repo)
        repo+=("${@:1:n}")
        args+=("${@:1:n}")
        ;;
      --tag)
        new_tag=$val
        args+=("${@:1:n}")
        edits=1
        ;;
      -?*)
        args+=("${@:1:n}")
        edits=1
        ;;
      *)
        if [[ -z $tag ]]; then tag=$1; else edits=1; fi
        args+=("$1")
        ;;
    esac
    shift "$n"
  done
  if ((at >= 0)); then
    _hub_release_message "$file" "${messages[@]}"
    [[ -z $HUB_MSG_TITLE ]] || title+=(--title "$HUB_MSG_TITLE")
    [[ -z $HUB_MSG_BODY ]] || title+=(--notes "$HUB_MSG_BODY")
    ((${#title[@]})) && edits=1
    args=("${args[@]:0:at}" "${title[@]}" "${args[@]:at}")
  fi
  ((${#assets[@]})) || hub::exec_gh release edit "${args[@]}"
  [[ -n $tag ]] || hub::die "Usage: hub release edit TAG [-a FILE]... [gh release edit options]"
  if ((edits)); then
    hub::gh release edit "${args[@]}" || exit
  fi
  hub::exec_gh release upload "${new_tag:-$tag}" "${assets[@]}" --clobber "${repo[@]}"
}

# _hub_release_download ARGS... : gh release download, with hub's -i/--include GLOB as -p GLOB.
_hub_release_download() {
  local -a args=()
  local opt val n
  while (($#)); do
    opt=$1 val='' n=1
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      --?*=*) opt=${1%%=*} val=${1#*=} ;;
      -[ADiOpR]?*) opt=${1:0:2} val=${1:2} ;;
      -[ADiOpR] | --include | --archive | --dir | --output | --pattern | --repo)
        (($# > 1)) || hub::die "Aborted: $1 needs a value."
        val=$2 n=2
        ;;
    esac
    case $opt in
      -h | --help) hub::usage ;;
      -i | --include) args+=(-p "$val") ;;
      *) args+=("${@:1:n}") ;;
    esac
    shift "$n"
  done
  hub::exec_gh release download "${args[@]}"
}

# _hub_release_message FILE [MESSAGE...] : set HUB_MSG_TITLE and HUB_MSG_BODY from the
# -m MESSAGEs (joined as paragraphs) or else from FILE ("-" reads standard input).
_hub_release_message() {
  local file=$1 text
  shift
  if [[ -n $file ]]; then
    (($# == 0)) || hub::die "Aborted: -m and -F cannot be used together."
    if [[ $file == - ]]; then
      text=$(cat)
    else
      [[ -r $file && ! -d $file ]] || hub::die "Aborted: cannot read $file"
      text=$(<"$file")
    fi
  else
    text=$(printf '%s\n\n' "$@")
  fi
  hub::split_message "$text"
}
