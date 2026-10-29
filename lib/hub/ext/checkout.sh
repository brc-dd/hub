# shellcheck shell=bash
# Summary: Check out a pull request by its URL, through gh.
# Usage: hub checkout PULLREQ-URL [BRANCH]
#        hub checkout [-b BRANCH] [--detach] [--recurse-submodules] PULLREQ-URL
#        hub checkout [git-checkout options] [ARGS...]
#
# With the URL of a GitHub pull request, runs `gh pr checkout`, which fetches
# the pull request and checks it out in a local branch that tracks it, named
# after the pull request's head branch unless BRANCH is given. Of git
# checkout's options only -b, -d/--detach and --recurse-submodules can go with
# a URL, because they mean the same thing to gh. Anything else is plain
# `git checkout`.
#
#   $ hub checkout https://github.com/jingweno/gh/pull/73
#   > gh pr checkout https://github.com/jingweno/gh/pull/73
#
#   $ hub checkout https://github.com/jingweno/gh/pull/73 custom-branch
#   > gh pr checkout https://github.com/jingweno/gh/pull/73 -b custom-branch

hub_ext_checkout() {
  [[ ${1-} == --help ]] && hub::usage
  local arg url=''
  for arg in "$@"; do
    case $arg in
      --) break ;; # pathspecs follow
      http://* | https://*) hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull ]] && {
        url=$arg
        break
      } ;;
    esac
  done
  [[ -n $url ]] || hub::exec_git checkout "$@"

  local branch=''
  local -a flags=() rest=()
  while (($#)); do
    case $1 in
      -b)
        (($# > 1)) || hub::die "Aborted: -b needs a branch name"
        branch=$2
        shift
        ;;
      -b?*) branch=${1#-b} ;;
      -d | --detach) flags+=(--detach) ;;
      --recurse-submodules) flags+=(--recurse-submodules) ;;
      -f | --force)
        hub::die "Aborted: $1 can't be used with a pull request URL. To reset the local branch to the pull request instead, run: gh pr checkout --force $url"
        ;;
      -*) hub::die "Aborted: $1 can't be used with a pull request URL (gh pr checkout accepts -b BRANCH, --detach and --recurse-submodules)" ;;
      *) rest+=("$1") ;;
    esac
    shift
  done
  # What is left must be: URL [BRANCH], with BRANCH not also given as -b.
  if [[ ${rest[0]} != "$url" ]] || ((${#rest[@]} > 2)) || [[ ${#rest[@]} == 2 && (-n $branch || ${rest[1]} == *://*) ]]; then
    hub::die "Usage: hub checkout PULLREQ-URL [BRANCH]"
  fi
  ((${#rest[@]} == 2)) && branch=${rest[1]}

  local -a cmd=(pr checkout "$url")
  [[ -n $branch ]] && cmd+=(-b "$branch")
  hub::exec_gh "${cmd[@]}" "${flags[@]}"
}
