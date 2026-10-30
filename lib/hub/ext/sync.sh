# shellcheck shell=bash
# Summary: Fetch a remote and fast-forward or delete local branches to match it.
# Usage: hub sync [REMOTE]
#
# Fetches REMOTE (default: the upstream, github or origin remote) with --prune,
# then compares every local branch with its upstream branch on REMOTE, else with
# the branch of the same name there:
#
#   behind                       fast-forwarded
#   deleted on REMOTE, and       deleted, once `git ls-remote` confirms that
#     merged into its default      REMOTE has no such branch (a checked-out one
#     branch                       is switched to the default branch first)
#   ahead, diverged or unmerged  left alone, with a warning
#
# Local commits are never discarded. When git cannot update or delete a branch,
# or REMOTE cannot be asked about one, sync carries on with the others and exits
# non-zero. Only git is used.

hub_ext_sync() {
  [[ ${1-} == --help ]] && hub::usage
  (($# <= 1)) && [[ ${1-} != -* ]] || hub::die "Usage: hub sync [REMOTE]"
  hub::require_repo
  local remote=${1-} default current branch upremote upstream upref track tip short up_tip failed=0
  local -a cmd
  if [[ -z $remote ]]; then
    remote=$(hub::main_remote) || hub::die "Aborted: no GitHub remote found (looked for upstream, github, origin); name the one to sync: hub sync REMOTE"
  fi
  hub::git fetch --prune --quiet "$remote" || exit
  default=$(_hub_sync_default_branch "$remote")
  current=$(hub::git_query symbolic-ref -q HEAD)
  current=${current#refs/heads/}
  while IFS=$'\x1f' read -r -u 3 branch upremote upstream upref track tip short; do
    if [[ $upremote == "$remote" && $track == gone && $branch != "$default" ]]; then
      if ! hub::git_query merge-base --is-ancestor "$tip" "refs/remotes/$remote/$default"; then
        hub::warn "warning: '$branch' was deleted on $remote, but appears not merged into '${default:-$remote/HEAD}'"
        continue
      fi
      _hub_sync_gone "$remote" "$branch" "${upstream#refs/remotes/}" "$upref" || {
        (($? == 2)) && failed=1
        continue
      }
      if [[ $branch == "$current" ]]; then
        hub::git checkout --quiet "$default" || {
          hub::warn "error: could not check out '$default' to delete '$branch'"
          failed=1
          continue
        }
        current=$default
      fi
      hub::git branch -D "$branch" || failed=1
      continue
    fi
    [[ $upremote == "$remote" && $track != gone ]] || upstream=refs/remotes/$remote/$branch
    up_tip=$(hub::git_query rev-parse --verify --quiet "$upstream^{commit}") || continue
    [[ $tip == "$up_tip" ]] && continue
    cmd=(branch --force --no-track "$branch" "$upstream")
    [[ $branch == "$current" ]] && cmd=(merge --ff-only --quiet "$upstream")
    if ! hub::git_query merge-base --is-ancestor "$tip" "$up_tip"; then
      hub::warn "warning: '$branch' seems to contain unpushed commits"
    elif hub::git "${cmd[@]}"; then
      ((HUB_NOOP)) || printf 'Updated branch %s (was %s).\n' "$branch" "$short"
    else
      failed=1
    fi
  done 3< <(hub::git_query for-each-ref \
    --format='%(refname:lstrip=2)%1f%(upstream:remotename)%1f%(upstream)%1f%(upstream:remoteref)%1f%(upstream:track,nobracket)%1f%(objectname)%1f%(objectname:short)' \
    refs/heads)
  ((failed == 0)) || exit 1
}

# _hub_sync_gone REMOTE BRANCH UPSTREAM REF : 0 if REMOTE has no REF any more; else 1 with a note
# (it is there, just not fetched), or 2 with an error (REMOTE could not be asked).
_hub_sync_gone() {
  local remote=$1 branch=$2 upstream=$3 ref=$4
  local -a heads=()
  [[ $ref == refs/heads/* ]] && heads=(--heads) # not for gh pr checkout's refs/pull/N/head
  hub::git_query ls-remote --exit-code "${heads[@]}" "$remote" "$ref" >/dev/null
  case $? in
    2) return 0 ;;
    0) hub::warn "skipping '$branch': $upstream exists on $remote but is not fetched (check remote.$remote.fetch)" ;;
    *) hub::warn "error: could not check whether $upstream still exists on $remote; leaving '$branch' alone" && return 2 ;;
  esac
  return 1
}

_hub_sync_default_branch() {
  local ref
  for ref in "$(hub::git_query symbolic-ref -q "refs/remotes/$1/HEAD")" "refs/remotes/$1/main" "refs/remotes/$1/master"; do
    # REMOTE/HEAD dangles once the default branch is renamed and the old one pruned
    hub::git_query show-ref --verify --quiet "$ref" && printf '%s\n' "${ref#"refs/remotes/$1/"}" && return
  done
}
