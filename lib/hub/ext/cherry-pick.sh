# shellcheck shell=bash
# Summary: Cherry-pick a commit from GitHub by its URL, or from a fork as USER@SHA.
# Usage: hub cherry-pick [git-cherry-pick options] COMMIT-URL
#        hub cherry-pick [git-cherry-pick options] USER@SHA
#
# When the last argument is the URL of a GitHub commit (.../commit/SHA or
# .../pull/N/commits/SHA) or USER@SHA, a commit in USER's fork of the current
# project, hub fetches the commit (for a pull request, its head) through a
# remote that points at its repository if there is one, and cherry-picks it. A
# short SHA is expanded with gh first. Anything else is plain git cherry-pick.
#
#   $ hub cherry-pick https://github.com/jingweno/gh/commit/a319d88
#   > git fetch --no-tags https://github.com/jingweno/gh.git a319d88...
#   > git cherry-pick a319d88...
#
#   $ hub cherry-pick https://github.com/jingweno/gh/pull/73/commits/a319d88
#   > git fetch --no-tags origin refs/pull/73/head
#   > git cherry-pick a319d88

hub_ext_cherry_pick() {
  [[ ${1-} == --help ]] && hub::usage
  local ref=${!#} owner repo host sha fetch='' src
  if hub::parse_github_url "$ref" && [[ -n $HUB_URL_SHA ]]; then
    owner=$HUB_URL_OWNER repo=$HUB_URL_REPO host=$HUB_URL_HOST sha=$HUB_URL_SHA
    [[ $HUB_URL_KIND == pull ]] && fetch=refs/pull/$HUB_URL_NUMBER/head
  elif [[ $ref =~ ^([A-Za-z0-9][A-Za-z0-9-]*)@([0-9A-Fa-f]{7,40})$ ]]; then
    owner=${BASH_REMATCH[1]} sha=${BASH_REMATCH[2]}
    hub::main_project >/dev/null
    repo=${HUB_PROJECT#*/} host=$HUB_PROJECT_HOST
  else
    hub::exec_git cherry-pick "$@"
  fi
  if [[ -z $fetch && ! $sha =~ ^[0-9a-f]{40}$ ]]; then
    # GitHub serves a commit that no ref advertises only by its full SHA.
    sha=$(hub::gh_query api --hostname "$host" "repos/$owner/$repo/commits/$sha" --jq .sha) \
      || hub::die "Aborted: could not find commit $ref"
  fi
  src=$(hub::remote_for_project "$owner/$repo" "$host") || src=$(hub::git_url "$owner/$repo" "$host")
  hub::git fetch --no-tags "$src" "${fetch:-$sha}" || exit
  hub::exec_git cherry-pick "${@:1:$#-1}" "$sha"
}
