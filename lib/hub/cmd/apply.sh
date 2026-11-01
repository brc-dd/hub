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
#   $ hub apply --index https://github.com/cli/cli/pull/7
#   > gh api --hostname github.com repos/cli/cli/pulls/7 -H 'Accept: application/vnd.github.diff'
#   > git apply --index TMPDIR/hub-apply.XXXXXX/1.diff
#
# git's own manual: git apply --help

hub_cmd_apply() {
  local word found=''
  for word; do
    case $word in
      -- | --end-of-options) break ;;
      --help | --help-all) hub::exec_git apply "$@" ;;
      # -h alone or among git apply's one-letter flags (-Rh) asks for git's usage.
      -*) [[ ! $word =~ ^-[3NRqvz]*h ]] || hub::exec_git apply "$@" ;;
      *) ! hub::patch_url "$word" || found=1 ;;
    esac
  done
  [[ -n $found ]] || hub::exec_git apply "$@"
  # Always a diff: git apply reads a patch series as one input, and a file that the series
  # creates and later deletes would stay in the work tree.
  hub::download_patches diff "$@"
  hub::git apply "${HUB_ARGS[@]}"
}
