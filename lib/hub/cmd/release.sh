# shellcheck shell=bash
# Summary: List, view, create, edit, upload and download releases (gh release).
# Usage: hub release [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-RELEASE-ARGS...]
#
# gh's command: gh release's options and output. hub renames one subcommand and fills in a
# missing one, then hands every argument to gh release in its place: show is view, and no
# subcommand (none, or an option first) is list. -h or --help before the subcommand prints this
# manual; after it, gh's help. gh picks the repository and host (-R, GH_REPO, GH_HOST, gh repo
# set-default); hub 2.x's GITHUB_HOST reaches gh as GH_HOST when GH_HOST is not set.
#
# hub 2.x's options in gh's spelling:
#   release -d                      gh release list (drafts are listed; --exclude-drafts hides them)
#   release -p                      gh release list --exclude-pre-releases
#   release -f FORMAT               --json FIELDS with --jq EXPR or -t TEMPLATE
#   release show --show-downloads   gh release view TAG --json assets
#   release create|edit -a FILE     gh release create TAG FILE..., or gh release upload TAG FILE...
#   release create|edit -m MESSAGE  --title TITLE --notes TEXT (the first line was the title)
#   release create|edit -F FILE     --notes-file FILE, with --title TITLE
#   release create|edit -t TARGET   --target TARGET (gh's -t is the title)
#   release create -o               gh release view TAG -w afterwards
#   release download TAG -i GLOB    gh release download TAG -p GLOB
#
#   $ hub release -L 5 --exclude-drafts
#   > gh release list -L 5 --exclude-drafts
#   $ hub release -R cli/cli show v2.0.0
#   > gh release -R cli/cli view v2.0.0

hub_cmd_release() {
  hub::gh_subcommand "$@" || hub::usage
  hub::exec_gh release "${HUB_ARGS[@]}"
}
