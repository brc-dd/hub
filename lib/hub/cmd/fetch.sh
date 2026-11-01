# shellcheck shell=bash
# Summary: Fetch from GitHub users' copies of the project, adding their remotes.
# Usage: hub fetch [GIT-FETCH-OPTIONS...] USER [REFSPEC...]
#        hub fetch [GIT-FETCH-OPTIONS...] USER,USER... [REST...]
#
# A git command hub extends: git fetch's options apply. A first operand that is a GitHub login,
# and not a remote, a remote group or a local repository, names that user's copy of the project
# (the project's repository name, on the project's host). hub checks with gh that it exists,
# adds it as the remote USER (https, or ssh when gh's git_protocol is ssh), then runs git fetch
# with the command line as given. A comma list adds every missing user the same way and fetches
# all members with git fetch --multiple; members that are remotes or groups stay as they are.
# The remote is added before git runs, with --dry-run too. With --multiple, --no-multiple or
# --all, without an operand, or with any other operand, the command line is git's.
#
#   $ hub fetch alice
#   > git remote add alice https://github.com/alice/REPO.git
#   > git fetch alice
#   $ hub fetch --prune alice,origin
#   > git remote add alice https://github.com/alice/REPO.git
#   > git fetch --multiple --prune alice origin
#
# git's own manual: git fetch --help

hub_cmd_fetch() {
  local valued='--depth --deepen --shallow-since --shallow-exclude --refmap -j --jobs -o'
  valued+=' --server-option --upload-pack --negotiation-tip --filter'
  local op name user other project host repo protocol out top
  local -a args=("$@") members missing=()
  hub::scan "$valued" "$@"
  ((${#HUB_OPERANDS[@]})) || hub::exec_git fetch "$@"
  if _hub_fetch_git_only "$@"; then hub::exec_git fetch "$@"; fi
  op=${HUB_OPERANDS[0]} name=${args[op]}
  hub::git_query rev-parse --git-dir >/dev/null || hub::exec_git fetch "$@"
  top=$(hub::toplevel) || top=$(hub::git_query rev-parse --absolute-git-dir)
  if _hub_fetch_remote "$name" || _hub_fetch_local "$top" "$name"; then
    hub::exec_git fetch "$@"
  fi
  # read would stop at a newline and drop the rest of the list.
  [[ $name != *$'\n'* ]] || hub::exec_git fetch "$@"
  if [[ $name == *,* ]]; then
    [[ $name != ,* && $name != *, && $name != *,,* ]] \
      || hub::die "empty name in the list: $(hub::shown "$name")"
    IFS=, read -r -a members <<<"$name"
    for user in "${members[@]}"; do
      [[ $user != -* ]] \
        || hub::die "not a remote name: $(hub::shown "$user")" '(write options outside the list)'
    done
  else
    members=("$name")
  fi
  for user in "${members[@]}"; do
    _hub_fetch_remote "$user" && continue
    hub::is_owner "$user" || hub::exec_git fetch "$@"
    ! _hub_fetch_local "$top" "$user" || hub::exec_git fetch "$@"
    # GitHub logins ignore case, git's remote names do not.
    while read -r other; do
      [[ ${other,,} != "${user,,}" ]] \
        || hub::die "$user is not a remote, but $other is (use $other)"
    done < <(hub::remotes)
    [[ " ${missing[*]} " == *" $user "* ]] || missing+=("$user")
  done
  if ((${#missing[@]})); then
    hub::require_gh
    if project=$(hub::project 2>/dev/null); then
      host=${project%% *} repo=${project##* }
    else
      host=$(hub::host) && repo=$(hub::repo_name) || exit 1
    fi
    for user in "${missing[@]}"; do
      out=$(gh repo view "$host/$user/$repo" --json name 2>&1) && continue
      # gh's answer for a missing repository; an auth or network failure is relayed as it is.
      [[ $out == *'Could not resolve to a Repository'* ]] || { printf '%s\n' "$out" >&2 && exit 1; }
      hub::die "$user is not a remote, and $host/$user/$repo does not exist"
    done
    protocol=$(hub::protocol "$host")
    for user in "${missing[@]}"; do
      hub::git remote add "$user" "$(hub::clone_url "$host" "$user" "$repo" "$protocol")" || exit
    done
  fi
  ((${#members[@]} > 1)) || hub::exec_git fetch "$@"
  hub::exec_git fetch --multiple "${args[@]:0:op}" "${members[@]}" "${args[@]:op+1}"
}

# _hub_fetch_remote NAME : NAME is a remote or a remote group.
_hub_fetch_remote() {
  hub::remote_exists "$1" || hub::git_query config --get "remotes.$1" >/dev/null
}

# _hub_fetch_local TOP NAME : git would read NAME as a local repository, from here or from TOP
# (git resolves a relative path from the top of the work tree).
_hub_fetch_local() {
  hub::local_source "$2" || (cd "$1" && hub::local_source "$2")
}

# _hub_fetch_git_only ARGS... : one of the option words (HUB_OPTIONS) makes the line git's.
_hub_fetch_git_only() {
  local i word name
  local -a args=("$@")
  for i in "${HUB_OPTIONS[@]}"; do
    word=${args[i]%%=*}
    case $word in
      --recurse-submodules) ;;
      --?*)
        # git expands abbreviations (--mul); the last two are hidden and take a separate value.
        for name in --multiple --no-multiple --all --submodule-prefix \
          --recurse-submodules-default; do
          [[ $name != "$word"* ]] || return 0
        done
        ;;
      # -qm is --multiple. An attached value spelled with m also sends the line to git.
      -?*) [[ $word != *m* ]] || return 0 ;;
    esac
  done
  return 1
}
