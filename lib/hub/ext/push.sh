# shellcheck shell=bash
# Summary: Push to several remotes at once.
# Usage: hub push REMOTE1,REMOTE2[,...] [<git-push arguments>]
#
# A git command hub extends: git push's options apply, and hub recognizes one operand, the
# repository, when it is a comma-separated list of remotes. It runs git push once per remote, in
# the list's order, with every other argument in place, and stops at the first failure. When the
# list is the whole command line, the current branch is pushed; otherwise the arguments go as
# given, so without a refspec git's push.default decides what each push sends.
#
# The list is split only when it names no existing remote (a remote called `one,two` is pushed
# to as such), git could not read it as a local path, and it has no colon (URLs are never lists);
# `--` only ends the options, so a list after it is still the list. Every member must be a name:
# an empty member, or one that starts with -, is an error, found before anything is pushed.
# Anything else is plain git push.
#
# hub reads git push's options as the installed git does, from the option table git keeps for
# its completion: which ones take a value (--push-option x, -o x) and what an abbreviation stands
# for (--rec check). An option git would refuse leaves the command line to git.
#
#   $ hub push origin,staging
#   > git push origin CURRENT-BRANCH
#   > git push staging CURRENT-BRANCH
#
#   $ hub push --tags origin,staging
#   > git push --tags origin
#   > git push --tags staging

hub_ext_push() {
  local -a args=("$@") remotes=()
  local arg i value=0 ended=0 pos=-1 list rest remote branch
  for i in "${!args[@]}"; do
    arg=${args[i]}
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      ((pos >= 0)) || pos=$i
    else
      case $arg in
        --) ended=1 ;;
        --help) hub::usage ;;
        *)
          hub::git_option push o '' "$arg" || hub::exec_git push "$@" # an option git refuses
          ((HUB_OPT_NEXT)) && value=1
          ;;
      esac
    fi
  done
  if ((pos < 0)) || [[ ${args[pos]} != *,* || ${args[pos]} == *:* ]] || hub::remote_exists "${args[pos]}" || hub::local_source "${args[pos]}"; then
    hub::exec_git push "$@"
  fi
  list=${args[pos]} rest=$list,
  while [[ -n $rest ]]; do
    remote=${rest%%,*} rest=${rest#*,}
    [[ -n $remote ]] || hub::die "hub push: empty remote name in the list '$list'"
    [[ $remote != -* ]] || hub::die "hub push: '$remote' in the list '$list' is not a remote name"
    remotes+=("$remote")
  done
  if ((${#args[@]} == 1)); then
    branch=$(hub::current_branch) || hub::die "Aborted: not currently on any branch."
    args+=("$branch")
  fi
  for remote in "${remotes[@]}"; do
    hub::git push "${args[@]:0:pos}" "$remote" "${args[@]:pos+1}" || exit
  done
}
