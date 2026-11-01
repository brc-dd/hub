# shellcheck shell=bash
# Summary: Apply the changes of a GitHub pull request, commit or comparison.
# Usage: hub apply [GIT-APPLY-OPTIONS...] (URL | PATCH)...
#
# A git command hub extends: git apply's options apply. Every word before -- (or
# --end-of-options) that is the URL of a pull request (.../pull/N or one page of it), a commit
# (.../commit/SHA, .../pull/N/commits/SHA) or a comparison (.../compare/BASE...HEAD) is
# downloaded through gh's API as one diff, with or without a .patch or .diff suffix, and git
# apply gets the file in the URL's place. Nothing is committed: to make commits, use hub am.
# A failed download stops hub before git apply runs. Other URLs, such as one commit's page
# within a pull request (.../pull/N/files/SHA), stay as given. Without such a URL, this is
# plain git apply.
#
#   $ hub apply https://github.com/cli/cli/pull/55
#   > gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.diff'
#   > git apply TMPDIR/hub-apply.XXXXXX/1.diff
#   $ hub apply --index https://github.com/cli/cli/commit/1a2b3c4
#
# git's own manual: git apply --help

hub_cmd_apply() {
  local i n=0 tmp
  local -a args=("$@") urls=()
  for ((i = 0; i < $#; i++)); do
    case ${args[i]} in
      -- | --end-of-options) break ;;
      --help) hub::exec_git apply "$@" ;;
      # -h alone or among git apply's one-letter flags (-Rh) asks for git's usage.
      -*) [[ ! ${args[i]} =~ ^-[3NRqvz]*h ]] || hub::exec_git apply "$@" ;;
      *) if _hub_apply_patch_url "${args[i]}"; then urls+=("$i"); fi ;;
    esac
  done
  ((${#urls[@]})) || hub::exec_git apply "$@"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/hub-apply.XXXXXX") || exit 1
  # shellcheck disable=SC2064  # the path is expanded now, quoted
  trap "rm -rf -- $(printf '%q' "$tmp")" EXIT
  for i in "${urls[@]}"; do
    # Always a diff: git apply reads a patch series as one input, and a file that the series
    # creates and later deletes would stay in the work tree.
    hub::fetch_patch "${args[i]}" diff "$tmp/$((++n)).diff" \
      || hub::die "could not download: ${args[i]}"
    args[i]=$tmp/$n.diff
  done
  hub::git apply "${args[@]}"
}

# _hub_apply_patch_url WORD : WORD is a pull, pull-commit, commit or compare URL GitHub serves.
_hub_apply_patch_url() {
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
