# shellcheck shell=bash
# Summary: Make an authenticated GitHub API request (gh api).
# Usage: hub api ENDPOINT [gh api options]
#
# A gh-backed command: `gh api` with the arguments exactly as given, options, values, `--` and
# standard input included (see `gh api --help`). The host is gh's choice: `--hostname HOST`, else
# GH_HOST (hub 2.x's GITHUB_HOST is passed to gh as GH_HOST), else github.com. Old hub's options
# are not translated: `-t` is gh's `--template`, `--cache` takes a duration with its unit (`600s`,
# `1h`), and there is no `--flat`, `--obey-ratelimit` or `--color`; `--jq` and `--template` shape
# the output. `hub api --help` prints this manual; `gh api --help` describes the options.
#
# Options:
#   gh's. See `gh api --help`.
#
#   $ hub api --cache 1h 'repos/{owner}/{repo}/releases' --jq '.[0].tag_name'
#   > gh api --cache 1h repos/\{owner\}/\{repo\}/releases --jq .\[0\].tag_name
#   $ hub api --hostname ghe.example.com graphql -f query=@q.graphql
#   > gh api --hostname ghe.example.com graphql -f query=@q.graphql

hub_cmd_api() {
  case ${1-} in -h | --help) hub::usage ;; esac
  hub::require_gh
  hub::exec_gh api "$@"
}
