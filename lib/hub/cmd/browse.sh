# shellcheck shell=bash
# Summary: Open a GitHub repository page in the browser.
# Usage: hub browse [-u] [-c] [[OWNER/]REPO | --] [SUBPAGE]
#
# Opens https://HOST/OWNER/REPO, plus /SUBPAGE (issues, pulls, wiki, tree/BRANCH/PATH, ...), for
# REPO or, without one or with `--`, for the current repository. A bare REPO is yours;
# HOST/OWNER/REPO names another host. The current repository is GH_REPO, else the one the
# upstream, github or origin remote points at. REPO.wiki is the wiki of REPO: hub opens its
# wiki, wiki/_history for commits and wiki/_SUBPAGE otherwise.
#
# In the current repository, on a branch other than the default branch, the front page, `tree`
# and `commits` open at that branch, in the repository the branch pushes to: the one named by the
# push URL of the remote `git push` would use (remote.*.push, branch.*.pushRemote,
# remote.pushDefault, branch.*.remote and push.default). When that remote is not on GitHub, they
# open in the current repository without the branch; when git could not say where the branch
# pushes (no upstream, push.default nothing), they open at the branch in the current repository.
# With GH_REPO or a REPO argument, the branch is not used. The default branch is the one
# refs/remotes/REMOTE/HEAD names (set by clone, or `git remote set-head REMOTE -a`); when it is
# unknown, hub asks gh for it, the one API call this command can make, and assumes main when gh
# cannot answer.
#
# Options:
#   -u, --url    Print the URL instead of opening it.
#   -c, --copy   Copy the URL to the clipboard instead of opening it; with -u, print and copy.
#
# When the browser or the clipboard tool fails, its status is the exit status, after the URL
# was printed.
#
#   $ hub browse -- issues
#   > open https://github.com/mislav/dotfiles/issues
#   $ hub browse -u cli/cli releases
#   https://github.com/cli/cli/releases

hub_cmd_browse() {
  local print=0 copy=0 repo='' subpage='' proj host branch url rc=0
  local -a args=()
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -u | --url) print=1 ;;
      -c | --copy) copy=1 ;;
      -h | --help) hub::usage ;;
      --) # the current repository; what follows is the SUBPAGE
        args+=("$@")
        break
        ;;
      -?*) _hub_browse_usage_error "unknown option: $1" ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  ((${#args[@]} <= 2)) || _hub_browse_usage_error "too many arguments"
  repo=${args[0]-} subpage=${args[1]-}
  [[ $repo != -- ]] || repo=''
  if [[ -z $repo ]]; then
    hub::main_project >/dev/null
    proj=$HUB_PROJECT host=$HUB_PROJECT_HOST
    if [[ -z ${GH_REPO:-} && $proj != */?*.wiki ]] && [[ -z $subpage || $subpage == tree || $subpage == commits ]] \
      && branch=$(hub::current_branch) && [[ $branch != "$(hub::default_branch || echo main)" ]]; then
      if hub::push_target "$branch"; then
        if hub::remote_project "$HUB_PUSH_REMOTE" push >/dev/null; then
          proj=$HUB_PROJECT host=$HUB_PROJECT_HOST branch=$HUB_PUSH_BRANCH
        else
          branch='' # the branch goes somewhere that is not GitHub: no page shows it
        fi
      fi
      [[ -z $branch ]] || subpage=${subpage:-tree}/$(hub::url_escape "$branch")
    fi
  elif [[ $repo == */* ]]; then
    hub::parse_project "$repo" || _hub_browse_usage_error "not a repository: $repo"
    proj=$HUB_PROJECT host=$HUB_PROJECT_HOST
  else
    hub::is_project_name "$repo" || _hub_browse_usage_error "not a repository name: $repo"
    proj=$(hub::expand_project "$repo") || exit 1
    host=$(hub::host)
  fi
  [[ $subpage != tree ]] || subpage='' # GitHub has no bare tree page: the front page shows the default branch
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
  if ((copy)); then hub::copy "$url" || rc=$?; fi
  if ((! print && ! copy)); then hub::open_url "$url" || rc=$?; fi
  return "$rc"
}

_hub_browse_usage_error() {
  hub::die "hub browse: $1"$'\n'"Usage: hub browse [-u] [-c] [[OWNER/]REPO | --] [SUBPAGE]"
}
