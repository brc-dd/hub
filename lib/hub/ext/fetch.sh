# shellcheck shell=bash
# Summary: Fetch from GitHub users' forks, adding remotes for them first.
# Usage: hub fetch USER[,USER2...] [<git-fetch arguments>]
#
# Adds a remote named USER for each USER in the comma-separated list that is
# not a remote (or remote group) yet, pointing at USER's copy of the current
# repository (REPO as in `hub remote add USER`), then fetches them all: with
# `git fetch --multiple` for a list, plain `git fetch` for one name. Arguments
# after the list are passed to git fetch as they are.
#
# Nothing is looked up on GitHub: if USER has no such repository, git fetch
# fails and the new remote stays (`git remote remove USER` drops it). When the
# first argument is an option, a URL, a path or an existing remote, this is
# plain git fetch.
#
#   $ hub fetch mislav
#   > git remote add mislav https://github.com/mislav/REPO.git
#   > git fetch mislav
#
#   $ hub fetch jingweno,mislav --prune
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git fetch --multiple jingweno mislav --prune
#
# For git's own options, see `man git-fetch`.

# shellcheck source=lib/hub/ext/remote.sh
source "${BASH_SOURCE[0]%/*}/remote.sh" # _hub_remote_project

hub_ext_fetch() {
  local arg
  for arg in "$@"; do
    [[ $arg == -- ]] && break
    [[ $arg == --help ]] && hub::usage
  done
  # Only a list of names, inside a repository, is ours; options, URLs and paths go straight to git.
  if [[ ! ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9_.,-]*$ || -e $1 ]] || ! hub::git_dir >/dev/null; then
    hub::exec_git fetch "$@"
  fi
  local -A known=() seen=()
  local -a list names=() missing=()
  local name
  while IFS= read -r name; do known[$name]=1; done < <(hub::git_query remote)
  [[ -n ${known[$1]-} ]] && hub::exec_git fetch "$@"
  IFS=, read -r -a list <<<"$1"
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
  shift
  ((${#names[@]} > 1)) && names=(--multiple "${names[@]}")
  hub::exec_git fetch "${names[@]}" "$@"
}
