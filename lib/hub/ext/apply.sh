# shellcheck shell=bash
# Summary: Apply the changes behind a GitHub pull request or commit URL.
# Usage: hub apply [git-apply options] [URL | PATCH]...
#
# As `hub am`, but each URL is downloaded as a diff for git apply: a pull
# request's combined diff, as on its "Files changed" tab, or one commit's diff.
# To make commits instead, use `hub am`. Without any URL, this is plain git
# apply.
#
#   $ hub apply https://github.com/jingweno/gh/pull/55
#   > gh pr diff https://github.com/jingweno/gh/pull/55 --color=never > $TMPDIR/hub-apply.XXXXXX/1.diff
#   > git apply $TMPDIR/hub-apply.XXXXXX/1.diff

# shellcheck source=lib/hub/ext/am.sh
source "$HUB_LIB/ext/am.sh"

hub_ext_apply() {
  [[ ${1-} == --help ]] && hub::usage
  _hub_am_run apply diff "$@"
}
