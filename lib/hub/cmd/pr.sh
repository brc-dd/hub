# shellcheck shell=bash
# Summary: List, view and check out pull requests (gh pr).
# Usage: hub pr [-R [HOST/]OWNER/REPO] [SUBCOMMAND] [GH-PR-ARGS...]
#
# gh's command: gh pr's options and output. hub renames one subcommand and fills in a missing
# one, then hands every argument to gh pr in its place: show is view, and no subcommand (none,
# or an option first) is list. -h or --help before the subcommand prints this manual; after
# it, gh's help. gh picks the repository and host (-R, GH_REPO, GH_HOST, gh repo set-default);
# hub 2.x's GITHUB_HOST reaches gh as GH_HOST when GH_HOST is not set.
#
# hub 2.x's options in gh's spelling:
#   pr list -h BRANCH -b BASE       gh pr list -H BRANCH -B BASE (gh's -H takes no OWNER: prefix)
#   pr list -o KEY [-^]             gh pr list -S 'sort:KEY-desc' (sort:KEY-asc), created or updated
#   pr list -o popularity           gh pr list -S 'sort:comments-desc'
#   pr list|show -f FORMAT          --json FIELDS with --jq EXPR or -t TEMPLATE
#   pr checkout PR BRANCH           gh pr checkout PR -b BRANCH
#   pr show -h HEAD                 gh pr view HEAD
#   pr show -u                      gh pr view --json url --jq .url
#   pr show -c                      not supported; gh's -c is --comments: pipe the URL to pbcopy
#   pr show                         gh pr view -w opens it in the browser
#
#   $ hub pr -s closed -L 5
#   > gh pr list -s closed -L 5
#   $ hub pr -R cli/cli show 12
#   > gh pr -R cli/cli view 12

hub_cmd_pr() {
  hub::gh_subcommand "$@" || hub::usage
  hub::exec_gh pr "${HUB_ARGS[@]}"
}
