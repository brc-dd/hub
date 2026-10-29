# shellcheck shell=bash
# Summary: Make an authenticated GitHub API request (gh api).
# Usage: hub api ENDPOINT [gh api options]
#
# Runs `gh api` with gh's own options and behaviour: -X METHOD, -F/-f fields,
# --input FILE, -H HEADER, -i, --paginate, --jq, --template, the graphql
# endpoint and the {owner}/{repo}/{branch} placeholders all work as in gh. See
# `gh api --help`. hub adapts two of its old options:
#
#   -t, --flat      Dropped, with a warning: gh has no flat KEY<TAB>VALUE output;
#                   use --jq or --template instead. (gh's own -t is short for
#                   --template; spell it out with hub.)
#   --cache N       A bare number of seconds becomes gh's duration "Ns".
#
#   $ hub api --cache 600 'repos/{owner}/{repo}/releases' --jq '.[].tag_name'
#   > gh api --cache 600s 'repos/{owner}/{repo}/releases' --jq '.[].tag_name'

hub_cmd_api() {
  local -a args=()
  local flat=0
  while (($#)); do
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      -h | --help) hub::usage ;;
      -t | --flat) flat=1 ;;
      --cache)
        args+=("$1")
        shift
        (($#)) || break
        if [[ $1 =~ ^[0-9]+$ ]]; then args+=("${1}s"); else args+=("$1"); fi
        ;;
      --cache=*)
        if [[ ${1#*=} =~ ^[0-9]+$ ]]; then args+=("${1}s"); else args+=("$1"); fi
        ;;
      -[XFfHpq] | --method | --field | --raw-field | --header | --input | --preview | --jq | --template | --hostname)
        args+=("$1")
        shift
        (($#)) || break
        args+=("$1")
        ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  ((flat)) && hub::warn "hub: ignoring -t/--flat: gh api has no flat output; use --jq or --template instead"
  hub::exec_gh api "${args[@]}"
}
