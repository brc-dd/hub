# shellcheck shell=bash
# Summary: Apply the commits of a GitHub pull request, commit or comparison URL.
# Usage: hub am [GIT-AM-OPTIONS...] (URL | MBOX)...
#
# A git command hub extends: git am's options apply. Every word before -- (or --end-of-options)
# that is the URL of a pull request (.../pull/N), a commit (.../commit/SHA, .../pull/N/commits/SHA)
# or a comparison (.../compare/BASE...HEAD), with or without a .patch or .diff suffix, is
# downloaded through gh's API as a patch series, so the commits keep their authors and messages;
# git am gets the file in the URL's place, and the other words stay as given. A failed download
# stops hub before git am runs. Other URLs, such as one commit's page within a pull request
# (.../pull/N/files/SHA), stay as given. Outside a work tree, or while an am session is in
# progress, nothing is downloaded and git am answers. Without such a URL, this is plain git am.
#
#   $ hub am -3 https://github.com/cli/cli/pull/55
#   > gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.patch'
#   > git am -3 TMPDIR/hub-am.XXXXXX/1.patch
#
# git's own manual: git am --help

hub_cmd_am() {
  local i n=0 tmp
  local -a args=("$@") urls=()
  for ((i = 0; i < $#; i++)); do
    case ${args[i]} in
      -- | --end-of-options) break ;;
      --help) hub::exec_git am "$@" ;;
      # -h alone or among git am's one-letter flags (-3h) asks for git's usage.
      -*) [[ ! ${args[i]} =~ ^-[3ciknmqrsu]*h ]] || hub::exec_git am "$@" ;;
      *) if _hub_am_patch_url "${args[i]}"; then urls+=("$i"); fi ;;
    esac
  done
  ((${#urls[@]})) || hub::exec_git am "$@"
  hub::require_repo
  # git am refuses new mailboxes during a session: let it say so before anything is fetched.
  [[ ! -d $(hub::git_query rev-parse --git-path rebase-apply) ]] || hub::exec_git am "$@"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/hub-am.XXXXXX") || exit 1
  # git am copies the patches into .git/rebase-apply, so the files can go when hub ends.
  # shellcheck disable=SC2064  # the path is expanded now, quoted
  trap "rm -rf -- $(printf '%q' "$tmp")" EXIT
  for i in "${urls[@]}"; do
    hub::fetch_patch "${args[i]}" patch "$tmp/$((++n)).patch" \
      || hub::die "could not download: ${args[i]}"
    args[i]=$tmp/$n.patch
  done
  hub::git am "${args[@]}"
}

# _hub_am_patch_url WORD : WORD is a pull, pull-commit, commit or compare URL GitHub serves.
_hub_am_patch_url() {
  local page='^https?://[^/?#]+/[^/?#]+/[^/?#]+/pull/[0-9]+(\.(patch|diff)|/[^/?#]*)?/?([?#]|$)'
  hub::parse_github_url "$1" || return 1
  case ${HUB_URL[kind]} in
    # A deeper page, such as pull/N/files/SHA, shows only some of the pull request's changes.
    pull) [[ -n ${HUB_URL[number]-} ]] && [[ -n ${HUB_URL[sha]-} || $1 =~ $page ]] ;;
    commit) ;;
    # A bare .../compare names no range.
    compare) [[ $1 =~ ^https?://[^/?#]+/[^/?#]+/[^/?#]+/compare/[^/?#] ]] ;;
    *) return 1 ;;
  esac
}
