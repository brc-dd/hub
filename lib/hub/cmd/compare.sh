# shellcheck shell=bash
# Summary: Open a GitHub compare page for a branch or a range.
# Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[BASE...]HEAD]
#
# Opens https://HOST/OWNER/REPO/compare/RANGE for the current repository.
# Without a range, the current branch is compared with the default branch;
# when the branch pushes to another GitHub repository (your fork), the head
# is written OWNER:BRANCH so that GitHub compares across the fork. On the
# default branch or a detached HEAD, name a range or use -b.
#
# A two-dot range A..B becomes A...B, the form GitHub's compare view uses.
# With an OWNER argument, the compare page of OWNER's copy of the repository
# (a fork) is opened instead.
#
# Options:
#   -b, --base BASE   Compare against BASE: BASE...HEAD (HEAD defaults to the current branch).
#   -u, --url         Print the URL instead of opening it.
#   -c, --copy        Copy the URL to the clipboard instead of opening it.
#
#   $ hub compare                            # on branch feature
#   > open https://github.com/mislav/dotfiles/compare/feature
#   $ hub compare v1.0..v1.1
#   > open https://github.com/mislav/dotfiles/compare/v1.0...v1.1
#   $ hub compare -u -b develop
#   https://github.com/mislav/dotfiles/compare/develop...feature
#   $ hub compare jingweno feature
#   > open https://github.com/jingweno/dotfiles/compare/feature

hub_cmd_compare() {
  local print=0 copy=0 base='' owner='' range='' proj host branch url
  local -a args=()
  while (($#)); do
    case $1 in
      -u | --url) print=1 ;;
      -c | --copy) copy=1 ;;
      -b | --base)
        (($# >= 2)) || hub::die "hub compare: $1 needs a BASE"
        base=$2
        shift
        ;;
      --base=*) base=${1#*=} ;;
      -h | --help) hub::usage ;;
      -*) hub::die "hub compare: unknown option: $1" ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  case ${#args[@]} in
    0) ;;
    1) range=${args[0]} ;;
    2) owner=${args[0]} range=${args[1]} ;;
    *) hub::die "Usage: hub compare [-u] [-c] [-b BASE] [OWNER] [[BASE...]HEAD]" ;;
  esac

  proj=$(hub::main_project && printf '%s\n' "$HUB_PROJECT_HOST") || exit 1
  host=${proj##*$'\n'} proj=${proj%%$'\n'*}
  [[ -n $owner ]] && proj=$owner/${proj#*/}

  if [[ -z $range ]]; then
    branch=$(hub::current_branch) \
      || hub::die "Aborted: not currently on any branch; name a branch or a BASE...HEAD range to compare."
    if [[ -z $base && $branch == "$(hub::default_branch)" ]]; then
      hub::die "Aborted: $branch is the default branch; name a branch or a BASE...HEAD range to compare, or use -b BASE."
    fi
    range=$(_hub_compare_head "$branch" "$host" "${proj%%/*}")
  elif [[ $range == *..* ]]; then
    [[ -z $base ]] || hub::die "Aborted: use either -b BASE or a range, not both."
    [[ $range == *...* ]] || range=${range/../...}
  fi
  [[ -n $base ]] && range=$base...$range

  url=https://$host/$proj/compare/$(_hub_compare_escape "$range")
  if ((print)); then printf '%s\n' "$url"; fi
  if ((copy)); then hub::copy "$url"; fi
  if ((! print && ! copy)); then hub::open_url "$url"; fi
}

# _hub_compare_head BRANCH HOST OWNER : the compare head for BRANCH. When BRANCH pushes
# to a GitHub remote on HOST owned by someone other than OWNER, that is FORKOWNER:BRANCH.
_hub_compare_head() {
  local branch=$1 remote ref out
  if IFS=$'\t' read -r remote ref < <(hub::git_query for-each-ref --format='%(push:remotename)%09%(push)' "refs/heads/$branch") \
    && [[ -n $remote ]] && out=$(hub::remote_project "$remote" && printf '%s\n' "$HUB_PROJECT_HOST"); then
    [[ $ref == "refs/remotes/$remote/"?* ]] && branch=${ref#"refs/remotes/$remote/"}
    local fork_host=${out##*$'\n'} fork_owner=${out%%/*}
    if [[ ${fork_host,,} == "${2,,}" && ${fork_owner,,} != "${3,,}" ]]; then
      branch=$fork_owner:$branch
    fi
  fi
  printf '%s\n' "$branch"
}

# _hub_compare_escape STR : percent-encode STR for use in a URL path (/ : @ and unreserved characters are kept).
_hub_compare_escape() {
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
