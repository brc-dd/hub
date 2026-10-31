# shellcheck shell=bash
# Summary: List, view, create, edit, upload and download releases (gh release).
# Usage: hub release [SUBCOMMAND] [gh release options]
#
# A gh-backed command: `gh release`, with gh's subcommands, options and output. hub maps the two
# subcommand spellings gh lacks and hands every other argument over unchanged, in its place:
#
#   hub release show ...    gh release view ...
#   hub release ...         gh release list ..., when there is no subcommand word
#
# The subcommand word is the first argument that is neither an option nor the value of one, found
# as gh finds it: `-x VALUE` and `--long VALUE` take the next argument, `-xVALUE` and `--long=VALUE`
# are complete, and `--` ends the search. A subcommand gh does not know is passed on for gh to
# reject. `-h`/`--help` before the subcommand word prints this manual; after it, gh's.
#
# Options:
#   gh's. See `gh release --help` and `gh release SUBCOMMAND --help`. Old hub's spellings are not
#   translated: assets are arguments, `create TAG FILE...` and `upload TAG FILE... [--clobber]`
#   (`FILE#LABEL` labels one; there is no -a); the title and notes are `--title` and `--notes` or
#   `--notes-file` (gh's `-t` is --title, its `-F` is --notes-file); the commit is `--target REF`;
#   `download TAG -p GLOB` picks assets. gh checks the whole command line before its first request
#   and runs one operation per command: to add assets to a draft and publish it, `upload` first,
#   then `edit TAG --draft=false`. Which repository a tag selects is gh's decision, from the
#   remotes, `gh repo set-default`, GH_REPO or -R; hub adds nothing.
#
#   $ hub release -L 5 --exclude-drafts
#   > gh release list -L 5 --exclude-drafts
#   $ hub release -R cli/cli show v2.0.0
#   > gh release -R cli/cli view v2.0.0
#   $ hub release create v1.2.0 dist/app.tgz --title "Version 1.2" --generate-notes
#   > gh release create v1.2.0 dist/app.tgz --title Version\ 1.2 --generate-notes

hub_cmd_release() {
  hub::gh_subcommand_args "$@" || hub::usage
  hub::require_gh
  hub::exec_gh release "${HUB_ARGS[@]}"
}
