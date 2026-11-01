# shellcheck shell=bash
# Summary: Make an authenticated GitHub API request (gh api).
# Usage: hub api ENDPOINT [GH-API-ARGS...]
#
# gh's command: gh api's options and output. hub hands every argument to gh api unchanged and in
# order, -- and standard input included. gh picks the host: --hostname HOST, else GH_HOST, else
# the one host it is logged in to, else github.com; hub 2.x's GITHUB_HOST reaches gh as GH_HOST
# when GH_HOST is not set. gh fills {owner}, {repo} and {branch} from the current repository, but
# they do not change the host: use --hostname on GitHub Enterprise. -h or --help as the first
# argument prints this manual; anywhere else, gh's help (gh api --help describes the options).
#
# hub 2.x's options in gh's spelling:
#   api -t, api --flat              not supported; -t is gh's --template: shape output with --jq
#   api --cache 600                 gh api --cache 600s (a duration with its unit)
#   api --obey-ratelimit            not supported
#   api --color                     not supported; gh colors JSON on a terminal
#
#   $ hub api 'repos/{owner}/{repo}/releases' --jq '.[0].tag_name'
#   > gh api repos/\{owner\}/\{repo\}/releases --jq .\[0\].tag_name
#   $ hub api --hostname ghe.example.com graphql -f query=@q.graphql
#   > gh api --hostname ghe.example.com graphql -f query=@q.graphql

hub_cmd_api() {
  case ${1-} in -h | --help) hub::usage ;; esac
  hub::exec_gh api "$@"
}
