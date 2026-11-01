# shellcheck shell=bash
# Summary: Open a GitHub compare page for a branch or a range.
# Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[START...]END]
#
# hub's own command: these are all of its options. Opens https://HOST/OWNER/REPO/compare/RANGE
# for the current project, or for OWNER's copy of it. START..END becomes START...END; with -b,
# the range is BASE...END. START and END are both required in a range.
#
# Without END, the head is the current branch, in the repository it pushes to:
# branch.BRANCH.pushRemote, remote.pushDefault, an upstream of its own name, the only remote,
# your fork, then origin. The branch must be on that remote's remote-tracking branches; it is
# written FORKOWNER:BRANCH when that repository has another owner. Without -b, GitHub compares
# it with the default branch.
#
# Options:
#   -b, --base BASE   Compare END, or the current branch, with BASE.
#   -u, --url         Print the URL instead of opening it.
#   -c, --copy        Copy the URL to the clipboard instead of opening it; with -u, print and copy.
#
# Exit status: the browser's or the clipboard tool's.
#
#   $ hub compare v1.0..v1.1
#   > open https://github.com/mislav/dotfiles/compare/v1.0...v1.1
#   $ hub compare -u -b develop
#   https://github.com/mislav/dotfiles/compare/develop...feature

hub_cmd_compare() {
  local print=0 copy=0 base='' owner='' range='' end project host project_owner repo url
  local -a operands=()
  hub::normalize_opts b --base "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -u | --url) print=1 ;;
      -c | --copy) copy=1 ;;
      -b | --base)
        (($# >= 2)) || hub::usage_error "$1 needs a value"
        [[ -n $2 ]] || hub::usage_error "$1 needs a branch name"
        base=$2
        shift
        ;;
      -h | --help) hub::usage ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $(hub::shown "$1")" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  case ${#operands[@]} in
    0) ;;
    1) range=${operands[0]} ;;
    2) owner=${operands[0]} range=${operands[1]} ;;
    *) hub::usage_error "unexpected argument: $(hub::shown "${operands[2]}")" ;;
  esac
  # The owner becomes a path segment of the URL.
  if ((${#operands[@]} == 2)) && ! hub::is_owner "$owner"; then
    hub::usage_error "not an owner: $owner"
  fi
  if ((${#operands[@]})) && [[ -z $range ]]; then hub::usage_error 'empty range'; fi
  if [[ $base == *..* ]]; then hub::usage_error "use either -b BASE or a range, not both: $base"; fi
  if [[ -n $base && $range == *..* ]]; then
    hub::usage_error "use either -b BASE or a range, not both: $range"
  fi
  if [[ $range == *..* ]]; then
    end=${range#*..} && end=${end#.}
    # git reads START.. as START..HEAD; hub does not guess the head.
    if [[ $range == ..* || -z $end || $end == .* || $end == *..* ]]; then
      hub::usage_error "not a range: $range"
    fi
    # On GitHub A..B diffs the two tips; git's A..B, the commits B adds, is GitHub's A...B.
    range=${range%%..*}...$end
  fi
  project=$(hub::project) || exit 1
  read -r host project_owner repo <<<"$project"
  owner=${owner:-$project_owner}
  [[ -n $range ]] || range=$(_hub_compare_head "$host" "$owner") || exit 1
  [[ -z $base ]] || range=$base...$range
  url=https://$host/$owner/$repo/compare/$(hub::url_escape "$range")
  hub::show_url "$print" "$copy" "$url"
}

# _hub_compare_head HOST OWNER : the current branch as a head of OWNER's repository on HOST.
_hub_compare_head() {
  local branch remote key found fork_host fork_owner
  hub::require_repo
  branch=$(hub::current_branch) || hub::die 'not on a branch (check out a branch, or name a range)'
  if ! remote=$(hub::push_remote "$branch"); then
    # Set but empty, the first of these keys is why there is no answer.
    for key in "branch.$branch.pushRemote" remote.pushDefault; do
      if git config "$key" >/dev/null; then
        hub::die "$key is empty (set it to a remote, or name a range)"
      fi
    done
    hub::die "cannot tell where $branch pushes (git push -u REMOTE $branch first, or name a range)"
  fi
  # 2: pushed, with local commits on top; the page shows what GitHub has.
  hub::pushed "$branch" "$remote" >/dev/null || (($? == 2)) \
    || hub::die "$branch is not pushed to $remote (push it first, or name a range)"
  found=$(hub::remote_project "$remote" push) \
    || hub::die "$remote does not push to a GitHub repository (name a range)"
  read -r fork_host fork_owner _ <<<"$found"
  [[ $fork_host == "$1" ]] || hub::die "$remote pushes to $fork_host, not to $1 (name a range)"
  if [[ ${fork_owner,,} == "${2,,}" ]]; then
    printf '%s\n' "$branch"
  else
    printf '%s\n' "$fork_owner:$branch"
  fi
}
