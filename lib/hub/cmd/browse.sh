# shellcheck shell=bash
# Summary: Open a GitHub repository page in the browser.
# Usage: hub browse [-u] [-c] [[OWNER/]REPO | --] [SUBPAGE]
#
# Opens https://HOST/OWNER/REPO, plus /SUBPAGE when one is given. Without a
# repository argument, or with `--` in its place, the current repository is
# used: its upstream, github or origin remote (or GH_REPO). A bare REPO means
# your own repository; HOST/OWNER/REPO names one on another host.
#
# SUBPAGE is appended as given: issues, pulls, wiki, actions, releases,
# settings, tree/BRANCH, blob/main/README.md, ...
#
# For the current repository, no SUBPAGE and the SUBPAGEs tree and commits
# follow the branch you are on: on a branch other than the default branch,
# hub opens tree/BRANCH (commits/BRANCH for commits) in the repository the
# branch pushes to, which is your fork when the branch tracks a fork remote.
# Otherwise (the default branch, a REPO argument, GH_REPO) tree is the front
# page and commits the history of the default branch.
#
# The URL is built locally. GitHub is only asked for your login (bare REPO)
# and, when refs/remotes/REMOTE/HEAD is missing, the default branch.
#
# Options:
#   -u, --url    Print the URL instead of opening it.
#   -c, --copy   Copy the URL to the clipboard instead of opening it.
#
#   $ hub browse
#   > open https://github.com/mislav/dotfiles
#   $ hub browse -- issues
#   > open https://github.com/mislav/dotfiles/issues
#   $ hub browse -- commits      # on the branch feature
#   > open https://github.com/mislav/dotfiles/commits/feature
#   $ hub browse -u cli/cli releases
#   https://github.com/cli/cli/releases

hub_cmd_browse() {
  local print=0 copy=0 arg repo subpage proj host branch url
  local -a args=()
  for arg in "$@"; do
    case $arg in
      -u | --url) print=1 ;;
      -c | --copy) copy=1 ;;
      -h | --help) hub::usage ;;
      --) args+=("$arg") ;;
      -*) hub::die "hub browse: unknown option: $arg" ;;
      *) args+=("$arg") ;;
    esac
  done
  ((${#args[@]} <= 2)) || hub::die "Usage: hub browse [-u] [-c] [[OWNER/]REPO | --] [SUBPAGE]"
  repo=${args[0]-} subpage=${args[1]-}
  [[ $repo == -- ]] && repo=

  if [[ -n $repo ]]; then
    case $repo in
      */*/*) host=${repo%%/*} proj=${repo#*/} ;;
      *)
        host=$(hub::host)
        proj=$(hub::expand_project "$repo") || exit 1
        ;;
    esac
  else
    proj=$(hub::main_project && printf '%s\n' "$HUB_PROJECT_HOST") || exit 1
    host=${proj##*$'\n'} proj=${proj%%$'\n'*}
    if [[ -z $subpage || $subpage == tree || $subpage == commits ]] && [[ -z ${GH_REPO:-} ]] \
      && branch=$(hub::current_branch) && [[ $branch != "$(hub::default_branch)" ]]; then
      _hub_browse_push_target "$branch"
      subpage=${subpage:-tree}/$(_hub_browse_escape "$branch")
    fi
  fi
  # A bare tree is the default branch, i.e. the front page (GitHub has no .../tree page).
  if [[ $subpage == tree ]]; then subpage=; fi

  url=https://$host/$proj${subpage:+/$subpage}
  if ((print)); then printf '%s\n' "$url"; fi
  if ((copy)); then hub::copy "$url"; fi
  if ((! print && ! copy)); then hub::open_url "$url"; fi
}

# _hub_browse_push_target BRANCH : if BRANCH pushes to a GitHub remote, point the
# caller's host, proj and branch at that repository and the branch name there.
_hub_browse_push_target() {
  local remote ref out
  IFS=$'\t' read -r remote ref < <(hub::git_query for-each-ref --format='%(push:remotename)%09%(push)' "refs/heads/$1") || return 0
  [[ -n $remote ]] || return 0
  out=$(hub::remote_project "$remote" && printf '%s\n' "$HUB_PROJECT_HOST") || return 0
  proj=${out%%$'\n'*} host=${out##*$'\n'}
  [[ $ref == "refs/remotes/$remote/"?* ]] && branch=${ref#"refs/remotes/$remote/"}
  return 0
}

# _hub_browse_escape STR : percent-encode STR for use in a URL path (/ : @ and unreserved characters are kept).
_hub_browse_escape() {
  local LC_ALL=C s=$1 out='' c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9._~/:@-]) out+=$c ;;
      *)
        printf -v c '%%%02X' "'$c"
        out+=$c
        ;;
    esac
  done
  printf '%s\n' "$out"
}
