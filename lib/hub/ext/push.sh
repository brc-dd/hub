# shellcheck shell=bash
# Summary: Push a branch to several remotes at once.
# Usage: hub push REMOTE1,REMOTE2[,...] [REF...] [git-push options]
#
# With a comma-separated list of remotes, runs `git push` once per remote, in
# order, stopping at the first failure. Without a REF, the current branch is
# pushed. Anything else is passed to git push unchanged.
#
#   $ hub push origin,staging cool-feature
#   > git push origin cool-feature
#   > git push staging cool-feature

hub_ext_push() {
  [[ $# -ge 1 && $1 == *,* ]] || hub::exec_git push "$@"
  local remotes=$1 arg branch
  shift
  local -a flags=() refs=()
  for arg in "$@"; do
    if [[ $arg == -* ]]; then flags+=("$arg"); else refs+=("$arg"); fi
  done
  if ((${#refs[@]} == 0)); then
    branch=$(hub::current_branch) || hub::die "Aborted: not currently on any branch."
    refs=("$branch")
  fi
  local -a list
  IFS=, read -r -a list <<<"$remotes"
  local remote
  for remote in "${list[@]}"; do
    [[ -n $remote ]] || continue
    hub::git push "$remote" "${flags[@]}" "${refs[@]}" || exit $?
  done
}
