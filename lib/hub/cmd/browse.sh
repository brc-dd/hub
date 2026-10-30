# shellcheck shell=bash
# Summary: Open a GitHub repository page in the browser.
# Usage: hub browse [-u] [-c] [[OWNER/]REPO | --] [SUBPAGE]
#
# Opens https://HOST/OWNER/REPO, plus /SUBPAGE (issues, wiki, tree/BRANCH, ...), for REPO or,
# without one or with `--`, for the current repository. A bare REPO is yours; HOST/OWNER/REPO
# names another host. In the current repository on a branch other than the default branch, the
# front page, tree and commits open at that branch, in the repository it pushes to. REPO.wiki is
# the wiki of REPO: hub opens its wiki, wiki/_history for commits and wiki/_SUBPAGE otherwise.
#
# Options:
#   -u, --url    Print the URL instead of opening it.
#   -c, --copy   Copy the URL to the clipboard instead of opening it.
#
#   $ hub browse -- issues
#   > open https://github.com/mislav/dotfiles/issues
#   $ hub browse -u cli/cli releases
#   https://github.com/cli/cli/releases

hub_cmd_browse() {
  local print=0 copy=0 arg repo subpage proj host branch url
  local -a args=()
  for arg; do
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
  [[ $repo != -- ]] || repo=
  if [[ $repo == */*/* ]]; then
    host=${repo%%/*} proj=${repo#*/}
  elif [[ -n $repo ]]; then
    host=$(hub::host)
    proj=$(hub::expand_project "$repo") || exit 1
  else
    hub::main_project >/dev/null
    proj=$HUB_PROJECT host=$HUB_PROJECT_HOST
    if [[ -z $subpage || $subpage == tree || $subpage == commits ]] && [[ -z ${GH_REPO:-} && $proj != */?*.wiki ]] \
      && branch=$(hub::current_branch) && [[ $branch != "$(hub::default_branch)" ]]; then
      if hub::push_target "$branch" && hub::remote_project "$HUB_PUSH_REMOTE" >/dev/null; then
        proj=$HUB_PROJECT host=$HUB_PROJECT_HOST branch=$HUB_PUSH_BRANCH
      fi
      subpage=${subpage:-tree}/$(hub::url_escape "$branch")
    fi
  fi
  [[ $subpage != tree ]] || subpage= # GitHub has no bare tree page: the front page shows the default branch
  if [[ $proj == */?*.wiki ]]; then
    proj=${proj%.wiki}
    case $subpage in
      '' | wiki) subpage=wiki ;;
      commits | commits/*) subpage=wiki/_history ;;
      *) subpage=wiki/_$subpage ;;
    esac
  fi
  url=https://$host/$proj${subpage:+/$subpage}
  if ((print)); then printf '%s\n' "$url"; fi
  if ((copy)); then hub::copy "$url"; fi
  if ((! print && ! copy)); then hub::open_url "$url"; fi
}
