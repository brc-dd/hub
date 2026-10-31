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
# For a pull request's commit, hub fetches the pull request's head (refs/pull/N/head) into a
# private ref of this run (FETCH_HEAD is shared with every other fetch in the work tree) and looks
# the commit up in that history only, never among local branches or tags that happen to share
# its prefix; a commit no longer in it (the head was force-pushed) is fetched by its full id,
# which gh looks up for a short one. For the other forms a short SHA is expanded through gh
# first, since GitHub serves a commit that no ref advertises only by its full id. A USER@SHA that
# is also a local revision (a branch or tag of that name) is git's, and so is anything else.
#
# hub reads git cherry-pick's options as the installed git does, from the option table git keeps
# for its completion: -m 1, -X ours and -Skey take their values, in clusters too. git keeps an
# option it does not know for its revision parser, and so does hub.
#
#   $ hub cherry-pick https://github.com/jingweno/gh/commit/a319d88
#   > git fetch --no-tags --refmap= https://github.com/jingweno/gh.git a319d88...
#   > git cherry-pick a319d88...
#
#   $ hub cherry-pick https://github.com/jingweno/gh/pull/73/commits/a319d88
#   > git fetch --no-tags --refmap= origin +refs/pull/73/head:refs/hub/cherry-pick/73-PID
#   > git update-ref -d refs/hub/cherry-pick/73-PID
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
        *)
          hub::git_option cherry-pick mX S "$arg" || true # unknown to git too: kept, for its revision parser
          ((HUB_OPT_NEXT)) && value=1
          ;;
      esac
    elif _hub_cherry_pick_shorthand "$arg"; then
      picks+=("$i")
    fi
  done
  ((${#picks[@]})) || hub::exec_git cherry-pick "$@"
  HUB_PICK_TMP=''
  trap _hub_cherry_pick_cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
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
  local arg=$1 owner repo host sha number='' src tmp
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
    # A ref of this run alone, gone once the commit is known: another fetch in this work tree
    # could replace FETCH_HEAD between the fetch and the lookup. --refmap= keeps git from also
    # writing what the remote's configured refspecs map the pull request to (a
    # +refs/pull/*/head:refs/heads/pull-* refspec would force-update a local branch).
    tmp=refs/hub/cherry-pick/$number-$$
    HUB_PICK_TMP=$tmp
    hub::git fetch --no-tags --refmap= "$src" "+refs/pull/$number/head:$tmp" || return
    if ((HUB_NOOP)); then # nothing was fetched to look the commit up in
      HUB_PICK_OID=$sha
    else
      HUB_PICK_OID=$(_hub_cherry_pick_in_history "$sha" "$tmp") || HUB_PICK_OID=''
    fi
    hub::git update-ref -d "$tmp"
    HUB_PICK_TMP=''
    [[ -z $HUB_PICK_OID ]] || return 0
  fi
  if [[ ! $sha =~ ^[0-9a-f]{40}$ ]]; then
    if ! sha=$(hub::gh_query api --hostname "$host" "repos/$owner/$repo/commits/$sha" --jq .sha) || [[ -z $sha ]]; then
      [[ -z $number ]] || hub::die "Aborted: could not find commit $arg; it is not in the pull request's current head (force-pushed?) and gh could not look it up"
      hub::die "Aborted: could not find commit $arg"
    fi
  fi
  hub::git fetch --no-tags --refmap= "$src" "$sha" || return
  HUB_PICK_OID=$sha
}

# _hub_cherry_pick_cleanup : remove this run's private ref (HUB_PICK_TMP) on the way out.
_hub_cherry_pick_cleanup() {
  [[ -z ${HUB_PICK_TMP-} ]] || hub::git update-ref -d "$HUB_PICK_TMP" 2>/dev/null
  return 0
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
