# shellcheck shell=bash
# Summary: Fetch a remote and fast-forward or delete local branches to match it.
# Usage: hub sync [--color[=WHEN]] [REMOTE]
#
# A hub-owned command. Fetches the branches of REMOTE (default: the upstream,
# github or origin remote) into refs/remotes/REMOTE/, pruning the remote-tracking
# branches that are gone there, then compares every local branch with the branch
# it tracks on REMOTE (branch.NAME.remote and branch.NAME.merge), else with the
# branch of the same name there:
#
#   behind                       fast-forwarded
#   deleted on REMOTE, and       deleted (a checked-out one is switched to
#     merged into its default      REMOTE's default branch first, which is
#     branch                       created from REMOTE's when it is missing)
#   ahead, diverged or unmerged  left alone, with a warning
#
# Local commits are never discarded. The fetch is `git fetch --prune REMOTE
# +refs/heads/*:refs/remotes/REMOTE/*` whatever remote.REMOTE.fetch, fetch.prune
# or fetch.pruneTags say, so nothing outside refs/remotes/REMOTE/ is ever pruned
# and no local branch is written by it; tags follow as in any fetch. A branch is
# updated or deleted only while it is still where sync saw it, never while it is
# checked out in another work tree, and never through a symbolic ref. The current
# branch is fast-forwarded with `git merge --ff-only`, which refuses when local
# changes would be lost, and sync checks that HEAD arrived. A branch that tracks
# something other than a branch of REMOTE (refs/pull/N/head, from gh pr checkout)
# is deleted once it is merged into the default branch and otherwise left alone.
# When a branch could not be updated or deleted, sync carries on with the others
# and exits non-zero. REMOTE's default branch is refs/remotes/REMOTE/HEAD, else
# gh's answer, else main.
#
# Options:
#   --color[=WHEN]   Color the output: always (the default for --color), never,
#                    or auto (on a terminal, unless NO_COLOR is set; the default).
#
#   $ hub sync
#   > git fetch --prune --quiet --refmap= origin +refs/heads/\*:refs/remotes/origin/\*
#   > git update-ref -m hub\ sync:\ fast-forward\ to\ origin/topic refs/heads/topic NEW OLD
#   > git merge --ff-only --no-squash --quiet NEW        (the current branch)
#   > git update-ref -d refs/heads/merged OLD            (deleted on origin, merged)

hub_ext_sync() {
  local arg remote='' color=auto ended=0
  hub::normalize_opts '' '' "$@"
  for arg in "${HUB_ARGS[@]}"; do
    if ((ended)) || [[ $arg != -?* ]]; then
      [[ -z $remote ]] || _hub_sync_usage
      remote=$arg
      continue
    fi
    case $arg in
      --) ended=1 ;;
      -h | --help) hub::usage ;;
      --color) color=always ;;
      --color=always | --color=never | --color=auto) color=${arg#*=} ;;
      *) _hub_sync_usage ;;
    esac
  done
  hub::require_repo
  if [[ -z $remote ]]; then
    remote=$(hub::main_remote) || hub::die "Aborted: no GitHub remote found (looked for upstream, github, origin); name the one to sync: hub sync REMOTE"
  else
    hub::remote_exists "$remote" || hub::die "Aborted: no remote named '$remote'"
  fi
  local use_color=0
  case $color in
    always) use_color=1 ;;
    auto) [[ -t 1 && -z ${NO_COLOR-} ]] && use_color=1 ;;
  esac

  # Only refs/remotes/REMOTE/ is written or pruned: the refspec is given, and --refmap= keeps the
  # configured one (which may map into refs/heads/) out of it; with a refspec on the command line
  # git ignores fetch.pruneTags too.
  hub::git fetch --prune --quiet --refmap= "$remote" "+refs/heads/*:refs/remotes/$remote/*" || exit

  # The snapshot every decision and every conditional update is based on. REMOTE's default branch
  # is looked up when a gone branch first needs it: it may cost a gh call.
  local default='' default_oid='' have_default=0 current='' failed=0
  current=$(hub::current_branch) || current=''
  local -A checked_out=() branch_remote=() branch_merge=() local_section=() remote_oid=()
  _hub_sync_checked_out checked_out
  _hub_sync_branch_config branch_remote branch_merge local_section
  _hub_sync_remote_tips remote_oid "$remote"

  local ref oid short type symref name tracks up_ref up
  while IFS=$'\x1f' read -r -u 3 ref oid short type symref; do
    name=${ref#refs/heads/}
    if [[ -n $symref ]]; then
      hub::warn "warning: '$name' is a symbolic ref to '${symref#refs/heads/}'; skipping it"
      continue
    fi
    [[ $type == commit ]] || continue
    # What the branch is compared with: the branch it tracks on REMOTE, else the one of its name.
    tracks=0 up_ref='' up=''
    if [[ ${branch_remote[$name]-} == "$remote" && -n ${branch_merge[$name]-} ]]; then
      tracks=1
      [[ ${branch_merge[$name]} == refs/heads/?* ]] && up_ref=refs/remotes/$remote/${branch_merge[$name]#refs/heads/}
    else
      up_ref=refs/remotes/$remote/$name
    fi
    [[ -z $up_ref ]] || up=${remote_oid[$up_ref]-}

    if [[ -n $up ]]; then
      [[ $oid == "$up" ]] && continue
      if ! hub::git_query merge-base --is-ancestor "$oid" "$up"; then
        hub::warn "warning: '$name' seems to contain unpushed commits"
        continue
      fi
      if [[ $name == "$current" ]]; then
        _hub_sync_ff_head "$name" "$oid" "$up" || {
          failed=1
          continue
        }
      elif [[ -n ${checked_out[$ref]-} ]]; then
        hub::warn "warning: '$name' is checked out in ${checked_out[$ref]}; not updating it"
        continue
      else
        hub::git update-ref -m "hub sync: fast-forward to ${up_ref#refs/remotes/}" "$ref" "$up" "$oid" || {
          hub::warn "error: '$name' changed while syncing; leaving it alone"
          failed=1
          continue
        }
      fi
      _hub_sync_report "$use_color" Updated "$name" "$short"
    elif ((tracks)); then
      # Deleted on REMOTE, or tracking something that is not one of its branches.
      if ((! have_default)); then
        default=$(hub::default_branch "$remote")
        default_oid=$(hub::git_query rev-parse --verify --quiet "refs/remotes/$remote/$default^{commit}") || default_oid=''
        have_default=1
      fi
      if [[ $name == "$default" ]]; then
        hub::warn "warning: '$name' tracks a branch that is gone from $remote, but it is the default branch; leaving it alone"
        continue
      fi
      if [[ -z $default_oid ]]; then
        [[ -z $up_ref ]] || hub::warn "warning: '$name' was deleted on $remote, but $remote has no '$default' branch to check it against; leaving it alone"
        continue
      fi
      if ! hub::git_query merge-base --is-ancestor "$oid" "$default_oid"; then
        [[ -z $up_ref ]] || hub::warn "warning: '$name' was deleted on $remote, but appears not merged into '$default'"
        continue
      fi
      if [[ $name == "$current" ]]; then
        _hub_sync_switch_default "$remote" "$default" || {
          hub::warn "error: could not switch to '$default' to delete '$name'"
          failed=1
          continue
        }
        current=$default
      elif [[ -n ${checked_out[$ref]-} ]]; then
        hub::warn "warning: '$name' is checked out in ${checked_out[$ref]}; not deleting it"
        continue
      fi
      hub::git update-ref -d "$ref" "$oid" || {
        hub::warn "error: '$name' changed while syncing; leaving it alone"
        failed=1
        continue
      }
      if [[ -n ${local_section[$name]-} ]]; then
        hub::git config --remove-section "branch.$name" || failed=1
      fi
      _hub_sync_report "$use_color" Deleted "$name" "$short"
    fi
  done 3< <(hub::git_query for-each-ref \
    --format='%(refname)%1f%(objectname)%1f%(objectname:short)%1f%(objecttype)%1f%(symref)' refs/heads)
  ((failed == 0)) || exit 1
}

_hub_sync_usage() { hub::die "Usage: hub sync [--color[=WHEN]] [REMOTE]"; }

# _hub_sync_checked_out ARRAY : ARRAY[refs/heads/NAME] is the path of the work tree NAME is
# checked out in (through any chain of symbolic refs, as git reports it).
_hub_sync_checked_out() {
  local -n _out=$1
  local line path=''
  while IFS= read -r -d '' line; do
    case $line in
      'worktree '*) path=${line#worktree } ;;
      'branch '*) _out[${line#branch }]=$path ;;
    esac
  done < <(hub::git_query worktree list --porcelain -z)
}

# _hub_sync_branch_config REMOTES MERGES SECTIONS : REMOTES[NAME] is branch.NAME.remote as git
# sees it (the last value wins) and MERGES[NAME] the first branch.NAME.merge; SECTIONS[NAME] is set
# when the repository's own configuration has a branch.NAME section to remove with the branch.
_hub_sync_branch_config() {
  local -n _remotes=$1 _merges=$2 _sections=$3
  local scope entry key value name
  while IFS= read -r -d '' scope && IFS= read -r -d '' entry; do
    key=${entry%%$'\n'*}
    value=''
    [[ $entry == *$'\n'* ]] && value=${entry#*$'\n'}
    name=${key#branch.}
    name=${name%.*}
    [[ $scope == local ]] && _sections["$name"]=1
    case ${key##*.} in
      remote) _remotes["$name"]=$value ;;
      merge) [[ -n ${_merges[$name]+x} ]] || _merges["$name"]=$value ;;
    esac
  done < <(hub::git_query config -z --show-scope --get-regexp '^branch\..+\.(remote|merge)$')
}

# _hub_sync_remote_tips ARRAY REMOTE : ARRAY[refs/remotes/REMOTE/NAME] is the commit it points at.
_hub_sync_remote_tips() {
  local -n _tips=$1
  local ref oid type
  while IFS=$'\x1f' read -r ref oid type; do
    [[ $type == commit ]] && _tips["$ref"]=$oid
  done < <(hub::git_query for-each-ref --format='%(refname)%1f%(objectname)%1f%(objecttype)' "refs/remotes/$2/")
}

# _hub_sync_ff_head NAME OLD NEW : fast-forward the current branch NAME from OLD to NEW through
# git merge, which keeps the index and work tree consistent and refuses to lose local changes.
# --no-squash beats a configured --squash (branch.NAME.mergeOptions), which would stage the
# changes and leave HEAD alone with a success status; HEAD is checked afterwards all the same.
_hub_sync_ff_head() {
  local name=$1 old=$2 new=$3 head
  if ((! HUB_NOOP)); then
    [[ $(hub::git_query rev-parse --verify --quiet "refs/heads/$name^{commit}") == "$old" && $(hub::current_branch) == "$name" ]] || {
      hub::warn "error: '$name' changed while syncing; leaving it alone"
      return 1
    }
  fi
  hub::git merge --ff-only --no-squash --quiet "$new" || return 1
  ((HUB_NOOP)) && return 0
  head=$(hub::git_query rev-parse --verify --quiet 'HEAD^{commit}')
  [[ $head == "$new" ]] || {
    hub::warn "error: '$name' was not fast-forwarded (still at ${head:0:7}); check its merge configuration"
    return 1
  }
}

# _hub_sync_switch_default REMOTE DEFAULT : make DEFAULT the current branch so that the branch
# that was can be deleted. `git switch` only ever means a branch (a file of that name is never
# restored instead), and a missing local DEFAULT is created from refs/remotes/REMOTE/DEFAULT and
# set to track it, never from another remote through checkout.guess or checkout.defaultRemote.
_hub_sync_switch_default() {
  local remote=$1 default=$2
  if hub::branch_exists "$default"; then
    hub::git switch --quiet --no-guess "$default" || return 1
  else
    hub::git switch --quiet --no-track -c "$default" "refs/remotes/$remote/$default" || return 1
    hub::git config "branch.$default.remote" "$remote" || return 1
    hub::git config "branch.$default.merge" "refs/heads/$default" || return 1
  fi
  ((HUB_NOOP)) && return 0
  [[ $(hub::current_branch) == "$default" ]]
}

# _hub_sync_report COLOR Updated|Deleted NAME SHORT : one line per branch sync changed; nothing
# under --noop, where the commands say it. Green for updates, red for deletions when COLOR is 1.
_hub_sync_report() {
  ((HUB_NOOP)) && return 0
  local c1='' c2='' reset=''
  if (($1)); then
    if [[ $2 == Updated ]]; then c1=$'\e[32m' c2=$'\e[32;1m'; else c1=$'\e[31m' c2=$'\e[31;1m'; fi
    reset=$'\e[0m'
  fi
  printf '%s%s branch %s%s%s (was %s).\n' "$c1" "$2" "$c2" "$3" "$reset" "$4"
}
