# shellcheck shell=bash
# Summary: Open a GitHub compare page for a branch or a range.
# Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[BASE...]HEAD]
#
# Opens https://HOST/OWNER/REPO/compare/RANGE for the current repository, or for OWNER's copy of
# it. Without a range, the current branch is compared with the default branch, or with BASE. The
# branch must be pushed: hub looks for the remote-tracking ref of its push remote, else of the
# main remote, on the compare page's host, and writes FORKOWNER:BRANCH for another owner's copy
# (fetch first if it was pushed from elsewhere). A..B becomes A...B; a range from a ref to itself
# is refused. For a wiki (REPO.wiki), the page is OWNER/REPO/wiki/_compare/RANGE.
#
# Options:
#   -b, --base BASE   Compare against BASE: BASE...HEAD, HEAD defaulting to the current branch.
#   -u, --url         Print the URL instead of opening it.
#   -c, --copy        Copy the URL to the clipboard instead of opening it.
#
#   $ hub compare v1.0..v1.1
#   > open https://github.com/mislav/dotfiles/compare/v1.0...v1.1
#   $ hub compare -u -b develop
#   https://github.com/mislav/dotfiles/compare/develop...feature

hub_cmd_compare() {
  local print=0 copy=0 base='' owner='' range='' page=compare proj host branch url
  local -a args=()
  while (($#)); do
    case $1 in
      -u | --url) print=1 ;;
      -c | --copy) copy=1 ;;
      -b | --base)
        (($# >= 2)) || hub::die "hub compare: $1 needs a BASE"
        base=$2
        shift
        ;;
      --base=*) base=${1#*=} ;;
      -h | --help) hub::usage ;;
      -*) hub::die "hub compare: unknown option: $1" ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  case ${#args[@]} in
    0 | 1) range=${args[0]-} ;;
    2) owner=${args[0]} range=${args[1]} ;;
    *) hub::die "Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[BASE...]HEAD]" ;;
  esac
  hub::main_project >/dev/null
  proj=${owner:-${HUB_PROJECT%%/*}}/${HUB_PROJECT#*/} host=$HUB_PROJECT_HOST

  if [[ -z $range ]]; then
    branch=$(hub::current_branch) \
      || hub::die "Aborted: not currently on any branch; name a branch or a BASE...HEAD range to compare."
    if [[ -z $base && $branch == "$(hub::default_branch)" ]]; then
      hub::die "Aborted: $branch is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
    fi
    range=$(_hub_compare_head "$branch" "$host" "${proj%%/*}") \
      || hub::die "Aborted: the branch '$branch' is not pushed to any GitHub remote; push it first or name a range"
  elif [[ $range == *..* ]]; then
    [[ -z $base ]] || hub::die "Aborted: use either -b BASE or a range, not both."
    [[ $range == *...* ]] || range=${range/../...}
  fi
  [[ -z $base ]] || range=$base...$range
  if [[ $range == *...* && ${range%%...*} == "${range#*...}" ]]; then
    hub::die "Aborted: '${range%%...*}' is both the base and the head; name a different BASE or HEAD"
  fi
  if [[ $proj == */?*.wiki ]]; then proj=${proj%.wiki} page=wiki/_compare; fi
  url=https://$host/$proj/$page/$(hub::url_escape "$range")
  if ((print)); then printf '%s\n' "$url"; fi
  if ((copy)); then hub::copy "$url"; fi
  if ((! print && ! copy)); then hub::open_url "$url"; fi
}

_hub_compare_head() { # BRANCH HOST OWNER : the head, from the remote whose ref shows BRANCH is pushed
  hub::push_target "$1" && _hub_compare_head_in "$HUB_PUSH_REMOTE" "$HUB_PUSH_BRANCH" "$2" "$3" && return 0
  _hub_compare_head_in "$(hub::main_remote)" "$1" "$2" "$3"
}

_hub_compare_head_in() { # REMOTE BRANCH HOST OWNER : BRANCH, or REMOTEOWNER:BRANCH for another owner's copy
  local owner
  hub::git_query show-ref --verify --quiet "refs/remotes/$1/$2" && hub::remote_project "$1" >/dev/null \
    && hub::same_host "$HUB_PROJECT_HOST" "$3" || return 1
  owner=${HUB_PROJECT%%/*}
  if [[ ${owner,,} == "${4,,}" ]]; then printf '%s\n' "$2"; else printf '%s:%s\n' "$owner" "$2"; fi
}
