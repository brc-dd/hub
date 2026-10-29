# shellcheck shell=bash
# Summary: Apply the changes behind a GitHub pull request or commit URL.
# Usage: hub apply [git-apply options] [URL | PATCH]...
#
# Every argument that is the URL of a GitHub pull request or commit
# (.../pull/N, .../commit/SHA, .../pull/N/commits/SHA) is downloaded with gh
# as a diff into a temporary file, and `git apply` gets that file in its
# place. A pull request gives its combined diff, as on its "Files changed" tab.
# Other arguments go to git apply unchanged, and without any URL this is plain
# `git apply`. A URL that is the value of an option (as in --exclude URL) or
# that comes after `--` is left as it is. To make commits instead, see `hub am`.
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
