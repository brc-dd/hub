# shellcheck shell=bash
# Summary: Create, view, edit and delete gists (gh gist).
# Usage: hub gist [SUBCOMMAND] [gh gist options]
#
# A gh-backed command: `gh gist`, with gh's subcommands, options and output. hub maps the two
# subcommand spellings gh lacks and hands every other argument over unchanged, in its place:
#
#   hub gist show ...    gh gist view ...
#   hub gist ...         gh gist list ..., when there is no subcommand word
#
# The subcommand word is the first argument that is neither an option nor the value of one, found
# as gh finds it: `-x VALUE` and `--long VALUE` take the next argument, `-xVALUE` and `--long=VALUE`
# are complete, and `--` ends the search. A subcommand gh does not know is passed on for gh to
# reject. `-h`/`--help` before the subcommand word prints this manual; after it, gh's.
#
# Options:
#   gh's. See `gh gist --help` and `gh gist SUBCOMMAND --help`. Old hub's spellings are not
#   translated: `create -p`/`--public` makes a public gist and `create -w` opens it (there is no
#   -o); without FILEs, create reads standard input; `view ID --raw` prints the contents and
#   `view ID -f FILE` picks one file (a second word is not a file name). Which host a gist URL
#   selects is gh's decision: gh takes the ID from the URL and uses its default host (GH_HOST,
#   else the host it is logged in to); hub adds nothing.
#
#   $ hub gist show 8f3c4e2 --raw -f notes.md
#   > gh gist view 8f3c4e2 --raw -f notes.md
#   $ hub gist create -p -d Notes a.txt b.md
#   > gh gist create -p -d Notes a.txt b.md
#   $ hub gist -L 5
#   > gh gist list -L 5

hub_cmd_gist() {
  hub::gh_subcommand_args "$@" || hub::usage
  hub::require_gh
  hub::exec_gh gist "${HUB_ARGS[@]}"
}
