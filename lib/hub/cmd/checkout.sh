# shellcheck shell=bash
# Summary: Check out a pull request, or run git checkout.
# Usage: hub checkout [-b BRANCH] [-d | --detach] [--recurse-submodules] PULL-REQUEST-URL [BRANCH]
#        hub checkout GIT-CHECKOUT-ARGS...
#
# A git command hub extends: git checkout's options apply. A pull request URL (any page of it)
# before -- (or --end-of-options) makes the line hub's: gh pr checkout fetches the pull request
# and checks it out in a local branch, BRANCH when given. Only the options below go with a URL.
# Without a URL, this is plain git checkout. gh runs with GH_HOST set to the URL's host, so
# that it fetches from a local remote of that host.
#
# Options:
#   -b BRANCH                  Name the local branch (the same as the BRANCH operand).
#   -d, --detach               Check out the pull request's head commit without a branch.
#       --recurse-submodules   Update the submodules too.
#
#   $ hub checkout https://github.com/rails/rails/pull/42 review
#   > gh pr checkout https://github.com/rails/rails/pull/42 -b review
#   $ hub checkout main
#   > git checkout main
#
# git's own manual: git checkout --help

hub_cmd_checkout() {
  local word only found=0 url='' host='' detach=0 recurse=0 branch operand
  local -a gh_args=()
  for word; do
    case $word in
      -- | --end-of-options) break ;;
      --help | --help-all) hub::exec_git checkout "$@" ;;
      # -h alone or among git checkout's one-letter flags (-qh) asks for git's usage.
      -*) [[ ! $word =~ ^-[lqmdtf23p]*h ]] || hub::exec_git checkout "$@" ;;
    esac
    if ((! found)) && hub::pull_url "$word"; then found=1; fi
  done
  ((found)) || hub::exec_git checkout "$@"
  while (($#)); do
    case $1 in
      -b)
        (($# > 1)) || hub::usage_error '-b needs a value'
        [[ -n $2 ]] || hub::usage_error '-b needs a branch name'
        branch=$2 && shift
        ;;
      -b?*) branch=${1#-b} ;;
      -d | --detach) detach=1 ;;
      --recurse-submodules) recurse=1 ;;
      -f | --force)
        hub::die "$1 discards local changes in git; gh pr checkout --force resets the branch to" \
          'the pull request instead (run it yourself)'
        ;;
      -?*)
        only='gh pr checkout takes -b BRANCH, --detach and --recurse-submodules only'
        hub::usage_error "unknown option: $(hub::shown "$1") ($only)"
        ;;
      '') hub::die 'the branch name is empty' ;;
      *)
        if hub::pull_url "$1"; then
          [[ -z $url ]] || hub::usage_error "unexpected argument: $(hub::shown "$1")"
          url=$1 host=${HUB_URL[host]}
        elif [[ -n $url && -z ${operand+set} ]]; then
          operand=$1
        else
          hub::usage_error "unexpected argument: $(hub::shown "$1")"
        fi
        ;;
    esac
    shift
  done
  [[ -n $url ]] || hub::usage_error 'the pull request URL is missing'
  if [[ -n ${operand+set} ]]; then
    [[ -z ${branch+set} ]] || hub::usage_error \
      "unexpected argument: $(hub::shown "$operand") (-b names the branch already)"
    branch=$operand
  fi
  if [[ -n ${branch+set} ]]; then
    _hub_checkout_valid_branch "$branch" \
      || hub::die "not a valid branch name: $(hub::shown "$branch")"
    gh_args+=(-b "$branch")
  fi
  ((! detach)) || gh_args+=(--detach)
  ((! recurse)) || gh_args+=(--recurse-submodules)
  # gh considers only the local remotes on GH_HOST when it is set.
  GH_HOST=$host hub::exec_gh pr checkout "$url" "${gh_args[@]}"
}

# _hub_checkout_valid_branch NAME : gh's fetch and checkout make and check out the branch NAME.
_hub_checkout_valid_branch() {
  # Not an option, an @{-N} expansion or another ref namespace.
  [[ $(hub::git_query check-ref-format --branch "$1") == "$1" ]] \
    && [[ ! $1 =~ ^(refs|heads|tags|remotes)/ ]]
}
