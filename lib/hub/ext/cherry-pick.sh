# shellcheck shell=bash
# Summary: Cherry-pick a commit from GitHub by its URL, or from a fork as USER@SHA.
# Usage: hub cherry-pick [git-cherry-pick options] COMMIT-URL
#        hub cherry-pick [git-cherry-pick options] USER@SHA
#        hub cherry-pick [git-cherry-pick options] COMMIT...
#
# When the last argument is the URL of a GitHub commit (.../commit/SHA or
# .../pull/N/commits/SHA), or USER@SHA for a commit in USER's fork of the
# current project, the commit is fetched first and then cherry-picked. The
# repository is fetched through a local remote that points at it, or else
# straight from its URL; a commit of a pull request is fetched along with the
# pull request's head. Anything else is plain `git cherry-pick`.
#
# A short SHA is first looked up with gh, since the fetch needs the full one.
# gh is asked on the commit's own host (the URL's, or the current project's
# for USER@SHA), even when its default host (GH_HOST, or the only host it is
# logged in to) is another one.
#
#   $ hub cherry-pick https://github.com/jingweno/gh/commit/a319d88
#   > git fetch --no-tags https://github.com/jingweno/gh.git a319d88...  (the full SHA, looked up with gh)
#   > git cherry-pick a319d88...
#
#   $ hub cherry-pick https://github.com/jingweno/gh/pull/73/commits/a319d88
#   > git fetch --no-tags origin refs/pull/73/head
#   > git cherry-pick a319d88

hub_ext_cherry_pick() {
  [[ ${1-} == --help ]] && hub::usage
  (($#)) || hub::exec_git cherry-pick
  local ref=${!#} owner repo host sha fetch='' proj src
  case $ref in
    http://* | https://*)
      hub::parse_github_url "$ref" && [[ -n $HUB_URL_SHA && ($HUB_URL_KIND == commit || $HUB_URL_KIND == pull) ]] \
        || hub::exec_git cherry-pick "$@"
      owner=$HUB_URL_OWNER repo=$HUB_URL_REPO host=$HUB_URL_HOST sha=$HUB_URL_SHA
      [[ $HUB_URL_KIND == pull ]] && fetch=refs/pull/$HUB_URL_NUMBER/head
      hub::require_repo
      ;;
    *@*)
      [[ $ref =~ ^([A-Za-z0-9][A-Za-z0-9-]*)@([0-9A-Fa-f]{7,40})$ ]] || hub::exec_git cherry-pick "$@"
      owner=${BASH_REMATCH[1]} sha=${BASH_REMATCH[2]}
      hub::require_repo
      # A local revision that merely looks like USER@SHA is left to git.
      hub::git_query rev-parse --verify --quiet "$ref^{commit}" >/dev/null && hub::exec_git cherry-pick "$@"
      proj=$(hub::main_project && printf '%s\n' "$HUB_PROJECT_HOST") || exit 1
      repo=${proj%%$'\n'*} host=${proj#*$'\n'}
      repo=${repo#*/}
      ;;
    *) hub::exec_git cherry-pick "$@" ;;
  esac

  if [[ -z $fetch ]]; then
    # Fetch the commit itself. GitHub serves a commit no ref advertises only by its full SHA.
    # Always name the host: gh's default is GH_HOST, or the only host it is logged in to.
    if [[ ! $sha =~ ^[0-9a-f]{40}$ ]]; then
      sha=$(hub::gh_query api --hostname "$host" "repos/$owner/$repo/commits/$sha" --jq .sha) && [[ $sha =~ ^[0-9a-f]{40}$ ]] \
        || hub::die "Aborted: could not find commit $ref"
    fi
    fetch=$sha
  fi
  src=$(_hub_cherry_pick_remote "$owner/$repo" "$host") || src=$(hub::git_url "$owner/$repo" "$host")
  hub::git fetch --no-tags "$src" "$fetch" || exit
  hub::exec_git cherry-pick "${@:1:$#-1}" "$sha"
}

# _hub_cherry_pick_remote OWNER/REPO HOST : the name of a local remote that points at OWNER/REPO on HOST.
_hub_cherry_pick_remote() {
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
