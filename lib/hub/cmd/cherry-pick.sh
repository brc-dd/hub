# shellcheck shell=bash
# Summary: Cherry-pick a commit from its GitHub URL.
# Usage: hub cherry-pick [GIT-CHERRY-PICK-OPTIONS...] (COMMIT-URL | COMMIT)...
#
# A git command hub extends: git cherry-pick's options apply. Every word before -- (or
# --end-of-options) that is the URL of a commit (.../commit/SHA) or of a pull request's commit
# (.../pull/N/commits/SHA) names that commit of the URL's repository: a short id is expanded
# through gh's API, the commit is fetched from the repository (through a remote that points at
# it, else its URL) without tags and without updating any branch or remote-tracking ref (only
# FETCH_HEAD), and git cherry-pick gets the full id in the URL's place. The other words stay as
# given. Without such a URL, this is plain git cherry-pick. hub 2.x's USER@SHA form is not
# supported: paste the commit's URL.
#
#   $ hub cherry-pick https://github.com/jingweno/gh/commit/a319d88
#   > gh api --hostname github.com repos/jingweno/gh/commits/a319d88 --jq .sha
#   > git fetch --quiet --no-tags --refmap= -- https://github.com/jingweno/gh.git FULL-SHA
#   > git cherry-pick FULL-SHA
#
# git's own manual: git cherry-pick --help

hub_cmd_cherry_pick() {
  local i sha
  local -a args=("$@") urls=() hosts=() owners=() repos=() shas=() sources=()
  for ((i = 0; i < $#; i++)); do
    case ${args[i]} in
      -- | --end-of-options) break ;;
      -h | --help) hub::exec_git cherry-pick "$@" ;;
    esac
    hub::parse_github_url "${args[i]}" || continue
    case ${HUB_URL[kind]}:${HUB_URL[number]-} in
      commit:* | pull:?*) [[ -n ${HUB_URL[sha]-} ]] || continue ;;
      *) continue ;;
    esac
    urls+=("$i")
    hosts[i]=${HUB_URL[host]} owners[i]=${HUB_URL[owner]} repos[i]=${HUB_URL[repo]}
    shas[i]=${HUB_URL[sha],,}
  done
  ((${#urls[@]})) || hub::exec_git cherry-pick "$@"
  hub::require_repo
  for i in "${urls[@]}"; do
    sha=${shas[i]}
    if ((${#sha} < 40)); then
      hub::require_gh
      sha=$(gh api --hostname "${hosts[i]}" \
        "repos/${owners[i]}/${repos[i]}/commits/$sha" --jq .sha) || exit 1
      sha=${sha,,}
      [[ $sha =~ ^[0-9a-f]{40}$ ]] || hub::die "no such commit: ${args[i]}"
    elif ((${#sha} > 40)); then
      hub::die "not a commit id: ${args[i]}"
    fi
    args[i]=$sha
    sources[i]=$(hub::fetch_source "${hosts[i]}" "${owners[i]}" "${repos[i]}")
  done
  for i in "${urls[@]}"; do
    hub::git fetch --quiet --no-tags --refmap= -- "${sources[i]}" "${args[i]}" || exit
  done
  hub::exec_git cherry-pick "${args[@]}"
}
