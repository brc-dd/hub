# shellcheck shell=bash
# Summary: Apply the changes behind a GitHub pull request, commit or compare URL.
# Usage: hub apply [<git-apply options>] (URL | PATCH)...
#
# As `hub am`, but each URL is downloaded as a diff for git apply: a pull request's or
# comparison's combined diff, as on its "Files changed" tab, or one commit's diff; a URL ending
# in .patch is downloaded as a patch series instead, which git apply also reads. To make
# commits, use `hub am`. Without any URL, this is plain git apply.
#
#   $ hub apply https://github.com/jingweno/gh/pull/55
#   > gh api --hostname github.com repos/jingweno/gh/pulls/55 -H 'Accept: application/vnd.github.v3.diff' > $TMPDIR/hub-apply.XXXXXX/1.diff
#   > git apply $TMPDIR/hub-apply.XXXXXX/1.diff

# shellcheck source=lib/hub/ext/am.sh
source "$HUB_LIB/ext/am.sh"

hub_ext_apply() { _hub_am_run apply "$@"; }
