# shellcheck shell=bash
# Summary: Fetch from GitHub users' forks, adding remotes for them first.
# Usage: hub fetch USER[,USER2...] [<git-fetch arguments>]
#        hub fetch --multiple [<git-fetch options>] USER [USER2...]
#
# Adds a remote named USER for each USER in the comma-separated list that is
# not a remote (or remote group) yet, pointing at USER's copy of the current
# repository (REPO as in `hub remote add USER`), then fetches them all: with
# `git fetch --multiple` for a list, plain `git fetch` for one name. Arguments
# after the list are passed to git fetch as they are.
#
# With --multiple (or -m) first, the list is instead every name that follows
# it, before, between or after git fetch's options; the value of an option,
# as in --depth 1, is not a name. The missing remotes are added in the same
# way, then `git fetch --multiple` gets the rest of the arguments unchanged and
# in their order.
#
# Nothing is looked up on GitHub: if USER has no such repository, git fetch
# fails and the new remote stays (`git remote remove USER` drops it). This is
# plain git fetch when the first argument is any other option, a URL, a path
# or an existing remote, and when a name in the list is neither a remote (or
# remote group) nor something that can be a GitHub login, such as a URL.
#
#   $ hub fetch mislav
#   > git remote add mislav https://github.com/mislav/REPO.git
#   > git fetch mislav
#
#   $ hub fetch jingweno,mislav --prune
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git fetch --multiple jingweno mislav --prune
#
#   $ hub fetch --multiple --prune jingweno --depth 1 mislav
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git fetch --multiple --prune jingweno --depth 1 mislav
#
# For git's own options, see `man git-fetch`.

# shellcheck source=lib/hub/ext/remote.sh
source "${BASH_SOURCE[0]%/*}/remote.sh" # _hub_remote_project

hub_ext_fetch() {
  local arg multiple=0
  for arg in "$@"; do
    [[ $arg == -- ]] && break
    [[ $arg == --help ]] && hub::usage
  done
  local -a list=() rest=()
  if [[ ${1-} == --multiple || ${1-} == -m ]]; then
    multiple=1
    # The names are the operands, wherever the options are: neither an option nor an option's value.
    local value=0 operands=0
    for arg in "${@:2}"; do
      if ((value)); then
        value=0
      elif ((operands)) || [[ $arg != -?* ]]; then
        list+=("$arg")
      elif [[ $arg == -- ]]; then
        operands=1
      elif _hub_fetch_takes_value "$arg"; then
        value=1
      fi
    done
  elif [[ ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9_.,-]*$ && ! -e $1 ]]; then
    IFS=, read -r -a list <<<"$1"
    rest=("${@:2}")
  fi
  # Only a list of names, inside a repository, is ours; options, URLs and paths go straight to git.
  if ((${#list[@]} == 0)) || ! hub::git_dir >/dev/null; then
    hub::exec_git fetch "$@"
  fi
  local -A known=() seen=()
  local -a names=() missing=()
  local name
  while IFS= read -r name; do known[$name]=1; done < <(hub::git_query remote)
  ((! multiple)) && [[ -n ${known[$1]-} ]] && hub::exec_git fetch "$@" # an existing remote first
  for name in "${list[@]}"; do
    if [[ -z $name ]]; then
      ((multiple)) && hub::exec_git fetch "$@" # git rejects it; the comma form skips it (alice,,bob)
      continue
    fi
    [[ -z ${seen[$name]-} ]] || continue
    seen[$name]=1
    names+=("$name")
    [[ -n ${known[$name]-} ]] && continue
    hub::git_query config --get "remotes.$name" >/dev/null && continue     # a remote group
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || hub::exec_git fetch "$@" # not a GitHub login
    missing+=("$name")
  done
  if ((${#missing[@]})); then
    local host repo proto
    read -r host repo <<<"$(_hub_remote_project)"
    proto=$(GH_HOST=$host hub::protocol)
    for name in "${missing[@]}"; do
      hub::git remote add "$name" "$(hub::git_url "$name/$repo" "$host" "$proto")" || exit $?
    done
  fi
  if ((multiple)); then
    hub::exec_git fetch --multiple "${@:2}" # every other argument as given, in its place
  fi
  ((${#names[@]} > 1)) && names=(--multiple "${names[@]}")
  hub::exec_git fetch "${names[@]}" "${rest[@]}"
}

# _hub_fetch_takes_value OPTION : true if the git fetch OPTION takes the next argument as its value.
_hub_fetch_takes_value() {
  case $1 in
    --depth | --deepen | --shallow-since | --shallow-exclude | --negotiation-tip | --refmap | --upload-pack) return 0 ;;
    --server-option | --jobs | --filter | --submodule-prefix | --recurse-submodules-default) return 0 ;;
    --*) return 1 ;; # a flag, or a value attached with "="
  esac
  # -j and -o take the rest of a short option cluster (-j4), or the next argument when last (-pj 4).
  local opts=${1#-} head
  head=${opts%%[jo]*}
  [[ $head != "$opts" ]] && ((${#head} + 1 == ${#opts}))
}
