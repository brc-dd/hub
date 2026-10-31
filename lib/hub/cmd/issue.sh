# shellcheck shell=bash
# Summary: List, view, create, edit and close issues (gh issue).
# Usage: hub issue [SUBCOMMAND] [gh issue options]
#
# A gh-backed command: `gh issue`, with gh's subcommands, options and output. hub maps the two
# subcommand spellings gh lacks and hands every other argument over unchanged, in its place:
#
#   hub issue show ...    gh issue view ...
#   hub issue ...         gh issue list ..., when there is no subcommand word
#
# The subcommand word is the first argument that is neither an option nor the value of one, found
# as gh finds it: `-x VALUE` and `--long VALUE` take the next argument, `-xVALUE` and `--long=VALUE`
# are complete, and `--` ends the search. A subcommand gh does not know is passed on for gh to
# reject. `-h`/`--help` before the subcommand word prints this manual; after it, gh's.
#
# Options:
#   gh's. See `gh issue --help` and `gh issue SUBCOMMAND --help`. Old hub's spellings are not
#   translated: `update` is `edit`; closing and reopening are `close` (with `-r REASON`,
#   `--duplicate-of ISSUE`, `-c COMMENT`) and `reopen`; `labels` is `gh label list`; a title and
#   body are `--title` and `--body` or `--body-file` (gh's `-m` is --milestone, its `-F` is
#   --body-file). gh checks the whole command line, locators included, before its first request.
#   Which repository an issue number selects is gh's decision, from the remotes,
#   `gh repo set-default`, GH_REPO or -R; hub adds nothing.
#
#   $ hub issue -s closed -L 5
#   > gh issue list -s closed -L 5
#   $ hub issue -R cli/cli show 12
#   > gh issue -R cli/cli view 12
#   $ hub issue close 12 --duplicate-of 7
#   > gh issue close 12 --duplicate-of 7

hub_cmd_issue() {
  hub::gh_subcommand_args "$@" || hub::usage
  hub::require_gh
  hub::exec_gh issue "${HUB_ARGS[@]}"
}
