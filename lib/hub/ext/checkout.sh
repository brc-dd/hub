# shellcheck shell=bash
# Summary: Check out a pull request by its URL, through gh.
# Usage: hub checkout PULLREQ-URL [BRANCH]
#        hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULLREQ-URL
#        hub checkout [<git-checkout arguments>]
#
# Runs `gh pr checkout`, which fetches the pull request and checks it out in a
# branch that tracks it: BRANCH, else one named after its head branch. Other git
# checkout options are refused with a URL; -f because gh's --force resets the
# local branch. Without a pull request URL, this is plain git checkout.
#
#   $ hub checkout https://github.com/jingweno/gh/pull/73 custom-branch
#   > gh pr checkout https://github.com/jingweno/gh/pull/73 -b custom-branch

hub_ext_checkout() {
  [[ ${1-} == --help ]] && hub::usage
  local arg url=''
  for arg in "$@"; do
    [[ $arg == -- ]] && break # paths follow
    hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull ]] && url=$arg && break
  done
  [[ -n $url ]] || hub::exec_git checkout "$@"
  local -a flags=() rest=()
  while (($#)); do
    case $1 in
      -b) flags+=(-b "${@:2:1}") && shift ;;
      -b?*) flags+=(-b "${1#-b}") ;;
      -d | --detach) flags+=(--detach) ;;
      --recurse-submodules) flags+=("$1") ;;
      -f | --force) hub::die "Aborted: $1 can't be used with a pull request URL. To reset the local branch to the pull request instead, run: gh pr checkout --force $url" ;;
      -*) hub::die "Aborted: $1 can't be used with a pull request URL (gh pr checkout accepts -b BRANCH, --detach and --recurse-submodules)" ;;
      *) rest+=("$1") ;;
    esac
    shift
  done
  [[ ${rest[0]} == "$url" && ${#rest[@]} -le 2 ]] || hub::die "Usage: hub checkout PULLREQ-URL [BRANCH]"
  hub::exec_gh pr checkout "$url" "${flags[@]}" ${rest[1]:+-b "${rest[1]}"}
}
