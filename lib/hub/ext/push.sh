# shellcheck shell=bash
# Summary: Push to several remotes at once.
# Usage: hub push REMOTE1,REMOTE2[,...] [<git-push arguments>]
#
# Runs `git push REMOTE ARGS...` for each remote in the list, in order, and stops
# at the first failure. ARGS are passed exactly as given; only when there are
# none is the current branch pushed. Anything else is plain git push.
#
#   $ hub push origin,staging
#   > git push origin CURRENT-BRANCH
#   > git push staging CURRENT-BRANCH
#
#   $ hub push origin,staging --tags
#   > git push origin --tags
#   > git push staging --tags

hub_ext_push() {
  [[ ${1-} == *,* && $1 != -* ]] || hub::exec_git push "$@"
  local -a remotes
  local remote branch
  IFS=, read -r -a remotes <<<"$1"
  shift
  if (($# == 0)); then
    branch=$(hub::current_branch) || hub::die "Aborted: not currently on any branch."
    set -- "$branch"
  fi
  for remote in "${remotes[@]}"; do
    hub::git push "$remote" "$@" || exit
  done
}
