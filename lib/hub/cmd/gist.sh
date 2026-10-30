# shellcheck shell=bash
# Summary: Create and view gists (gh gist).
# Usage: hub gist create [--public] [-o] [FILE...] [gh gist create options]
#        hub gist show ID [FILENAME] [gh gist view options]
#        hub gist SUBCOMMAND [gh gist options]
#
#   hub gist create --public        gh gist create -p
#   hub gist create -o, --browse    gh gist create -w
#   hub gist show ID [FILENAME]     gh gist view ID --raw [--filename FILENAME]
#
# Without FILEs, create reads standard input. Other subcommands and options go to gh unchanged.
#
#   $ hub gist show 8f3c4e2 notes.md
#   > gh gist view 8f3c4e2 --raw --filename notes.md

hub_cmd_gist() {
  case ${1-} in '' | -h | --help) hub::usage ;; esac
  local sub=$1
  shift
  case $sub in
    create) _hub_gist_create "$@" ;;
    show) _hub_gist_show "$@" ;;
    *) hub::exec_gh gist "$sub" "$@" ;;
  esac
}

_hub_gist_create() {
  local -a args=()
  while (($#)); do
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      -h | --help) hub::usage ;;
      --public) args+=(-p) ;;
      -o | --browse) args+=(-w) ;;
      -d | -f | --desc | --filename)
        args+=("$1")
        shift
        (($#)) || break
        args+=("$1")
        ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  hub::exec_gh gist create "${args[@]}"
}

_hub_gist_show() {
  local -a words=() opts=()
  while (($#)); do
    case $1 in
      --)
        shift
        words+=("$@")
        break
        ;;
      -h | --help) hub::usage ;;
      -f | --filename)
        opts+=("$1")
        shift
        (($#)) || break
        opts+=("$1")
        ;;
      -?*) opts+=("$1") ;;
      *) words+=("$1") ;;
    esac
    shift
  done
  local -a cmd=(gist view "${words[@]:0:1}" --raw)
  ((${#words[@]} > 1)) && cmd+=(--filename "${words[1]}")
  hub::exec_gh "${cmd[@]}" "${opts[@]}" "${words[@]:2}"
}
