# shellcheck shell=bash
# Summary: Make an authenticated GitHub API request (gh api).
# Usage: hub api ENDPOINT [gh api options]
#
# Runs `gh api` with gh's own options (see `gh api --help`), except for two of old hub's:
#
#   -t, --flat   An error (exit 2); use --jq, or --template spelled out (gh's -t is --template).
#   --cache N    A bare number of seconds becomes gh's duration "Ns".
#
#   $ hub api --cache 600 'repos/{owner}/{repo}/releases' --jq '.[].tag_name'
#   > gh api --cache 600s 'repos/{owner}/{repo}/releases' --jq '.[].tag_name'

hub_cmd_api() {
  local -a args=()
  while (($#)); do
    case $1 in
      --)
        args+=("$@")
        break
        ;;
      -h | --help) hub::usage ;;
      --flat) _hub_api_flat ;;
      --cache=*) if [[ ${1#*=} =~ ^[0-9]+$ ]]; then args+=("${1}s"); else args+=("$1"); fi ;;
      --cache | --method | --field | --raw-field | --header | --input | --preview | --jq | --template | --hostname)
        args+=("$1")
        shift
        (($#)) || break
        if [[ ${args[-1]} == --cache && $1 =~ ^[0-9]+$ ]]; then args+=("${1}s"); else args+=("$1"); fi
        ;;
      -[!-]*)
        [[ $1 =~ ^-i*t ]] && _hub_api_flat # gh's short options, maybe bundled: only -i takes no value
        args+=("$1")
        if [[ $1 =~ ^-i*[XFfHpq]$ ]]; then
          shift
          (($#)) || break
          args+=("$1")
        fi
        ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  hub::exec_gh api "${args[@]}"
}

_hub_api_flat() {
  hub::warn "hub api: -t/--flat is not supported: gh api has no flat KEY<TAB>VALUE output; use --jq or --template instead"
  exit 2
}
