# shellcheck shell=bash
# Summary: Open a GitHub repository in the web browser.
# Usage: hub browse [-u] [-c] [[[HOST/]OWNER/]REPO | --] [SUBPAGE]
#
# hub's own command: these are all of its options. Opens https://HOST/OWNER/REPO/SUBPAGE.
# The repository is OWNER/REPO, HOST/OWNER/REPO or a URL; REPO alone is yours on the default
# host; no repository, or --, is the current project. SUBPAGE is appended as given (issues,
# pulls, wiki, commits, settings, actions, ...); tree alone is the front page.
#
# For the current project (not GH_REPO) with no SUBPAGE, tree or commits: when the current
# branch is not the default branch and is on the remote it pushes to, the page is tree/BRANCH
# or commits/BRANCH of the repository that remote pushes to.
#
# Options:
#   -u   Print the URL instead of opening it.
#   -c   Copy the URL to the clipboard instead of opening it; with -u, print and copy.
#
#   $ hub browse -- issues
#   > open https://github.com/mislav/dotfiles/issues
#   $ hub browse -u cli/cli releases
#   https://github.com/cli/cli/releases

hub_cmd_browse() {
  local print=0 copy=0 dashdash=0 project host owner repo subpage url
  local -a operands=()
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -u) print=1 ;;
      -c) copy=1 ;;
      -h | --help) hub::usage ;;
      --) shift && dashdash=1 && break ;;
      -?*) hub::usage_error "unknown option: $1" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  # -- takes the repository's place: only a SUBPAGE may follow it.
  if ((dashdash)); then
    ((${#operands[@]} == 0)) || hub::usage_error "unexpected argument: --"
    (($# <= 1)) || hub::usage_error "unexpected argument: $2"
    subpage=${1-}
  else
    ((${#operands[@]} <= 2)) || hub::usage_error "unexpected argument: ${operands[2]}"
    subpage=${operands[1]-}
  fi
  if ((dashdash == 0 && ${#operands[@]})); then
    project=$(_hub_browse_repository "${operands[0]}") || exit 1
  else
    project=$(hub::project) || exit 1
  fi
  read -r host owner repo <<<"$project"
  case $subpage in
    '' | tree | commits)
      [[ $subpage == tree ]] && subpage=
      if ((dashdash || ${#operands[@]} == 0)) && [[ -z ${GH_REPO-} ]] \
        && project=$(_hub_browse_branch_page "${subpage:-tree}"); then
        read -r host owner repo subpage <<<"$project"
      fi
      ;;
  esac
  url=https://$host/$owner/$repo${subpage:+/$subpage}
  if ((print)); then printf '%s\n' "$url"; fi
  if ((copy)); then
    hub::copy "$url"
  elif ((! print)); then
    hub::open_url "$url"
  fi
}

# _hub_browse_repository STR : "HOST OWNER REPO" of the operand; REPO alone is your login's.
_hub_browse_repository() {
  local host login owner repo
  if [[ $1 != */* ]] && hub::is_shorthand "$1"; then
    host=$(hub::host) && login=$(hub::login "$host") || return 1
    printf '%s %s %s\n' "$host" "$login" "$1"
  elif read -r host owner repo < <(hub::parse_project "$1") \
    && _hub_browse_checked "$1" "$host" "$owner" "$repo"; then
    printf '%s %s %s\n' "$host" "$owner" "$repo"
  else
    hub::die "not a repository: $1 (use REPO, OWNER/REPO, HOST/OWNER/REPO or a URL)"
  fi
}

# _hub_browse_checked STR HOST OWNER REPO : the name classes, and a HOST that looks like one
# (cli/cli/issues is a typo, not the host cli); hub::parse_url already checked a URL.
_hub_browse_checked() {
  [[ $1 != *:* ]] || return 0
  hub::is_shorthand "$3/$4" || return 1
  [[ $1 != */*/* || $2 == *.* ]] || hub::known_host "$2"
}

# _hub_browse_branch_page PAGE : "HOST OWNER REPO PAGE/BRANCH" of the current branch where it
# pushes, when that branch is not the default branch and is on its push remote.
_hub_browse_branch_page() {
  local branch remote default='' rc=0 found
  branch=$(hub::current_branch) || return 1
  # An unborn branch has nothing to show.
  hub::git_query rev-parse --verify --quiet "refs/heads/$branch" >/dev/null || return 1
  # The default branch as the last fetch recorded it, without gh; unknown counts as another.
  remote=$(hub::project_remote) && default=$(_hub_browse_remote_head "$remote")
  [[ $branch != "$default" ]] || return 1
  remote=$(hub::push_remote "$branch") || return 1
  hub::pushed "$branch" "$remote" >/dev/null || rc=$?
  ((rc != 1)) || return 1
  found=$(hub::remote_project "$remote" push) || return 1
  printf '%s %s/%s\n' "$found" "$1" "$(hub::url_escape "$branch")"
}

# _hub_browse_remote_head REMOTE : the branch refs/remotes/REMOTE/HEAD points at, when both exist.
_hub_browse_remote_head() {
  local ref head=refs/remotes/$1/
  ref=$(git symbolic-ref --quiet "${head}HEAD" 2>/dev/null) && [[ $ref == "$head"?* ]] \
    && git show-ref --verify --quiet "$ref" && printf '%s\n' "${ref#"$head"}"
}
