# shellcheck shell=bash
# Summary: Make an authenticated GitHub API request (gh api).
# Usage: hub api ENDPOINT [gh api options]
#
# Runs `gh api` with gh's own options and behaviour: -X METHOD, -F/-f fields,
# --input FILE, -H HEADER, -i, --paginate, --jq, --template, the graphql
# endpoint and the {owner}/{repo}/{branch} placeholders all work as in gh. See
# `gh api --help`. hub handles two of its old options itself:
#
#   -t, --flat      An error (exit 2): gh has no flat KEY<TAB>VALUE output, and
#                   printing JSON in its place would hand scripts that parse
#                   those lines something else. Pick out values with --jq or
#                   --template instead. gh's own -t is short for --template;
#                   spell that out with hub.
#   --cache N       A bare number of seconds becomes gh's duration "Ns".
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
      --cache)
        args+=("$1")
        shift
        (($#)) || break
        if [[ $1 =~ ^[0-9]+$ ]]; then args+=("${1}s"); else args+=("$1"); fi
        ;;
      --cache=*)
        if [[ ${1#*=} =~ ^[0-9]+$ ]]; then args+=("${1}s"); else args+=("$1"); fi
        ;;
      --method | --field | --raw-field | --header | --input | --preview | --jq | --template | --hostname)
        args+=("$1")
        shift
        (($#)) || break
        args+=("$1")
        ;;
      -[!-]*)
        # gh's short options, alone or bundled (-it, -iXPOST): only -i takes no
        # value, so a t after any i's is -t, and anything after it is its value.
        [[ $1 =~ ^-i*t ]] && _hub_api_flat
        args+=("$1")
        if [[ $1 =~ ^-i*[XFfHpq]$ ]]; then # the value is the next argument
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

# _hub_api_flat : refuse hub 2.x's -t/--flat. Printing gh's JSON instead would give
# scripts that parse its KEY<TAB>VALUE lines a different format, maybe with exit 0.
_hub_api_flat() {
  hub::warn "hub api: -t/--flat is not supported: gh api has no flat KEY<TAB>VALUE output; use --jq or --template instead"
  exit 2
}
