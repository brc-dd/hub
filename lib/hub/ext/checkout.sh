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
# the value of an option (-b NAME, --pathspec-from-file FILE) is never taken for the URL. hub
# reads git checkout's options as the installed git does, from the option table git keeps for its
# completion, abbreviations and clusters included (--pathspec-from FILE, --det, -db NAME). An
# option git would refuse leaves the command line to git.
#
# gh runs with GH_HOST set to the URL's host, so that it picks a remote of that host to fetch the
# pull request from, never a same-named repository on another host it is logged in to.
#
#   $ hub checkout https://github.com/jingweno/gh/pull/73 custom-branch
#   > env GH_HOST=github.com gh pr checkout https://github.com/jingweno/gh/pull/73 -b custom-branch

hub_ext_checkout() {
  local -a gh_args=()
  local arg opt url='' host='' value=0 branch='' named=0 seen=0
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif [[ $arg == -- ]]; then
      break # paths follow
    elif [[ $arg == -?* ]]; then
      case $arg in
        --help) hub::usage ;;
        *)
          hub::git_option checkout bBU '' "$arg" || hub::exec_git checkout "$@" # an option git refuses
          ((HUB_OPT_NEXT)) && value=1
          ;;
      esac
    elif hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull ]]; then
      url=$arg host=$HUB_URL_HOST
      break
    fi
  done
  [[ -n $url ]] || hub::exec_git checkout "$@"
  while (($#)); do
    arg=$1
    shift
    if [[ $arg == -?* ]]; then # an option, read as git reads it; -- among them is refused like any other
      hub::git_option checkout bBU '' "$arg" || _hub_checkout_refuse "$arg"
      for opt in "${HUB_OPTS[@]}"; do
        case $opt in
          -b)
            named=1
            if ((HUB_OPT_NEXT)); then
              (($#)) || hub::die "Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]"
              branch=$1
              shift
            else
              branch=${arg#*b} # attached, as in -bNAME or -dbNAME
            fi
            ;;
          -d | --detach) gh_args+=(--detach) ;;
          --recurse-submodules) gh_args+=(--recurse-submodules) ;;
          -f | --force) hub::die "Aborted: $arg can't be used with a pull request URL. To reset the local branch to the pull request instead, run: gh pr checkout --force $url" ;;
          *) _hub_checkout_refuse "$arg" ;;
        esac
      done
    elif [[ $arg == "$url" ]] && ((seen == 0)); then
      seen=1
    elif ((seen == 1)); then
      branch=$arg named=1 seen=2
    else
      hub::die "Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL [BRANCH]"
    fi
  done
  if ((named)); then
    [[ -n $branch ]] || hub::die "Aborted: the branch name is empty"
    gh_args+=(-b "$branch")
  fi
  # gh filters the remotes it may fetch from by GH_HOST; the URL says which host this is about.
  export GH_HOST=$host
  if ((HUB_NOOP)); then
    hub::gh_line env "GH_HOST=$host" gh pr checkout "$url" "${gh_args[@]}"
    exit 0
  fi
  hub::exec_gh pr checkout "$url" "${gh_args[@]}"
}

# _hub_checkout_refuse OPTION : git checkout's OPTION has no counterpart in gh pr checkout.
_hub_checkout_refuse() {
  hub::die "Aborted: $1 can't be used with a pull request URL (gh pr checkout accepts -b BRANCH, --detach and --recurse-submodules)"
}
