# shellcheck shell=bash
# Summary: List, view, check out and merge pull requests (gh pr).
# Usage: hub pr [SUBCOMMAND] [gh pr options]
#
# A gh-backed command: `gh pr`, with gh's subcommands, options and output. hub maps the two
# subcommand spellings gh lacks and hands every other argument over unchanged, in its place:
#
#   hub pr show ...    gh pr view ...
#   hub pr ...         gh pr list ..., when there is no subcommand word
#
# The subcommand word is the first argument that is neither an option nor the value of one, found
# as gh finds it: `-x VALUE` and `--long VALUE` take the next argument, `-xVALUE` and `--long=VALUE`
# are complete, and `--` ends the search. A subcommand gh does not know is passed on for gh to
# reject. `-h`/`--help` before the subcommand word prints this manual; after it, gh's.
#
# Options:
#   gh's. See `gh pr --help` and `gh pr SUBCOMMAND --help`. Old hub's letters are not translated:
#   `checkout PR -b BRANCH` names the local branch, `view PR --json url -q .url` prints the URL.
#   Which repository and host a number, branch or URL selects is gh's decision, from the remotes,
#   `gh repo set-default`, GH_REPO or -R; hub adds nothing.
#
#   $ hub pr show 12 --comments
#   > gh pr view 12 --comments
#   $ hub pr -R cli/cli show 12
#   > gh pr -R cli/cli view 12
#   $ hub pr -s closed -L 5
#   > gh pr list -s closed -L 5

hub_cmd_pr() {
  hub::gh_subcommand_args "$@" || hub::usage
  hub::require_gh
  hub::exec_gh pr "${HUB_ARGS[@]}"
}
