# shellcheck shell=bash
# Summary: Push to several remotes at once.
# Usage: hub push REMOTE1,REMOTE2[,...] [GIT-PUSH-ARGS...]
#
# A git command hub extends: git push's options apply. When the repository operand is a
# comma-separated list of remotes, hub runs git push once per remote, in order, with that remote
# in the list's place, and stops at the first push that fails; earlier remotes keep what they
# got. Every name in the list must be a remote before anything is pushed. When the list is the
# only operand, hub pushes the current branch under its own name (HEAD), unless an option
# chooses the refs itself (--all, --branches, --mirror, --tags, --delete) or the remote does
# (remote.NAME.push or remote.NAME.mirror). A remote, path or URL whose name contains a comma
# is one destination, and anything else is plain git push.
#
#   $ hub push origin,staging
#   > git push origin HEAD
#   > git push staging HEAD
#   $ hub push -f origin,staging main:release
#   > git push -f origin main:release
#   > git push -f staging main:release
#
# git's own manual: git push --help

hub_cmd_push() {
  local valued='-o --push-option --repo --receive-pack --exec --recurse-submodules'
  local -a args=("$@") remotes=() heads=() flags=()
  local list rest remote at head=0 i flag
  hub::scan "$valued" "$@"
  ((${#HUB_OPERANDS[@]})) || hub::exec_git push "$@"
  at=${HUB_OPERANDS[0]} list=${args[at]}
  [[ $list == *,* && $list != *:* ]] || hub::exec_git push "$@"
  _hub_push_flags "$valued" "$@"
  for flag in "${flags[@]}"; do
    [[ $flag != -h ]] || hub::exec_git push "$@"
  done
  # Outside a repository git says so itself.
  hub::git_query rev-parse --git-dir >/dev/null || hub::exec_git push "$@"
  if hub::remote_exists "$list" || hub::local_source "$list"; then hub::exec_git push "$@"; fi
  if ((${#HUB_OPERANDS[@]} == 1)) && ! _hub_push_chooses_refs "${flags[@]}"; then head=1; fi
  rest=$list,
  while [[ -n $rest ]]; do
    remote=${rest%%,*} rest=${rest#*,}
    [[ -n $remote ]] || hub::die "empty name in the list: $list"
    [[ $remote != -* ]] || hub::die "not a remote name: $remote (write options outside the list)"
    hub::remote_exists "$remote" || hub::die "not a remote: $remote"
    remotes+=("$remote")
    # git push REMOTE uses the remote's own refspecs, and refuses any refspec for a mirror.
    if ((head)) && [[ $(hub::git_query config --type=bool remote."$remote".mirror) != true ]] \
      && ! hub::git_query config --get-all remote."$remote".push >/dev/null; then
      heads+=(HEAD)
    else
      heads+=('')
    fi
  done
  for i in "${!remotes[@]}"; do
    args[at]=${remotes[i]}
    hub::git push "${args[@]}" ${heads[i]:+"${heads[i]}"} || return
  done
}

# _hub_push_flags VALUED ARGS... : the caller's array flags, the option words of ARGS without
# the values of VALUED options, up to -- or --end-of-options.
_hub_push_flags() {
  local valued=" $1 " word value=0
  shift
  for word; do
    if ((value)); then
      value=0
    elif [[ $word == -- || $word == --end-of-options ]]; then
      return 0
    elif [[ $valued == *" $word "* ]]; then
      value=1
    elif [[ $word == -?* ]]; then
      flags+=("$word")
    fi
  done
}

# _hub_push_chooses_refs FLAGS... : a flag pushes or deletes refs of its own choosing, so HEAD
# must not be added; abbreviations and -d in a cluster count.
_hub_push_chooses_refs() {
  local word long
  for word; do
    case $word in
      --?*)
        for long in --all --branches --mirror --tags --delete; do
          [[ $long != "${word%%=*}"* ]] || return 0
        done
        ;;
      # -o takes the rest of the cluster as its value.
      -*) [[ ${word%%o*} != -*d* ]] || return 0 ;;
    esac
  done
  return 1
}
