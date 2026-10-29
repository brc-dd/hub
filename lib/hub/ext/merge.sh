# shellcheck shell=bash
# Summary: Merge a pull request locally, with the message GitHub's merge button uses.
# Usage: hub merge PULLREQ-URL [git-merge options]
#        hub merge [git-merge options] [COMMIT...]
#
# With the URL of a GitHub pull request, fetches the pull request's head
# (refs/pull/N/head) from its base repository and merges it into the current
# branch, with a merge commit titled "Merge pull request #N from OWNER/BRANCH"
# and the pull request's title as the body. This is a local merge: nothing
# changes on GitHub until you push it. (`gh pr merge` merges on GitHub instead.)
#
# The base repository is fetched through a local remote that points at it, or
# else straight from its URL. --no-ff is implied unless --ff, --ff-only or
# --squash is given, -m or -F replaces the message, and other git-merge options
# are passed on. Without a pull request URL, this is plain `git merge`.
#
#   $ hub merge https://github.com/jingweno/gh/pull/73
#   > git fetch origin refs/pull/73/head
#   > git merge FETCH_HEAD --no-ff -m 'Merge pull request #73 from jingweno/feature ...'

hub_ext_merge() {
  [[ ${1-} == --help ]] && hub::usage
  local arg url='' owner='' repo='' host='' number='' ff=--no-ff own_msg=0 value=0
  local -a args=() others=()
  for arg in "$@"; do
    if ((value)); then
      value=0
      args+=("$arg")
      continue
    fi
    case $arg in
      -m | -F | --message | --file) own_msg=1 value=1 ;;
      -m?* | -F?* | --message=* | --file=*) own_msg=1 ;;
      -s | -X | --strategy | --strategy-option | --cleanup | --into-name) value=1 ;;
      --ff | --ff-only | --squash | --no-ff) ff='' ;;
      -*) ;;
      http://* | https://*)
        if [[ -z $url ]] && hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull ]]; then
          url=$arg owner=$HUB_URL_OWNER repo=$HUB_URL_REPO host=$HUB_URL_HOST number=$HUB_URL_NUMBER
          continue
        fi
        others+=("$arg")
        ;;
      *) others+=("$arg") ;;
    esac
    args+=("$arg")
  done
  [[ -n $url ]] || hub::exec_git merge "$@"
  ((${#others[@]} == 0)) || hub::die "Aborted: a pull request URL can't be merged together with other commits (${others[0]})"
  hub::require_repo

  local msg=''
  if ((! own_msg)); then
    msg=$(hub::gh_query pr view "$url" --json number,title,headRepositoryOwner,headRefName \
      --jq '"Merge pull request #\(.number) from \(.headRepositoryOwner.login)/\(.headRefName)\n\n\(.title)"') \
      && [[ -n $msg ]] || hub::die "Aborted: could not look up pull request $url"
  fi

  local src
  src=$(_hub_merge_remote "$owner/$repo" "$host") || src=$(hub::git_url "$owner/$repo" "$host")
  hub::git fetch "$src" "refs/pull/$number/head" || exit

  local -a cmd=(merge FETCH_HEAD)
  [[ -n $ff ]] && cmd+=("$ff")
  ((own_msg)) || cmd+=(-m "$msg")
  hub::exec_git "${cmd[@]}" "${args[@]}"
}

# _hub_merge_remote OWNER/REPO HOST : the name of a local remote that points at OWNER/REPO on HOST.
_hub_merge_remote() {
  local want="${1,,}"$'\n'"${2,,}" remote found
  while IFS= read -r remote; do
    found=$(hub::remote_project "$remote" && printf '%s\n' "$HUB_PROJECT_HOST") || continue
    [[ ${found,,} == "$want" ]] && {
      printf '%s\n' "$remote"
      return 0
    }
  done < <(hub::git_query remote)
  return 1
}
