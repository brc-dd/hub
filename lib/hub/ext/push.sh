# shellcheck shell=bash
# Summary: Push to several remotes at once.
# Usage: hub push REMOTE1,REMOTE2[,...] [<git-push arguments>]
#
# With a comma-separated list of remotes, runs `git push REMOTE ARGS...` once
# per remote, in order, stopping at the first failure. ARGS, everything after
# the list, are passed to every git push exactly as given; only when there are
# none at all is the current branch pushed. Anything else is plain git push.
#
#   $ hub push origin,staging cool-feature
#   > git push origin cool-feature
#   > git push staging cool-feature
#
#   $ hub push origin,staging
#   > git push origin CURRENT-BRANCH
#   > git push staging CURRENT-BRANCH
#
#   $ hub push origin,staging --tags
#   > git push origin --tags
#   > git push staging --tags
#
# For git's own options, see `man git-push`.

hub_ext_push() {
  # An option such as --push-option=a,b is not a list of remotes.
  [[ $# -ge 1 && $1 == *,* && $1 != -* ]] || hub::exec_git push "$@"
  local -a remotes
  IFS=, read -r -a remotes <<<"$1"
  shift
  if (($# == 0)); then
    local branch
    branch=$(hub::current_branch) || hub::die "Aborted: not currently on any branch."
    set -- "$branch"
  fi
  local remote
  for remote in "${remotes[@]}"; do
    [[ -n $remote ]] || continue
    hub::git push "$remote" "$@" || exit
  done
}
