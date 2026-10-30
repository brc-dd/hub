# shellcheck shell=bash
# Summary: Merge a pull request locally, with the message GitHub's merge button uses.
# Usage: hub merge PULLREQ-URL [git-merge options]
#
# Fetches the pull request's head (refs/pull/N/head) from its base repository,
# through a remote that points at it if there is one, and merges it into the
# current branch with --no-ff and the message "Merge pull request #N from
# OWNER/BRANCH" followed by the pull request's title. --ff, --ff-only and
# --squash replace --no-ff; -m and -F replace the message. Nothing changes on
# GitHub until you push (`gh pr merge` merges there). Without a pull request
# URL, this is plain git merge.
#
#   $ hub merge https://github.com/jingweno/gh/pull/73
#   > git fetch origin refs/pull/73/head
#   > git merge FETCH_HEAD --no-ff -m 'Merge pull request #73 from jingweno/feature ...'

hub_ext_merge() {
  [[ ${1-} == --help ]] && hub::usage
  local arg url='' owner repo host number ff=--no-ff msg='' own_msg=0 value=0 src
  local -a args=()
  for arg in "$@"; do
    if ((value)); then
      value=0
    else
      case $arg in
        -m | -F | --message | --file) own_msg=1 value=1 ;;
        -m?* | -F?* | --message=* | --file=*) own_msg=1 ;;
        -s | -X | --strategy | --strategy-option | --cleanup | --into-name) value=1 ;;
        --ff | --ff-only | --squash | --no-ff) ff='' ;;
        *)
          if [[ -z $url ]] && hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull ]]; then
            url=$arg owner=$HUB_URL_OWNER repo=$HUB_URL_REPO host=$HUB_URL_HOST number=$HUB_URL_NUMBER
            continue
          fi
          ;;
      esac
    fi
    args+=("$arg")
  done
  [[ -n $url ]] || hub::exec_git merge "$@"
  if ((! own_msg)); then
    msg=$(hub::gh_query pr view "$url" --json number,title,headRepositoryOwner,headRefName \
      --jq '"Merge pull request #\(.number) from \(.headRepositoryOwner.login)/\(.headRefName)\n\n\(.title)"') \
      || hub::die "Aborted: could not look up pull request $url"
  fi
  src=$(hub::remote_for_project "$owner/$repo" "$host") || src=$(hub::git_url "$owner/$repo" "$host")
  hub::git fetch "$src" "refs/pull/$number/head" || exit
  hub::exec_git merge FETCH_HEAD ${ff:+"$ff"} ${msg:+-m "$msg"} "${args[@]}"
}
