# shellcheck shell=bash
# Summary: Open a GitHub compare page for a branch or a range.
# Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[BASE...]HEAD]
#
# Opens https://HOST/OWNER/REPO/compare/RANGE for the current repository (GH_REPO, else the one
# the upstream, github or origin remote points at), or for OWNER's copy of it. A..B becomes
# A...B; a range from a ref to itself is refused. With -b, the range is BASE...HEAD, HEAD
# defaulting to the current branch. For a wiki (REPO.wiki), the page is
# OWNER/REPO/wiki/_compare/RANGE.
#
# Without a range, the current branch is compared with the repository's default branch, or with
# BASE. The branch must be pushed: hub looks for its remote-tracking ref on the remote it pushes
# to (the one `git push` would use: remote.*.push, branch.*.pushRemote, remote.pushDefault,
# branch.*.remote, else origin), then on the main remote (fetch first if it was pushed from
# elsewhere). The push URL of that remote names the repository the branch is in, which must be
# on the compare page's host. A branch in another repository is written FORKOWNER:BRANCH, or
# FORKOWNER:FORKREPO:BRANCH when that repository has another name. The branch is refused only
# when it is the compared repository's own default branch; a fork's main compares as
# FORKOWNER:main. The default branch is the one refs/remotes/REMOTE/HEAD names; when it is
# unknown, hub asks gh for it, and assumes main when gh cannot answer.
#
# Options:
#   -b, --base BASE   Compare against BASE: BASE...HEAD, HEAD defaulting to the current branch.
#   -u, --url         Print the URL instead of opening it.
#   -c, --copy        Copy the URL to the clipboard instead of opening it; with -u, print and copy.
#
# When the browser or the clipboard tool fails, its status is the exit status, after the URL
# was printed.
#
#   $ hub compare v1.0..v1.1
#   > open https://github.com/mislav/dotfiles/compare/v1.0...v1.1
#   $ hub compare -u -b develop
#   https://github.com/mislav/dotfiles/compare/develop...feature

hub_cmd_compare() {
  local print=0 copy=0 base='' owner='' range='' page=compare proj host branch url rc=0
  local -a args=()
  hub::normalize_opts b --base "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -u | --url) print=1 ;;
      -c | --copy) copy=1 ;;
      -b | --base)
        (($# >= 2)) || _hub_compare_usage_error "$1 needs a BASE"
        base=$2
        shift
        ;;
      -h | --help) hub::usage ;;
      --)
        shift
        args+=("$@")
        break
        ;;
      -?*) _hub_compare_usage_error "unknown option: $1" ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  case ${#args[@]} in
    0 | 1) range=${args[0]-} ;;
    2) owner=${args[0]} range=${args[1]} ;;
    *) _hub_compare_usage_error "too many arguments" ;;
  esac
  [[ $owner != */* ]] || _hub_compare_usage_error "not an owner: $owner"
  hub::main_project >/dev/null
  proj=${owner:-${HUB_PROJECT%%/*}}/${HUB_PROJECT#*/} host=$HUB_PROJECT_HOST

  if [[ -z $range ]]; then
    branch=$(hub::current_branch) \
      || hub::die "Aborted: not currently on any branch; name a branch or a BASE...HEAD range to compare."
    _hub_compare_head "$branch" "$host" "$proj" \
      || hub::die "Aborted: the branch '$branch' is not pushed to any GitHub remote; push it first or name a range"
    if [[ -z $base && ${HUB_COMPARE_PROJECT,,} == "${proj,,}" ]] \
      && [[ $HUB_COMPARE_BRANCH == "$(hub::default_branch "$HUB_COMPARE_REMOTE")" ]]; then
      hub::die "Aborted: $HUB_COMPARE_BRANCH is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
    fi
    range=$HUB_COMPARE_HEAD
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
  if ((copy)); then hub::copy "$url" || rc=$?; fi
  if ((! print && ! copy)); then hub::open_url "$url" || rc=$?; fi
  return "$rc"
}

_hub_compare_usage_error() {
  hub::die "hub compare: $1"$'\n'"Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[BASE...]HEAD]"
}

# _hub_compare_head BRANCH HOST OWNER/REPO : how to write BRANCH as the head on the compare page of
# OWNER/REPO at HOST, from the first remote whose remote-tracking ref shows the branch there: the
# one the branch pushes to (hub::push_target; when git could not push it as it is, the remote it
# is configured to push to), then the main remote. Sets HUB_COMPARE_HEAD (BRANCH, FORKOWNER:BRANCH
# or FORKOWNER:FORKREPO:BRANCH), HUB_COMPARE_REMOTE, HUB_COMPARE_PROJECT (the repository that
# remote pushes to) and HUB_COMPARE_BRANCH (the branch's name there). Returns 1 when no remote
# on HOST shows the branch.
_hub_compare_head() {
  local branch=$1 host=$2 base=$3 remote
  if hub::push_target "$branch"; then
    _hub_compare_head_in "$HUB_PUSH_REMOTE" "$HUB_PUSH_BRANCH" "$host" "$base" && return 0
  elif remote=$(_hub_compare_push_remote "$branch"); then
    _hub_compare_head_in "$remote" "$branch" "$host" "$base" && return 0
  fi
  remote=$(hub::main_remote) || return 1
  _hub_compare_head_in "$remote" "$branch" "$host" "$base"
}

# _hub_compare_push_remote BRANCH : the remote git is configured to push BRANCH to
# (branch.*.pushRemote, remote.pushDefault, branch.*.remote), else origin, when it exists; for a
# branch `git push` alone would refuse to push, such as one without an upstream.
_hub_compare_push_remote() {
  local remote
  remote=$(hub::git_query for-each-ref --format='%(push:remotename)' -- "refs/heads/$1")
  [[ -n $remote ]] || remote=origin
  hub::remote_exists "$remote" && printf '%s\n' "$remote"
}

# _hub_compare_head_in REMOTE BRANCH HOST OWNER/REPO : REMOTE's remote-tracking ref shows BRANCH,
# and the repository REMOTE pushes to is on HOST; sets the HUB_COMPARE_* variables.
_hub_compare_head_in() {
  local remote=$1 branch=$2 host=$3 base=$4
  hub::git_query show-ref --verify --quiet -- "refs/remotes/$remote/$branch" || return 1
  hub::remote_project "$remote" push >/dev/null || return 1
  hub::same_host "$HUB_PROJECT_HOST" "$host" || return 1
  HUB_COMPARE_REMOTE=$remote HUB_COMPARE_BRANCH=$branch HUB_COMPARE_PROJECT=$HUB_PROJECT
  local head_repo=${HUB_PROJECT#*/} base_repo=${base#*/}
  if [[ ${HUB_PROJECT,,} == "${base,,}" ]]; then
    HUB_COMPARE_HEAD=$branch
  elif [[ ${head_repo,,} == "${base_repo,,}" ]]; then
    HUB_COMPARE_HEAD=${HUB_PROJECT%%/*}:$branch
  else
    HUB_COMPARE_HEAD=${HUB_PROJECT%%/*}:$head_repo:$branch
  fi
}
