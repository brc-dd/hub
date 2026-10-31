# shellcheck shell=bash
# Summary: Merge a pull request locally, with the message GitHub's merge button uses.
# Usage: hub merge [<git-merge options>] PULLREQ-URL
#
# A git command hub extends: git merge's options apply, and hub recognizes one operand, a pull
# request URL. Its head (refs/pull/N/head) is fetched from the base repository, through a remote
# that points at it if there is one, into a private ref of this run, and the commit fetched is
# merged into the current branch with --no-ff and the message "Merge pull request #N from
# OWNER/BRANCH" followed by the pull request's title. The pull request is the only revision
# merged; every other argument is git's and reaches it in place: --ff, --ff-only or --no-ff set
# the fast-forward behavior instead of hub's --no-ff; -m or -F give the message instead of
# GitHub's; when --squash is in effect (the last of --squash and --no-squash counts, as in git)
# git squashes as usual, without a merge commit or hub's message. Nothing changes on GitHub until
# you push (`gh pr merge` merges there). Without a pull request URL, or with --abort, --quit or
# --continue, this is plain git merge, as given; arguments after -- are never read.
#
# hub finds the operands by knowing which of git merge's options take a value (git 2.54), in
# clusters too: `-qm URL` is a message, not a pull request. An abbreviated long option (--mess
# for --message) is not recognized, so its value would be taken for an operand: spell options out.
#
#   $ hub merge https://github.com/jingweno/gh/pull/73
#   > git fetch origin +refs/pull/73/head:refs/hub/merge/73-PID
#   > git merge --no-ff -m 'Merge pull request #73 from jingweno/feature ...' SHA
#   > git update-ref -d refs/hub/merge/73-PID

hub_ext_merge() {
  [[ ${1-} == --help ]] && hub::usage
  local -a args=("$@") opts=()
  local arg c i j url='' url_i=0 extra='' owner repo host number ended=0 value=0 squash=0 ff_given=0 own_msg=0
  for ((i = 0; i < $#; i++)); do
    arg=${args[i]}
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      if [[ -z $url ]] && ((! ended)) && hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == pull && -z $HUB_URL_SHA$HUB_URL_FORMAT ]]; then
        url=$arg url_i=$i owner=$HUB_URL_OWNER repo=$HUB_URL_REPO host=$HUB_URL_HOST number=$HUB_URL_NUMBER
      else
        [[ -n $extra ]] || extra=$arg
      fi
    else
      case $arg in
        --) ended=1 ;;
        --abort | --quit | --continue) hub::exec_git merge "$@" ;;
        --squash) squash=1 ;;
        --no-squash) squash=0 ;;
        --ff | --no-ff | --ff-only) ff_given=1 ;;
        -m | -F | --message | --file) own_msg=1 value=1 ;;
        --message=* | --file=*) own_msg=1 ;;
        -s | -X | --strategy | --strategy-option | --cleanup | --into-name) value=1 ;;
        --*) ;; # flags, and --log[=<n>], --gpg-sign[=<key-id>], --strategy=<s>: their value is attached
        *)
          # a cluster of short options: the first taking a value takes the rest of it, or the next argument
          for ((j = 1; j < ${#arg}; j++)); do
            c=${arg:j:1}
            case $c in
              m | F | s | X)
                [[ $c == [mF] ]] && own_msg=1
                ((j + 1 < ${#arg})) || value=1
                break
                ;;
              S) break ;; # -S[<key-id>]: an attached value only
            esac
          done
          ;;
      esac
    fi
  done
  [[ -n $url ]] || hub::exec_git merge "$@"
  [[ -z $extra ]] || hub::die "Aborted: a pull request is merged on its own; unexpected argument: $extra"
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
  # its hash, and the ref goes on every way out.
  tmp=refs/hub/merge/$number-$$
  if ((HUB_NOOP)); then
    args[url_i]=$tmp
    hub::git fetch "$src" "+refs/pull/$number/head:$tmp"
    hub::git merge "${opts[@]}" "${args[@]}"
    hub::git update-ref -d "$tmp"
    exit 0
  fi
  HUB_MERGE_TMP=$tmp
  trap _hub_merge_cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  hub::git fetch "$src" "+refs/pull/$number/head:$tmp" || exit
  oid=$(hub::git_query rev-parse --verify --quiet "$tmp^{commit}") || hub::die "Aborted: could not fetch refs/pull/$number/head from $src"
  args[url_i]=$oid
  hub::git merge "${opts[@]}" "${args[@]}"
}

# _hub_merge_cleanup : remove this run's private ref (set in HUB_MERGE_TMP) on the way out.
_hub_merge_cleanup() {
  [[ -z ${HUB_MERGE_TMP-} ]] || hub::git update-ref -d "$HUB_MERGE_TMP" 2>/dev/null
  return 0
}
