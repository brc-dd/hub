# shellcheck shell=bash
# Summary: Check out a pull request by its URL, through gh.
# Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]
#        hub checkout [<git-checkout arguments>]
#
# A git command hub extends: git checkout's options apply, and hub recognizes one operand, the
# URL of a GitHub pull request, anywhere before `--`. It then runs `gh pr checkout`, which
# fetches the pull request and checks it out in a branch that tracks it: BRANCH (the last of
# -b BRANCH and the operand after the URL), else one named after its head branch. An empty
# BRANCH is an error. The other git checkout options are refused with a URL; -f because gh's
# --force resets the local branch. Without a pull request URL this is plain git checkout, and
# the value of an option (-b NAME, --pathspec-from-file FILE) is never taken for the URL.
#
# hub finds the operand by knowing which of git checkout's options take a value (git 2.54). An
# abbreviated long option (--pathspec-from FILE for --pathspec-from-file FILE) is not recognized,
# so its value would be taken for an operand: spell options out.
#
#   $ hub checkout https://github.com/jingweno/gh/pull/73 custom-branch
#   > gh pr checkout https://github.com/jingweno/gh/pull/73 -b custom-branch

hub_ext_checkout() {
  local -a gh_args=()
  local arg url='' value=0 branch='' named=0 seen=0
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif [[ $arg == -- ]]; then
      break # paths follow
    elif [[ $arg == -?* ]]; then
      case $arg in
        --help) hub::usage ;;
        -b | -B | --conflict | --orphan | -U | --unified | --inter-hunk-context | --pathspec-from-file) value=1 ;;
        --*) ;;
        *) [[ $arg =~ ^-[^bBU]*[bBU]$ ]] && value=1 ;; # -b, -B or -U last in a cluster takes the next argument
      esac
    elif hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull ]]; then
      url=$arg
      break
    fi
  done
  [[ -n $url ]] || hub::exec_git checkout "$@"
  while (($#)); do
    case $1 in
      -b)
        (($# > 1)) || hub::die "Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]"
        branch=$2 named=1
        shift
        ;;
      -b?*) branch=${1#-b} named=1 ;;
      -d | --detach) gh_args+=(--detach) ;;
      --recurse-submodules) gh_args+=("$1") ;;
      -f | --force) hub::die "Aborted: $1 can't be used with a pull request URL. To reset the local branch to the pull request instead, run: gh pr checkout --force $url" ;;
      -?*) hub::die "Aborted: $1 can't be used with a pull request URL (gh pr checkout accepts -b BRANCH, --detach and --recurse-submodules)" ;;
      *)
        if [[ $1 == "$url" ]] && ((seen == 0)); then
          seen=1
        elif ((seen == 1)); then
          branch=$1 named=1 seen=2
        else
          hub::die "Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]"
        fi
        ;;
    esac
    shift
  done
  if ((named)); then
    [[ -n $branch ]] || hub::die "Aborted: the branch name is empty"
    gh_args+=(-b "$branch")
  fi
  hub::exec_gh pr checkout "$url" "${gh_args[@]}"
}
