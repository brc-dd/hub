# shellcheck shell=bash
# Summary: Fetch from GitHub users' forks, adding remotes for them first.
# Usage: hub fetch USER[,USER2...] [<git-fetch arguments>]
#        hub fetch [<git-fetch options>] --multiple [<git-fetch options>] USER [USER2...]
#
# Adds a remote named USER for each USER in the comma-separated list that is
# not a remote (or remote group) yet, pointing at USER's copy of the current
# repository (REPO as in `hub remote add USER`), then fetches them all: with
# `git fetch --multiple` for a list, plain `git fetch` for one name. Arguments
# after the list are passed to git fetch as they are.
#
# With --multiple (or -m) among the options before the first name and before
# `--`, the list is instead every name in the arguments: before, between or
# after git fetch's options, and everything after `--`, but not the value of
# an option, as in --depth 1. The missing remotes are added in the same way,
# then git fetch gets all the arguments unchanged and in their order.
#
# git fetch's --dry-run is not hub's --noop: hub still adds the missing
# remotes, and only the fetch is a dry run. To see what hub would do without
# changing anything, use `hub --noop fetch ...`.
#
# Nothing is looked up on GitHub: if USER has no such repository, git fetch
# fails and the new remote stays (`git remote remove USER` drops it). This is
# plain git fetch when the arguments start with an option and no --multiple
# comes before the first name, when the first argument is a URL, a path or an
# existing remote, and when a name in the list is neither a remote (or remote
# group) nor something that can be a GitHub login, such as a URL.
#
#   $ hub fetch mislav
#   > git remote add mislav https://github.com/mislav/REPO.git
#   > git fetch mislav
#
#   $ hub fetch jingweno,mislav --prune
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git fetch --multiple jingweno mislav --prune
#
#   $ hub fetch --prune --multiple jingweno --depth 1 mislav
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git fetch --prune --multiple jingweno --depth 1 mislav
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
  # The operands are the arguments that are neither an option nor an option's value, and all
  # after --; they are the names for --multiple, which counts only before the first of them.
  local -a list=() rest=() operands=()
  local value=0 leading=1 dashdash=0
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif ((dashdash)) || [[ $arg != -?* ]]; then
      operands+=("$arg")
      leading=0
    elif [[ $arg == -- ]]; then
      dashdash=1 leading=0
    else
      ((leading)) && _hub_fetch_is_multiple "$arg" && multiple=1
      _hub_fetch_takes_value "$arg" && value=1
    fi
  done
  if ((multiple)); then
    list=("${operands[@]}")
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
    hub::exec_git fetch "$@" # every argument as given, in its place
  fi
  ((${#names[@]} > 1)) && names=(--multiple "${names[@]}")
  hub::exec_git fetch "${names[@]}" "${rest[@]}"
}

# _hub_fetch_is_multiple OPTION : true if the git fetch OPTION is --multiple, or -m alone or in a
# short option cluster (-pm).
_hub_fetch_is_multiple() {
  case $1 in
    --multiple) return 0 ;;
    --*) return 1 ;;
  esac
  # What follows -j or -o in a cluster is their value, not more options (-jm is --jobs=m).
  local opts=${1#-}
  [[ ${opts%%[jo]*} == *m* ]]
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
