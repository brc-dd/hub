# shellcheck shell=bash
# Summary: List, view, check out and merge pull requests (gh pr).
# Usage: hub pr [SUBCOMMAND] [gh pr options]
#
# Runs `gh pr` with gh's own options and behaviour. hub only maps the old
# subcommand names and argument forms that gh doesn't have:
#
#   hub pr show [PR] [-w] [-u]     gh pr view [PR]: shows the pull request in the
#                                  terminal; -w opens it in the browser instead,
#                                  and -u prints only its URL (--json url --jq .url).
#   hub pr checkout PR [BRANCH]    gh pr checkout PR [-b BRANCH]
#
# Everything else goes to gh unchanged, for example:
#
#   hub pr list [-s STATE] [-L N]  gh pr list
#   hub pr merge [PR] --squash     gh pr merge: merges on GitHub, right away;
#                                  it is not a merge into your local branch.
#   hub pr status | view | diff | checks | comment | review | edit | close | ...
#
# PR is a number, a URL or a branch name; without one, gh uses the pull
# request for the current branch. See `gh pr SUBCOMMAND --help` for options.
#
#   $ hub pr checkout 123 fix-typo
#   > gh pr checkout 123 -b fix-typo

hub_cmd_pr() {
  case ${1-} in
    -h | --help) hub::usage ;;
    '') hub::exec_gh pr ;;
  esac
  local sub=$1
  shift
  case $sub in
    show) _hub_pr_show "$@" ;;
    checkout | co) _hub_pr_checkout "$sub" "$@" ;;
    *) hub::exec_gh pr "$sub" "$@" ;;
  esac
}

# _hub_pr_show ARGS... : gh pr view, with hub's -u/--url printing just the URL.
_hub_pr_show() {
  local -a args=()
  local arg url=0
  while (($#)); do
    arg=$1
    shift
    case $arg in
      -u | --url) url=1 ;;
      --)
        args+=(-- "$@")
        break
        ;;
      *) args+=("$arg") ;;
    esac
  done
  ((url)) && args+=(--json url --jq .url)
  hub::exec_gh pr view "${args[@]}"
}

# _hub_pr_checkout SUBCOMMAND ARGS... : gh pr checkout; an old-style second
# positional argument (the local branch name) becomes -b BRANCH.
_hub_pr_checkout() {
  local -a args=("$1")
  local arg positionals=0
  shift
  while (($#)); do
    arg=$1
    shift
    case $arg in
      -b | --branch | --worktree | -R | --repo)
        args+=("$arg")
        if (($#)); then
          args+=("$1")
          shift
        fi
        ;;
      --)
        args+=(-- "$@")
        break
        ;;
      -?*) args+=("$arg") ;;
      *)
        positionals=$((positionals + 1))
        if ((positionals == 2)); then args+=(-b "$arg"); else args+=("$arg"); fi
        ;;
    esac
  done
  hub::exec_gh pr "${args[@]}"
}
