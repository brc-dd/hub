# shellcheck shell=bash
# Summary: Fetch from GitHub users' forks, adding remotes for them first.
# Usage: hub fetch USER[,USER2...] [<git-fetch arguments>]
#        hub fetch [<git-fetch options>] --multiple [<git-fetch arguments>] USER [USER2...]
#
# Adds a remote named USER for each USER that is not a remote or remote group
# yet, pointing at USER's copy of the current repository (as `hub remote add
# USER` does), then fetches: `git fetch --multiple USER USER2... ARGS` for a
# list, else git fetch with the arguments as given. --multiple (or -m) counts
# only among the options before the first name, where the last of it and
# --no-multiple wins. Anything else is plain git fetch, and so is a list with a
# name that is neither a remote nor a possible GitHub login. Nothing is looked
# up on GitHub, and git's --dry-run does not stop hub from adding the remotes.
#
#   $ hub fetch jingweno,mislav --prune
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git remote add mislav https://github.com/mislav/REPO.git
#   > git fetch --multiple jingweno mislav --prune

# shellcheck source=lib/hub/ext/remote.sh

hub_ext_fetch() {
  local -a list=() operands=() missing=()
  local -A known=()
  local arg name multiple=0 value=0 leading=1 ended=0 host repo proto
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      operands+=("$arg")
      leading=0
    else
      case $arg in
        --) ended=1 leading=0 ;;
        --help) hub::usage ;;
        --no-multiple) ((leading)) && multiple=0 ;;
        *)
          [[ $leading == 1 && ($arg == --multiple || $arg =~ ^-[^-jo]*m) ]] && multiple=1 # -pm, not -jm
          _hub_fetch_takes_value "$arg" && value=1
          ;;
      esac
    fi
  done
  if ((multiple)); then
    list=("${operands[@]}")
  elif [[ ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9_.,-]*$ && ! -e $1 ]]; then
    IFS=, read -r -a list <<<"$1"
  fi
  ((${#list[@]})) || hub::exec_git fetch "$@"
  while IFS= read -r name; do known[$name]=1; done < <(hub::git_query remote)
  for name in "${list[@]}"; do
    [[ -n $name && -n ${known[$name]-} ]] && continue
    hub::git_query config --get "remotes.$name" >/dev/null && continue # a remote group
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || hub::exec_git fetch "$@"
    known[$name]=1
    missing+=("$name")
  done
  if ((${#missing[@]})); then
    read -r host repo <<<"$(hub::project_or_dir)"
    proto=$(hub::protocol "$host")
    for name in "${missing[@]}"; do
      hub::git remote add "$name" "$(hub::git_url "$name/$repo" "$host" "$proto")" || exit
    done
  fi
  ((multiple)) || [[ $1 != *,* ]] && hub::exec_git fetch "$@"
  hub::exec_git fetch --multiple "${list[@]}" "${@:2}"
}

_hub_fetch_takes_value() {
  case $1 in
    --depth | --deepen | --shallow-since | --shallow-exclude | --negotiation-tip | --refmap | --upload-pack) return 0 ;;
    --server-option | --jobs | --filter | --submodule-prefix | --recurse-submodules-default) return 0 ;;
  esac
  [[ $1 =~ ^-[^-jo]*[jo]$ ]] # -j or -o last in a cluster (-pj 4)
}
