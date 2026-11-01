# shellcheck shell=bash
# Summary: List, view, create and edit issues (gh issue).
# Usage: hub issue [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-ISSUE-ARGS...]
#
# gh's command: gh issue's options and output. hub renames one subcommand and fills in a
# missing one, then hands every argument to gh issue in its place: show is view, and no
# subcommand (none, or an option first) is list. -h or --help before the subcommand prints this
# manual; after it, gh's help. gh picks the repository and host (-R, GH_REPO, GH_HOST, gh repo
# set-default); hub 2.x's GITHUB_HOST reaches gh as GH_HOST when GH_HOST is not set.
#
# hub 2.x's options in gh's spelling:
#   issue -c CREATOR -@ USER        gh issue list -A CREATOR --mention USER
#   issue -M MILESTONE              gh issue list -m MILESTONE (gh's -m is the milestone)
#   issue -o KEY [-^]               gh issue list -S 'sort:KEY-desc' (sort:KEY-asc)
#   issue -d DATE                   gh issue list -S 'updated:>=DATE'
#   issue|issue show -f FORMAT      --json FIELDS with --jq EXPR or -t TEMPLATE
#   issue create -m MESSAGE         gh issue create -t TITLE -b BODY
#   issue create -F FILE            gh issue create -t TITLE -F FILE (-F is the body only)
#   issue create -o                 gh issue create -w (gh's -o does not exist)
#   issue update N ...              gh issue edit N (--add-label, --remove-label for -l)
#   issue update N -s closed        gh issue close N (gh issue reopen N for open)
#   issue labels                    gh label list
#
#   $ hub issue -s closed -L 5
#   > gh issue list -s closed -L 5
#   $ hub issue -R cli/cli show 12
#   > gh issue -R cli/cli view 12

hub_cmd_issue() {
  hub::gh_subcommand "$@" || hub::usage
  hub::exec_gh issue "${HUB_ARGS[@]}"
}
