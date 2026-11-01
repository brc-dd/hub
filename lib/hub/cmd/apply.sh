# shellcheck shell=bash
# Summary: Apply the changes of a GitHub pull request, commit or comparison.
# Usage: hub apply [GIT-APPLY-OPTIONS...] (URL | PATCH)...
#
# A git command hub extends: git apply's options apply. Every operand before -- (or
# --end-of-options) that is the URL of a pull request (.../pull/N or one page of it), a commit
# (.../commit/SHA, .../pull/N/commits/SHA) or a comparison (.../compare/BASE...HEAD) is
# downloaded through gh's API as one diff, with or without a .patch or .diff suffix, and git
# apply gets the file in the URL's place. gh api gets --allow-escape-sequences when it has that
# option. Nothing is committed: to make commits, use hub am. A failed download stops hub before
# git apply runs. Other URLs, such as one commit's page within a pull request
# (.../pull/N/files/SHA), stay as given. Without such a URL, this is plain git apply.
#
#   $ hub apply https://github.com/cli/cli/pull/55
#   > gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.diff'
#   > git apply TMPDIR/hub-apply.XXXXXX/1.diff
#   $ hub apply --index https://github.com/cli/cli/pull/7
#   > gh api --hostname github.com repos/cli/cli/pulls/7 -H 'Accept: application/vnd.github.diff'
#   > git apply --index TMPDIR/hub-apply.XXXXXX/1.diff
#
# git's own manual: git apply --help

hub_cmd_apply() {
  local valued='-p -C --exclude --include --directory --whitespace --build-fake-ancestor'
  local i end=$# urls=''
  local -a args=("$@")
  hub::scan "$valued" "$@"
  for i in "${HUB_OPTIONS[@]}"; do
    case ${args[i]} in -- | --end-of-options) end=$i && break ;; esac
  done
  for i in "${HUB_OPERANDS[@]}"; do
    ((i < end)) && hub::patch_url "${args[i]}" && urls+=" $i"
  done
  [[ -n $urls ]] || hub::exec_git apply "$@"
  # Always a diff: git apply reads a patch series as one input, and a file that the series
  # creates and later deletes would stay in the work tree.
  hub::download_patches diff "$urls" "$@"
  hub::git apply "${HUB_ARGS[@]}"
}
