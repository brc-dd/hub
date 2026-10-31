# shellcheck shell=bash
# Summary: Merge a pull request locally, with the message GitHub's merge button uses.
# Usage: hub merge [<git-merge options>] PULLREQ-URL
#
# A git command hub extends: git merge's options apply, and hub recognizes one operand, a pull
# request URL. Its head (refs/pull/N/head) is fetched from the base repository, through a remote
# that points at it if there is one, into a private ref of this run and nothing else (no tag the
# fetch would otherwise follow into the repository), and the commit fetched is merged into the
# current branch with --no-ff and the message "Merge pull request #N from
# OWNER/BRANCH" followed by the pull request's title. The pull request is the only revision
# merged; every other argument is git's and reaches it in place: --ff, --ff-only or --no-ff set
# the fast-forward behavior instead of hub's --no-ff; -m or -F give the message instead of
# GitHub's; when --squash is in effect (the last of --squash and --no-squash counts, as in git)
# git squashes as usual, without a merge commit or hub's message. Nothing changes on GitHub until
# you push (`gh pr merge` merges there). Without a pull request URL, or with --abort, --quit or
# --continue, this is plain git merge, as given; arguments after -- are never read.
#
# hub reads git merge's options as the installed git does, from the option table git keeps for
# its completion: which ones take a value, in clusters too (`-qm URL` is a message, not a pull
# request), and what an abbreviation stands for (--mess). An option git would refuse leaves the
# command line to git.
#
#   $ hub merge https://github.com/jingweno/gh/pull/73
#   > git fetch --no-tags --refmap= origin +refs/pull/73/head:refs/hub/merge/73-PID
#   > git merge --no-ff -m 'Merge pull request #73 from jingweno/feature ...' SHA
#   > git update-ref -d refs/hub/merge/73-PID

hub_ext_merge() {
  [[ ${1-} == --help ]] && hub::usage
  local -a args=("$@") opts=()
  local arg opt i url='' url_i=0 extra='' has_extra=0 owner repo host number ended=0 value=0 squash=0 ff_given=0 own_msg=0
  for ((i = 0; i < $#; i++)); do
    arg=${args[i]}
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      if [[ -z $url ]] && ((! ended)) && hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull && -z $HUB_URL_SHA$HUB_URL_FORMAT ]]; then
        url=$arg url_i=$i owner=$HUB_URL_OWNER repo=$HUB_URL_REPO host=$HUB_URL_HOST number=$HUB_URL_NUMBER
      else
        ((has_extra)) || extra=$arg has_extra=1 # the first one, an empty word too
      fi
    else
      case $arg in
        --) ended=1 ;;
        *)
          hub::git_option merge sXmF S "$arg" || hub::exec_git merge "$@" # an option git refuses
          # git lists --file without its value (a low-level callback option), but reads one
          [[ ${HUB_OPTS[-1]} == --file && $arg != *=* ]] && HUB_OPT_NEXT=1
          for opt in "${HUB_OPTS[@]}"; do
            case $opt in
              --abort | --quit | --continue) hub::exec_git merge "$@" ;;
              --squash) squash=1 ;;
              --no-squash) squash=0 ;;
              --ff | --no-ff | --ff-only) ff_given=1 ;;
              -m | -F | --message | --file) own_msg=1 ;;
            esac
          done
          ((HUB_OPT_NEXT)) && value=1
          ;;
      esac
    fi
  done
  [[ -n $url ]] || hub::exec_git merge "$@"
  if ((has_extra)); then
    [[ -n $extra ]] || extra="''"
    hub::die "Aborted: a pull request is merged on its own; unexpected argument: $extra"
  fi
  hub::require_repo
  ((squash || ff_given)) || opts+=(--no-ff)
  if ((! squash && ! own_msg)); then
    local msg
    msg=$(hub::gh_query pr view "$url" --json number,title,headRepositoryOwner,headRefName \
      --jq '"Merge pull request #\(.number) from \(.headRepositoryOwner.login)/\(.headRefName)\n\n\(.title)"') \
      || hub::die "Aborted: could not look up pull request $url"
    opts+=(-m "$msg")
  fi
  local src tmp oid
  src=$(hub::remote_for_project "$owner/$repo" "$host") || src=$(hub::git_url "$owner/$repo" "$host")
  # A ref of this run alone: FETCH_HEAD is shared with every other fetch in this work tree, and a
  # remote-tracking ref with any other fetch of the same remote. The commit fetched is merged by
  # its hash, and the ref goes on every way out. --refmap= keeps git from also writing what the
  # remote's configured refspecs map the pull request to (a +refs/pull/*/head:refs/heads/pull-*
  # refspec would force-update a local branch), and --no-tags from creating the tags that point
  # into the history fetched, which git follows by default.
  tmp=refs/hub/merge/$number-$$
  if ((HUB_NOOP)); then
    args[url_i]=$tmp
    hub::git fetch --no-tags --refmap= "$src" "+refs/pull/$number/head:$tmp"
    hub::git merge "${opts[@]}" "${args[@]}"
    hub::git update-ref -d "$tmp"
    exit 0
  fi
  HUB_MERGE_TMP=$tmp
  trap _hub_merge_cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  hub::git fetch --no-tags --refmap= "$src" "+refs/pull/$number/head:$tmp" || exit
  oid=$(hub::git_query rev-parse --verify --quiet "$tmp^{commit}") || hub::die "Aborted: could not fetch refs/pull/$number/head from $src"
  args[url_i]=$oid
  hub::git merge "${opts[@]}" "${args[@]}"
}

# _hub_merge_cleanup : remove this run's private ref (set in HUB_MERGE_TMP) on the way out.
_hub_merge_cleanup() {
  [[ -z ${HUB_MERGE_TMP-} ]] || hub::git update-ref -d "$HUB_MERGE_TMP" 2>/dev/null
  return 0
}
