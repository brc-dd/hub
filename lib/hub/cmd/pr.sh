# shellcheck shell=bash
# Summary: List, view, check out and merge pull requests (gh pr).
# Usage: hub pr [SUBCOMMAND] [gh pr options]
#
# Runs `gh pr` with gh's own options. hub maps two old forms:
#
#   hub pr show [PR] [-u]          gh pr view [PR]; -u prints only its URL
#   hub pr checkout PR [BRANCH]    gh pr checkout PR [-b BRANCH]
#
# Everything else goes to gh unchanged: list, status, diff, merge (which merges on
# GitHub), ... See `gh pr SUBCOMMAND --help`.
#
#   $ hub pr checkout 123 fix-typo
#   > gh pr checkout 123 -b fix-typo

hub_cmd_pr() {
  case ${1-} in
    -h | --help) hub::usage ;;
    show | checkout | co) ;;
    *) hub::exec_gh pr "$@" ;;
  esac
  local sub=$1 arg url=0 n=0
  local -a args=()
  shift
  while (($#)); do
    arg=$1
    shift
    case $arg in
      -u | --url)
        if [[ $sub == show ]]; then url=1; else args+=("$arg"); fi
        ;;
      --json | -q | --jq | -t | --template | -b | --branch | --worktree | -R | --repo)
        args+=("$arg" "${@:1:1}") # the value is gh's, even if it reads -u
        shift $(($# > 0))
        ;;
      --)
        args+=(-- "$@")
        break
        ;;
      -?*) args+=("$arg") ;;
      *)
        n=$((n + 1))
        if [[ $sub != show ]] && ((n == 2)); then args+=(-b "$arg"); else args+=("$arg"); fi
        ;;
    esac
  done
  [[ $sub != show ]] || sub=view
  ((url)) && args=(--json url --jq .url "${args[@]}") # ahead of any --
  hub::exec_gh pr "$sub" "${args[@]}"
}
