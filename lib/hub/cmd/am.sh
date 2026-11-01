# shellcheck shell=bash
# Summary: Apply the commits of a GitHub pull request, commit or comparison.
# Usage: hub am [GIT-AM-OPTIONS...] (URL | MBOX)...
#
# A git command hub extends: git am's options apply. Every operand before -- (or
# --end-of-options) that is the URL of a pull request (.../pull/N), a commit (.../commit/SHA,
# .../pull/N/commits/SHA) or a comparison (.../compare/BASE...HEAD), with or without a .patch or
# .diff suffix, is downloaded through gh's API as a patch series, so the commits keep their
# authors and messages; git am gets the file in the URL's place, and the other words stay as
# given. gh api gets --allow-escape-sequences when it has that option. A failed download stops
# hub before git am runs. Other URLs, such as one commit's page within a pull request
# (.../pull/N/files/SHA), stay as given. Outside a work tree hub stops before downloading; while
# an am session is in progress, nothing is downloaded and git am answers. Without such a URL,
# this is plain git am.
#
#   $ hub am -3 https://github.com/cli/cli/pull/55
#   > gh api --hostname github.com repos/cli/cli/pulls/55 -H 'Accept: application/vnd.github.patch'
#   > git am -3 TMPDIR/hub-am.XXXXXX/1.patch
#
# git's own manual: git am --help

hub_cmd_am() {
  local valued='-p -C --exclude --include --directory --whitespace --patch-format --resolvemsg'
  valued+=' --quoted-cr --empty'
  local i end=$# urls=''
  local -a args=("$@")
  hub::scan "$valued -S=" "$@"
  for i in "${HUB_OPTIONS[@]}"; do
    case ${args[i]} in -- | --end-of-options) end=$i && break ;; esac
  done
  for i in "${HUB_OPERANDS[@]}"; do
    ((i < end)) && hub::patch_url "${args[i]}" && urls+=" $i"
  done
  [[ -n $urls ]] || hub::exec_git am "$@"
  hub::require_repo
  # git am refuses new mailboxes during a session: let it say so before anything is fetched.
  [[ ! -d $(hub::git_query rev-parse --git-path rebase-apply) ]] || hub::exec_git am "$@"
  # git am copies the patches into .git/rebase-apply, so the files can go when hub ends.
  hub::download_patches patch "$urls" "$@"
  hub::git am "${HUB_ARGS[@]}"
}
