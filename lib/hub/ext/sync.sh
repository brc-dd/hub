# shellcheck shell=bash
# Summary: Fetch a remote and fast-forward or delete local branches to match it.
# Usage: hub sync [REMOTE]
#
# Fetches REMOTE (by default the main GitHub remote: upstream, github, then
# origin) with --prune, then goes through every local branch and compares it
# with its upstream branch on REMOTE, or else with the branch of the same name
# there:
#
#   behind                    fast-forwarded: "Updated branch NAME (was SHA)."
#   deleted on REMOTE, and    deleted with `git branch -D` (if it is checked
#     merged into REMOTE's      out, REMOTE's default branch is checked out
#     default branch            first)
#   ahead or diverged         left alone, with a warning
#   deleted but not merged    left alone, with a warning
#
# git reports an upstream branch as gone whenever its remote-tracking branch
# is missing, which it also is when remote.REMOTE.fetch leaves the branch out
# (^refs/heads/NAME, say). So before deleting a branch, sync asks REMOTE with
# `git ls-remote` (read-only, so --noop runs it too). A branch REMOTE still
# has is skipped with a note; if REMOTE cannot be asked, the branch is left
# alone and sync exits non-zero at the end.
#
# Local commits are never discarded. When git cannot update, check out or
# delete a branch (one checked out in another worktree, say), sync says which,
# carries on with the other branches and exits non-zero at the end. This is
# plain git; gh is not used.

hub_ext_sync() {
  [[ ${1-} == --help ]] && hub::usage
  (($# <= 1)) && [[ ${1-} != -* ]] || hub::die "Usage: hub sync [REMOTE]"
  hub::require_repo
  local remote=${1-}
  if [[ -z $remote ]]; then
    remote=$(hub::main_remote) \
      || hub::die "Aborted: no GitHub remote found (looked for upstream, github, origin); name the one to sync: hub sync REMOTE"
  fi
  hub::git_query remote get-url "$remote" >/dev/null || hub::die "Aborted: no such remote: $remote"
  hub::git fetch --prune --quiet "$remote" || exit

  local default current
  default=$(_hub_sync_default_branch "$remote")
  current=$(hub::git_query symbolic-ref -q HEAD)
  current=${current#refs/heads/}

  local branch upremote upstream upref track tip short up_tip failed=0
  while IFS=$'\x1f' read -r -u 3 branch upremote upstream upref track tip short; do
    if [[ $upremote == "$remote" && $track == gone && $branch != "$default" ]]; then
      # The upstream branch was deleted: drop the local one if REMOTE's default branch has all of it.
      if [[ -n $default ]] && hub::git_query merge-base --is-ancestor "$tip" "refs/remotes/$remote/$default"; then
        _hub_sync_gone "$remote" "$branch" "$upstream" "${upref:-refs/heads/$branch}" || {
          (($? == 2)) && failed=1
          continue
        }
        if [[ $branch == "$current" ]]; then
          if ! hub::git checkout --quiet "$default"; then
            hub::warn "error: could not check out '$default' to delete '$branch'"
            failed=1
            continue
          fi
          current=$default
        fi
        hub::git branch -D "$branch" || {
          hub::warn "error: could not delete '$branch'"
          failed=1
        }
      else
        hub::warn "warning: '$branch' was deleted on $remote, but appears not merged into '${default:-$remote/HEAD}'"
      fi
      continue
    fi
    if [[ $upremote != "$remote" || $track == gone ]]; then
      upstream=refs/remotes/$remote/$branch # no upstream on REMOTE: compare with the same-named branch
    fi
    up_tip=$(hub::git_query rev-parse --verify --quiet "$upstream^{commit}") || continue
    [[ $tip == "$up_tip" ]] && continue
    if hub::git_query merge-base --is-ancestor "$tip" "$up_tip"; then
      if [[ $branch == "$current" ]]; then
        hub::git merge --ff-only --quiet "$upstream"
      else
        hub::git branch --force --no-track "$branch" "$upstream"
      fi || {
        hub::warn "error: could not fast-forward '$branch' to ${upstream#refs/remotes/}"
        failed=1
        continue
      }
      ((HUB_NOOP)) || printf 'Updated branch %s (was %s).\n' "$branch" "$short"
    else
      hub::warn "warning: '$branch' seems to contain unpushed commits"
    fi
  done 3< <(hub::git_query for-each-ref \
    --format='%(refname:lstrip=2)%1f%(upstream:remotename)%1f%(upstream)%1f%(upstream:remoteref)%1f%(upstream:track,nobracket)%1f%(objectname)%1f%(objectname:short)' \
    refs/heads)
  ((failed == 0)) || exit 1
}

# _hub_sync_gone REMOTE BRANCH UPSTREAM REF : true if REMOTE really has no REF (BRANCH's upstream
# branch there, fetched as UPSTREAM) any more. Prints a note and returns 1 if REMOTE still has it,
# or prints an error and returns 2 if REMOTE could not be asked.
_hub_sync_gone() {
  local remote=$1 branch=$2 upstream=${3#refs/remotes/} ref=$4 status=0
  local -a heads=(--heads)
  [[ $ref == refs/heads/* ]] || heads=() # an upstream outside refs/heads (refs/pull/N/head, say)
  hub::git_query ls-remote --exit-code "${heads[@]}" "$remote" "$ref" >/dev/null || status=$?
  case $status in
    2) return 0 ;;
    0)
      hub::warn "skipping '$branch': $upstream exists on $remote but is not fetched (check remote.$remote.fetch)"
      return 1
      ;;
    *)
      hub::warn "error: could not check whether $upstream still exists on $remote; leaving '$branch' alone"
      return 2
      ;;
  esac
}

# _hub_sync_default_branch REMOTE : REMOTE's default branch, from REMOTE/HEAD, else main or master if REMOTE has one.
_hub_sync_default_branch() {
  local remote=$1 ref
  # REMOTE/HEAD can dangle after the default branch is renamed and the old one pruned.
  if ref=$(hub::git_query symbolic-ref -q "refs/remotes/$remote/HEAD") && hub::git_query show-ref --verify --quiet "$ref"; then
    printf '%s\n' "${ref#refs/remotes/"$remote"/}"
    return 0
  fi
  for ref in main master; do
    hub::git_query show-ref --verify --quiet "refs/remotes/$remote/$ref" && {
      printf '%s\n' "$ref"
      return 0
    }
  done
  return 1
}
