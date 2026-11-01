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
  local i found=0
  local -a args=("$@")
  for ((i = 0; i < $#; i++)); do
    case ${args[i]} in
      -- | --end-of-options) break ;;
      --help | --help-all) hub::exec_git am "$@" ;;
      # -h alone or among git am's one-letter flags (-3h) asks for git's usage.
      -*) [[ ! ${args[i]} =~ ^-[3ciknmqrsu]*h ]] || hub::exec_git am "$@" ;;
      *) ! hub::patch_url "${args[i]}" || found=1 ;;
    esac
  done
  ((found)) || hub::exec_git am "$@"
  hub::require_repo
  # git am refuses new mailboxes during a session: let it say so before anything is fetched.
  [[ ! -d $(hub::git_query rev-parse --git-path rebase-apply) ]] || hub::exec_git am "$@"
  # git am copies the patches into .git/rebase-apply, so the files can go when hub ends.
  hub::download_patches patch "$@"
  hub::git am "${HUB_ARGS[@]}"
}
