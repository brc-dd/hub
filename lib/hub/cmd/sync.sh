# shellcheck shell=bash
# Summary: Fetch and fast-forward or delete local branches to match the remotes.
# Usage: hub sync [REMOTE]
#
# hub's own command: it takes no options. Fetches REMOTE (default: the project's remote,
# upstream before github and origin) and every other remote a local branch tracks, with git
# fetch --prune and your fetch settings, then goes through the local branches: the current one
# after the others, and those that track a local branch at the end, each after the branch it
# tracks:
#
#   the default branch, behind REMOTE's      fast-forwarded from REMOTE, whatever it tracks
#   behind its upstream                      fast-forwarded
#   ahead of its upstream, or diverged       left alone, with a warning
#   upstream deleted, merged into REMOTE's   deleted (the current branch is first switched
#     default branch                           to the default branch, when that exists here)
#   upstream deleted, not merged             left alone, with a warning
#
# Symbolic refs and branches without an upstream, other than the default branch, are left
# alone. A branch whose upstream is a local branch, or on a remote that could not be fetched, is
# never deleted; a squash-merged branch counts as not merged. The default branch is held against
# its own upstream only when it has commits that REMOTE's lacks. Local commits are never
# discarded: a branch checked out in another work tree is left alone with a warning, and git
# refuses non-fast-forwards and shows its message. The default branch is
# refs/remotes/REMOTE/HEAD, else gh's answer for a GitHub remote; when neither knows it, no
# branch is deleted. git fetch creates that ref from git 2.48 on; with an older git, git remote
# set-head REMOTE --auto creates it once, and it corrects it with any git. sync tries every
# branch and exits 1 when a fetch of another tracked remote, an update or a deletion failed; a
# failed fetch of REMOTE stops it with git's status.
#
#   $ hub sync
#   > git fetch --prune --quiet -- upstream
#   > git fetch --prune --quiet -- origin
#   Deleted branch fix-typo (was 5d6e7f8).
#   Updated branch main (was 1a2b3c4).

hub_cmd_sync() {
  local remote='' default='' current='' failed=0 line name oid symref tracked upstream track r there
  local host owner repo worktrees gitdir stuck moved
  local format='%(refname:lstrip=2)%1f%(objectname)%1f%(symref)%1f%(upstream:remotename)'
  local -a operands=() lines=() locals=() last=() fetched=() others=() ordered=()
  local -A waiting=()
  format+='%1f%(upstream)%1f%(upstream:track,nobracket)'
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -h | --help) hub::usage ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $(hub::shown "$1")" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} <= 1)) || hub::usage_error "unexpected argument: $(hub::shown "${operands[1]}")"
  hub::require_repo
  if ((${#operands[@]})); then
    remote=${operands[0]}
    hub::remote_exists "$remote" || hub::die "not a remote: $(hub::shown "$remote")"
  elif [[ -n ${GH_REPO-} ]]; then
    # An invalid GH_REPO dies here with its own message.
    hub::project >/dev/null
    remote=$(hub::project_remote) \
      || hub::die "no remote points to GH_REPO: $(hub::shown "$GH_REPO") (name the remote to sync)"
  else
    remote=$(hub::project_remote) || hub::die 'no GitHub remote found (name the remote to sync)'
  fi
  # A branch's track is only right once the remote it tracks was fetched too. remotename is "."
  # for a local upstream, and empty for a URL and a remote without configuration.
  while IFS= read -r r; do
    if [[ -n $r && $r != . && " $remote ${others[*]} " != *" $r "* ]]; then others+=("$r"); fi
  done < <(git for-each-ref --format='%(upstream:remotename)' refs/heads)
  hub::git fetch --prune --quiet -- "$remote" || exit
  fetched=("$remote")
  for r in "${others[@]}"; do
    if hub::git fetch --prune --quiet -- "$r"; then fetched+=("$r"); else failed=1; fi
  done
  # Read after the fetch, which from git 2.48 on creates a missing refs/remotes/REMOTE/HEAD (it
  # never moves one).
  read -r host owner repo < <(hub::remote_project "$remote")
  default=$(hub::default_branch "$host" "$owner" "$repo" "$remote") || default=''
  current=$(hub::current_branch) || current=''
  worktrees=$(git worktree list --porcelain)
  gitdir=$(git rev-parse --absolute-git-dir) || exit
  # The unit separator keeps empty fields: a run of spaces would merge them.
  # Branches tracking a local branch, the current one included, come at the end, each after the
  # branch it tracks, as that branch may move first; the rest of a cycle follows in any order.
  while IFS= read -r line; do
    IFS=$'\x1f' read -r name _ _ tracked _ <<<"$line"
    if [[ $tracked == . ]]; then
      locals+=("$line")
      waiting["refs/heads/$name"]=1
    elif [[ $name == "$current" ]]; then
      last=("$line")
    else
      lines+=("$line")
    fi
  done < <(git for-each-ref --format="$format" refs/heads)
  stuck=0
  while ((${#ordered[@]} < ${#locals[@]})); do
    moved=0
    for line in "${locals[@]}"; do
      IFS=$'\x1f' read -r name _ _ _ upstream _ <<<"$line"
      [[ -n ${waiting["refs/heads/$name"]} ]] || continue
      if ((stuck)) || [[ -z ${waiting[$upstream]-} ]]; then
        ordered+=("$line") && waiting["refs/heads/$name"]='' && moved=1
      fi
    done
    ((moved)) || stuck=1
  done
  for line in "${lines[@]}" "${last[@]}" "${ordered[@]}"; do
    IFS=$'\x1f' read -r name oid symref tracked upstream track <<<"$line"
    [[ -z $symref ]] || continue
    # The project's copy is the source of truth for the default branch, even in a fork's clone:
    # once it has every commit of the branch, what the branch tracks does not matter.
    if [[ -n $default && $name == "$default" ]] \
      && there=$(git rev-parse --verify --quiet "refs/remotes/$remote/$default") \
      && git merge-base --is-ancestor "$oid" "$there"; then
      if [[ $there != "$oid" ]]; then
        _hub_sync_update "$name" "$oid" "refs/remotes/$remote/$default" "$current" "$worktrees" \
          "$gitdir" || failed=1
      fi
      continue
    fi
    [[ -n $tracked ]] || continue
    if [[ $tracked == . ]]; then
      track=$(git for-each-ref --format='%(upstream:track,nobracket)' "refs/heads/$name")
    fi
    case $track in
      behind*)
        _hub_sync_update "$name" "$oid" "$upstream" "$current" "$worktrees" "$gitdir" || failed=1
        ;;
      ahead*)
        if [[ $tracked == . ]]; then
          hub::warn "$name is ahead of ${upstream#refs/heads/}"
        else
          hub::warn "$name seems to contain unpushed commits"
        fi
        ;;
      gone)
        # Not fetched in this run (a local upstream never is): it may be missing for another reason.
        [[ " ${fetched[*]} " == *" $tracked "* ]] || continue
        if [[ -z $default ]]; then
          hub::warn "$name was deleted on $tracked, but the default branch of $remote is not" \
            'known; leaving it alone'
        elif [[ $name == "$default" ]]; then
          hub::warn "$name was deleted on $tracked, but it is the default branch of $remote;" \
            'leaving it alone'
        elif git merge-base --is-ancestor "refs/heads/$name" "refs/remotes/$remote/$default" \
          2>/dev/null; then
          _hub_sync_delete "$name" "$default" "$current" "$tracked" || failed=1
          # It may have switched to the default branch, which the branches after it may track.
          current=$(hub::current_branch) || current=''
        else
          hub::warn "$name was deleted on $tracked, but is not merged into $remote/$default"
        fi
        ;;
    esac
  done
  return "$failed"
}

# _hub_sync_update BRANCH OID REF CURRENT WORKTREES GITDIR : fast-forward BRANCH, at OID, to REF
# in the repository at GITDIR, unless git worktree list --porcelain's WORKTREES has it checked out
# elsewhere.
_hub_sync_update() {
  if [[ $1 == "$4" ]]; then
    # --no-squash: branch.*.mergeOptions may say --squash, which would not move the branch.
    hub::git merge --quiet --ff-only --no-squash "$3" || return
  elif [[ $'\n'$5$'\n' == *$'\n'"branch refs/heads/$1"$'\n'* ]]; then
    # git fetch refuses a branch checked out in another work tree only from git 2.35 on.
    hub::warn "$1 is checked out in another work tree; leaving it alone"
    return 1
  else
    # A branch that is not checked out moves by a fetch from the repository itself, which refuses
    # a non-fast-forward. Not from ".": that is the top of the work tree, not the git directory.
    hub::git fetch --quiet "$6" "$3:refs/heads/$1" || return
  fi
  [[ ${HUB_NOOP-} == 1 ]] && return 0
  printf 'Updated branch %s (was %s).\n' "$1" "$(git rev-parse --short "$2")"
}

# _hub_sync_delete BRANCH DEFAULT CURRENT REMOTE : delete BRANCH, switching away when current.
_hub_sync_delete() {
  if [[ $1 == "$3" ]]; then
    if ! git show-ref --verify --quiet "refs/heads/$2"; then
      hub::warn "$1 is merged and deleted on $4 (switch to another branch to delete it)"
      return 0
    fi
    hub::git switch --quiet --no-guess "$2" || return
  fi
  # git prints "Deleted branch BRANCH (was SHORTOID)." itself.
  hub::git branch -D -- "$1"
}
