# shellcheck shell=bash
# Summary: Fetch and fast-forward or delete local branches to match the remotes.
# Usage: hub sync [REMOTE]
#
# hub's own command: these are all of its options. Fetches REMOTE (default: the project's
# remote, upstream before github and origin) and every other remote a local branch tracks, with
# git fetch --prune and your fetch settings, then goes through the local branches, the current
# one last:
#
#   the default branch, behind REMOTE's      fast-forwarded from REMOTE, whatever it tracks
#   behind its upstream                      fast-forwarded
#   ahead of its upstream, or diverged       left alone, with a warning
#   upstream deleted, merged into REMOTE's   deleted (the current branch is first switched
#     default branch                           to the default branch, when that exists here)
#   upstream deleted, not merged             left alone, with a warning
#
# Symbolic refs, branches without an upstream and branches whose upstream is a local branch or
# on a remote that could not be fetched are left alone; a squash-merged branch counts as not
# merged. Local commits are never discarded: git refuses non-fast-forwards and branches checked
# out in another work tree, and its message is shown. The default branch is
# refs/remotes/REMOTE/HEAD (git remote set-head REMOTE --auto corrects it), else gh's answer
# for a GitHub remote; when neither knows it, no branch is deleted. sync tries every branch and
# exits 1 when an update or a deletion failed.
#
#   $ hub sync
#   > git fetch --prune --quiet -- upstream
#   > git fetch --prune --quiet -- origin
#   Deleted branch fix-typo (was 5d6e7f8).
#   Updated branch main (was 1a2b3c4).

hub_cmd_sync() {
  local remote='' default='' current='' failed=0 line name oid symref tracked upstream track r
  local format='%(refname:lstrip=2)%1f%(objectname)%1f%(symref)%1f%(upstream:remotename)'
  local -a operands=() lines=() last=() fetched=() others=()
  format+='%1f%(upstream)%1f%(upstream:track,nobracket)'
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -h | --help) hub::usage ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $1" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} <= 1)) || hub::usage_error "unexpected argument: ${operands[1]}"
  hub::require_repo
  if ((${#operands[@]})); then
    remote=${operands[0]}
    hub::remote_exists "$remote" || hub::die "not a remote: $remote"
  elif [[ -n ${GH_REPO-} ]]; then
    # An invalid GH_REPO dies here with its own message.
    hub::project >/dev/null
    remote=$(hub::project_remote) \
      || hub::die "no remote points to GH_REPO: $GH_REPO (name the remote to sync)"
  else
    remote=$(hub::project_remote) || hub::die 'no GitHub remote found; name the remote to sync'
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
  # Read after the fetch, which creates a missing refs/remotes/REMOTE/HEAD (it never moves one).
  default=$(_hub_sync_default_branch "$remote") || default=''
  current=$(hub::current_branch) || current=''
  # The unit separator keeps empty fields: a run of spaces would merge them.
  while IFS= read -r line; do
    if [[ ${line%%$'\x1f'*} == "$current" ]]; then last=("$line"); else lines+=("$line"); fi
  done < <(git for-each-ref --format="$format" refs/heads)
  for line in "${lines[@]}" "${last[@]}"; do
    IFS=$'\x1f' read -r name oid symref tracked upstream track <<<"$line"
    [[ -z $symref ]] || continue
    # The project's copy is the source of truth for the default branch, even in a fork's clone.
    if [[ -n $default && $name == "$default" ]] \
      && _hub_sync_behind "$oid" "refs/remotes/$remote/$default"; then
      _hub_sync_update "$name" "$oid" "refs/remotes/$remote/$default" "$current" || failed=1
      continue
    fi
    [[ -n $tracked ]] || continue
    case $track in
      behind*) _hub_sync_update "$name" "$oid" "$upstream" "$current" || failed=1 ;;
      ahead*) hub::warn "$name seems to contain unpushed commits" ;;
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
        else
          hub::warn "$name was deleted on $tracked, but is not merged into $remote/$default"
        fi
        ;;
    esac
  done
  return "$failed"
}

# _hub_sync_default_branch REMOTE : the default branch of REMOTE's repository; fails when unknown.
_hub_sync_default_branch() {
  local host owner repo
  _hub_sync_remote_head "$1" && return 0
  read -r host owner repo < <(hub::remote_project "$1") || return 1
  # Without gh the default branch is only unknown: sync still updates branches.
  command -v gh >/dev/null && hub::default_branch "$host" "$owner" "$repo"
}

# _hub_sync_remote_head REMOTE : the branch refs/remotes/REMOTE/HEAD points at, when both exist.
_hub_sync_remote_head() {
  local ref head=refs/remotes/$1/
  ref=$(git symbolic-ref --quiet "${head}HEAD" 2>/dev/null) && [[ $ref == "$head"?* ]] \
    && git show-ref --verify --quiet "$ref" && printf '%s\n' "${ref#"$head"}"
}

# _hub_sync_behind OID REF : REF exists and is ahead of OID.
_hub_sync_behind() {
  local there
  there=$(git rev-parse --verify --quiet "$2") || return 1
  [[ $there != "$1" ]] && git merge-base --is-ancestor "$1" "$there"
}

# _hub_sync_update BRANCH OID REF CURRENT : fast-forward BRANCH, at OID, to REF.
_hub_sync_update() {
  if [[ $1 == "$4" ]]; then
    # --no-squash: branch.*.mergeOptions may say --squash, which would not move the branch.
    hub::git merge --quiet --ff-only --no-squash "$3" || return
  else
    hub::git fetch --quiet . "$3:refs/heads/$1" || return
  fi
  [[ ${HUB_NOOP-} == 1 ]] && return 0
  printf 'Updated branch %s (was %s).\n' "$1" "$(git rev-parse --short "$2")"
}

# _hub_sync_delete BRANCH DEFAULT CURRENT REMOTE : delete BRANCH, switching away when current.
_hub_sync_delete() {
  if [[ $1 == "$3" ]]; then
    if ! git show-ref --verify --quiet "refs/heads/$2"; then
      hub::warn "$1 is merged and deleted on $4; switch to another branch to delete it"
      return 0
    fi
    hub::git switch --quiet --no-guess "$2" || return
  fi
  # git prints "Deleted branch BRANCH (was SHORTOID)." itself.
  hub::git branch -D -- "$1"
}
