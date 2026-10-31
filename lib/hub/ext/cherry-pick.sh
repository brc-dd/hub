# shellcheck shell=bash
# Summary: Cherry-pick a commit from GitHub by its URL, or from a fork as USER@SHA.
# Usage: hub cherry-pick [<git-cherry-pick options>] (COMMIT-URL | USER@SHA | <commit>)...
#
# A git command hub extends: git cherry-pick's options apply, and hub recognizes two operand
# forms before `--`: the URL of a GitHub commit (.../commit/SHA, or .../pull/N/commits/SHA), and
# USER@SHA, a commit in USER's fork of the current project. hub fetches each such commit from its
# repository, through a remote that points there if there is one, and runs git cherry-pick with
# the commit's full id in its place and every other argument as given.
#
# For a pull request's commit, hub fetches the pull request's head (refs/pull/N/head) and looks
# the commit up in that history only, never among local branches or tags that happen to share
# its prefix; a commit no longer in it (the head was force-pushed) is fetched by its full id,
# which gh looks up for a short one. For the other forms a short SHA is expanded through gh
# first, since GitHub serves a commit that no ref advertises only by its full id. A USER@SHA that
# is also a local revision (a branch or tag of that name) is git's, and so is anything else.
#
#   $ hub cherry-pick https://github.com/jingweno/gh/commit/a319d88
#   > git fetch --no-tags https://github.com/jingweno/gh.git a319d88...
#   > git cherry-pick a319d88...
#
#   $ hub cherry-pick https://github.com/jingweno/gh/pull/73/commits/a319d88
#   > git fetch --no-tags origin refs/pull/73/head
#   > git cherry-pick a319d88...

hub_ext_cherry_pick() {
  local -a args=("$@") picks=()
  local arg i value=0
  for i in "${!args[@]}"; do
    arg=${args[i]}
    if ((value)); then
      value=0
    elif [[ $arg == -- ]]; then
      break
    elif [[ $arg == -?* ]]; then
      case $arg in
        --help) hub::usage ;;
        --cleanup | --mainline | --strategy | --strategy-option | --empty) value=1 ;;
        --*) ;;
        *) [[ $arg =~ ^-[^mX]*[mX]$ ]] && value=1 ;; # -m or -X last in a cluster takes the next argument
      esac
    elif _hub_cherry_pick_shorthand "$arg"; then
      picks+=("$i")
    fi
  done
  ((${#picks[@]})) || hub::exec_git cherry-pick "$@"
  for i in "${picks[@]}"; do
    _hub_cherry_pick_resolve "${args[i]}" || exit
    args[i]=$HUB_PICK_OID
  done
  hub::exec_git cherry-pick "${args[@]}"
}

# _hub_cherry_pick_shorthand ARG : a GitHub commit URL, or USER@SHA when no local revision of that name exists.
_hub_cherry_pick_shorthand() {
  if hub::parse_github_url "$1"; then
    [[ -n $HUB_URL_SHA && ($HUB_URL_KIND == commit || $HUB_URL_KIND == pull) ]]
  else
    [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*@[0-9A-Fa-f]{7,40}$ ]] && ! hub::git_query rev-parse --verify --quiet "$1^{commit}" >/dev/null
  fi
}

# _hub_cherry_pick_resolve ARG : fetch the commit a shorthand names; HUB_PICK_OID is its full id.
# Returns git's status when a fetch fails; dies when the commit cannot be found.
_hub_cherry_pick_resolve() {
  local arg=$1 owner repo host sha number='' src
  HUB_PICK_OID=''
  if hub::parse_github_url "$arg"; then
    owner=$HUB_URL_OWNER repo=$HUB_URL_REPO host=$HUB_URL_HOST sha=${HUB_URL_SHA,,}
    [[ $HUB_URL_KIND == pull ]] && number=$HUB_URL_NUMBER
  else
    owner=${arg%%@*} sha=${arg##*@} sha=${sha,,}
    hub::main_project >/dev/null
    repo=${HUB_PROJECT#*/} host=$HUB_PROJECT_HOST
  fi
  src=$(hub::remote_for_project "$owner/$repo" "$host") || src=$(hub::git_url "$owner/$repo" "$host")
  if [[ -n $number ]]; then
    hub::git fetch --no-tags "$src" "refs/pull/$number/head" || return
    if ((HUB_NOOP)); then # nothing was fetched to look the commit up in
      HUB_PICK_OID=$sha
      return 0
    fi
    HUB_PICK_OID=$(_hub_cherry_pick_in_history "$sha" FETCH_HEAD) && return 0
  fi
  if [[ ! $sha =~ ^[0-9a-f]{40}$ ]]; then
    if ! sha=$(hub::gh_query api --hostname "$host" "repos/$owner/$repo/commits/$sha" --jq .sha) || [[ -z $sha ]]; then
      [[ -z $number ]] || hub::die "Aborted: could not find commit $arg; it is not in the pull request's current head (force-pushed?) and gh could not look it up"
      hub::die "Aborted: could not find commit $arg"
    fi
  fi
  hub::git fetch --no-tags "$src" "$sha" || return
  HUB_PICK_OID=$sha
}

# _hub_cherry_pick_in_history PREFIX TIP : print the id of the one commit reachable from TIP whose id
# starts with PREFIX. Objects only: a branch or tag named like PREFIX is never considered.
_hub_cherry_pick_in_history() {
  local c found=''
  while IFS= read -r c; do
    [[ $(hub::git_query cat-file -t "$c") == commit ]] || continue
    hub::git_query merge-base --is-ancestor "$c" "$2" || continue
    [[ -z $found ]] || return 1 # ambiguous
    found=$c
  done < <(hub::git_query rev-parse --disambiguate="$1")
  [[ -n $found ]] && printf '%s\n' "$found"
}
