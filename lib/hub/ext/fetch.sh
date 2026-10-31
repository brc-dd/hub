# shellcheck shell=bash
# Summary: Fetch from GitHub users' forks, adding remotes for them first.
# Usage: hub fetch [<git-fetch options>] USER[,USER...] [<refspec>...]
#        hub fetch --multiple [<git-fetch options>] (USER | REMOTE | GROUP)...
#
# A git command hub extends: git fetch's options apply, and hub recognizes one operand, the
# repository: a GitHub USER, or a comma-separated list of them. For each USER that is not yet a
# remote or remote group, hub adds a remote named USER that points at USER's copy of the current
# project (as `hub remote add USER` does), then runs git fetch with the arguments as given; a
# list becomes its members in its place, with --multiple put first on the command line (before
# any `--`). With --multiple (or -m) in effect, every operand is a remote, a group or a USER. The
# last of --multiple and --no-multiple on the command line counts, as in git; when it is
# --no-multiple, a list is one repository name for git, and goes to it unchanged. Nothing is
# looked up on GitHub, and git's --dry-run does not stop hub from adding the remotes.
#
# An operand goes to git unchanged when it is an existing remote or remote group, whatever its
# name (a remote called `alice,bob` is never split, and one defined in the legacy .git/remotes
# or .git/branches files is a remote too), when git could read it as a local path (an existing
# path, or NAME.git holding a repository), or when it is not a GitHub login (letters, digits,
# - and _). A list with an empty member, or a member that is neither a remote nor a login, is
# an error, found before any remote is added. REPO is the current project's name: GH_REPO, else
# the upstream, github or origin remote, else the work tree's directory. A remote in the legacy
# files is never the current project; `git remote add` it to make it one.
#
# hub reads git fetch's options as the installed git does, from the option table git keeps for
# its completion: which ones take a value (--depth 1, -j 4, in clusters too) and what an
# abbreviation stands for (--dep 1). An option git would refuse leaves the command line to git.
#
#   $ hub fetch jingweno,mislav --prune
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git remote add mislav https://github.com/mislav/REPO.git
#   > git fetch --multiple jingweno mislav --prune
#
#   $ hub fetch --multiple origin jingweno
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   > git fetch --multiple origin jingweno

hub_ext_fetch() {
  local -a args=("$@") operands=() members=() missing=()
  local -A seen=()
  local arg i name rest opt value=0 ended=0 multiple=0 negated=0 all=0 host repo proto
  for i in "${!args[@]}"; do
    arg=${args[i]}
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      operands+=("$i")
    else
      case $arg in
        --) ended=1 ;;
        --help) hub::usage ;;
        *)
          hub::git_option fetch jo '' "$arg" || hub::exec_git fetch "$@" # an option git refuses
          for opt in "${HUB_OPTS[@]}"; do
            case $opt in
              --multiple | -m) multiple=1 negated=0 ;;
              --no-multiple) multiple=0 negated=1 ;;
              --all) all=1 ;;
              --no-all) all=0 ;;
            esac
          done
          ((HUB_OPT_NEXT)) && value=1
          ;;
      esac
    fi
  done
  ((all == 0 && ${#operands[@]})) || hub::exec_git fetch "$@"
  if ((multiple)); then
    for i in "${operands[@]}"; do
      name=${args[i]}
      _hub_fetch_is_remote "$name" && continue
      hub::local_source "$name" && hub::exec_git fetch "$@" # git's to make what it can of
      _hub_fetch_is_user "$name" || hub::exec_git fetch "$@"
      [[ -n ${seen[$name]-} ]] || missing+=("$name")
      seen[$name]=1
    done
  else
    i=${operands[0]} name=${args[i]}
    if _hub_fetch_is_remote "$name" || hub::local_source "$name"; then hub::exec_git fetch "$@"; fi
    if [[ $name == *,* ]]; then
      ((negated)) && hub::exec_git fetch "$@" # --no-multiple: one repository, however it is named
      rest=$name,
      while [[ -n $rest ]]; do
        arg=${rest%%,*} rest=${rest#*,}
        [[ -n $arg ]] || hub::die "hub fetch: empty name in the list '$name'"
        members+=("$arg")
        _hub_fetch_is_remote "$arg" && continue
        _hub_fetch_is_user "$arg" || hub::die "hub fetch: '$arg' in the list '$name' is neither a remote nor a GitHub user"
        [[ -n ${seen[$arg]-} ]] || missing+=("$arg")
        seen[$arg]=1
      done
      args=(--multiple "${args[@]:0:i}" "${members[@]}" "${args[@]:i+1}")
    elif _hub_fetch_is_user "$name"; then
      missing=("$name")
    else
      hub::exec_git fetch "$@"
    fi
  fi
  if ((${#missing[@]})); then
    read -r host repo <<<"$(hub::project_or_dir)"
    [[ -n $repo ]] || exit 1
    proto=$(hub::protocol "$host")
    for name in "${missing[@]}"; do
      hub::git remote add "$name" "$(hub::git_url "$name/$repo" "$host" "$proto")" || exit
    done
  fi
  hub::exec_git fetch "${args[@]}"
}

# _hub_fetch_is_remote NAME : git knows NAME as a remote (configured or legacy) or a remote group.
_hub_fetch_is_remote() { hub::remote_exists "$1" || hub::git_query config --get "remotes.$1" >/dev/null; }

# _hub_fetch_is_user NAME : lexically a GitHub login.
_hub_fetch_is_user() { [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; }
