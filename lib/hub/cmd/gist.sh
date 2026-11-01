# shellcheck shell=bash
# Summary: List, view, create and edit gists (gh gist).
# Usage: hub gist [SUBCOMMAND] [GH-GIST-ARGS...]
#
# gh's command: gh gist's options and output. hub renames one subcommand and fills in a missing
# one, then hands every argument to gh gist in its place: show is view, and no subcommand (none,
# or an option first) is list. -h or --help before the subcommand prints this manual; after it,
# gh's help. gh gist has no -R: hub skips -R VALUE before the subcommand, as for pr, and gh then
# refuses it. gh picks the host (GH_HOST, else the host it is logged in to), also for a gist URL.
#
# hub 2.x's options in gh's spelling:
#   gist create --public FILE...   gh gist create --public FILE... (-p is --public too)
#   gist create                    gh gist create reads standard input without FILEs
#   gist create -o                 gh gist create -w
#   gist create -c                 not supported; gh prints the URL: pipe it to pbcopy
#   gist show ID                   gh gist view ID --raw (without --raw gh renders Markdown)
#   gist show ID FILE              gh gist view ID --raw -f FILE
#
# gh prints control characters (ESC and others) as visible text, so --raw is not a byte-exact
# copy; gh gist clone ID clones the gist with its files unchanged.
#
#   $ hub gist -L 5
#   > gh gist list -L 5
#   $ hub gist show 8f3c4e2 --raw -f notes.md
#   > gh gist view 8f3c4e2 --raw -f notes.md

hub_cmd_gist() {
  hub::gh_subcommand "$@" || hub::usage
  hub::exec_gh gist "${HUB_ARGS[@]}"
}
