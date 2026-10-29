# shellcheck shell=bash
# Summary: Fetch from GitHub users' forks, adding remotes for them first.
# Usage: hub fetch USER[,USER2...] [<git-fetch arguments>]
#        hub fetch --multiple USER [USER2...] [<git-fetch arguments>]
#
# Adds a remote named USER for each USER in the comma-separated list that is
# not a remote (or remote group) yet, pointing at USER's copy of the current
# repository (REPO as in `hub remote add USER`), then fetches them all: with
# `git fetch --multiple` for a list, plain `git fetch` for one name. Arguments
# after the list are passed to git fetch as they are.
#
# With --multiple (or -m) first, the list is instead the names that follow
# it, up to the first argument that starts with "-". The missing remotes are
# added in the same way, then `git fetch --multiple` gets the other arguments,
# as they are, followed by the names.
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
#   $ hub fetch --multiple jingweno mislav --prune
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git fetch --multiple --prune jingweno mislav
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
    for arg in "${@:2}"; do
      [[ $arg == -* ]] && break
      list+=("$arg")
    done
    rest=("${@:${#list[@]}+2}") # what follows the names
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
    [[ -n $name && -z ${seen[$name]-} ]] || continue
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
    hub::exec_git fetch --multiple "${rest[@]}" "${names[@]}"
  fi
  ((${#names[@]} > 1)) && names=(--multiple "${names[@]}")
  hub::exec_git fetch "${names[@]}" "${rest[@]}"
}
