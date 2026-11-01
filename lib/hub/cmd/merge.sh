# shellcheck shell=bash
# Summary: Merge a pull request locally, with the message GitHub's merge button uses.
# Usage: hub merge [GIT-MERGE-OPTIONS...] PULL-REQUEST-URL
#
# A git command hub extends: git merge's options apply. The pull request's head is fetched from
# its repository (through a remote that points at it, else its URL), without tags and without
# updating any branch, and merged into the current branch with --no-ff and the message "Merge
# pull request #N from OWNER/BRANCH" followed by the title. --ff, --no-ff or --ff-only replace
# hub's --no-ff; -m, -F or --no-message replace its message; --squash leaves both out. The pull
# request is merged alone: any other operand is an error. Nothing is pushed (gh pr merge merges
# on GitHub). Without a pull request URL, or with --abort, --quit or --continue, this is plain
# git merge; so is a URL of only some of the pull request's changes (.../pull/N/commits/SHA,
# .../pull/N/files/SHA) or of its patch.
#
#   $ hub merge https://github.com/jingweno/gh/pull/73
#   > git fetch --quiet --no-tags --refmap= -- origin refs/pull/73/head
#   > git merge --no-ff -m 'Merge pull request #73 from jingweno/feature' -m TITLE FULL-SHA
#
# git's own manual: git merge --help

hub_cmd_merge() {
  local valued='-m --message -F --file -s --strategy -X --strategy-option --into-name --cleanup'
  local cares=' --squash --no-squash --ff --no-ff --ff-only --message --file --no-message'
  cares+=' --abort --quit --continue '
  local word name care i url=-1 extra=-1 end=$# squash=0 ff=0 message=0 number out source oid
  local -a args=("$@") opts=()
  hub::scan "$valued -S=" "$@"
  for i in "${HUB_OPTIONS[@]}"; do
    word=${args[i]} name=${args[i]%%=*}
    # git expands an abbreviation (--squ, --no-mess=X): hub could misread it.
    if [[ $name == --?* && $cares != *" $name "* ]]; then
      for care in $cares; do
        [[ $care != "$name"?* ]] || hub::exec_git merge "$@"
      done
    fi
    case $word in
      -- | --end-of-options) end=$i ;;
      --abort | --quit | --continue) hub::exec_git merge "$@" ;;
      --squash) squash=1 ;;
      --no-squash) squash=0 ;;
      --ff | --no-ff | --ff-only) ff=1 ;;
      -m* | -F* | --message* | --file* | --no-message) message=1 ;;
    esac
  done
  for i in "${HUB_OPERANDS[@]}"; do
    # The pull request itself, not a commit, a patch or a page of some of its changes.
    if ((i < end && url < 0)) && hub::patch_url "${args[i]}" && [[ ${HUB_URL[kind]} == pull ]] \
      && [[ -z ${HUB_URL[sha]-}${HUB_URL[format]-} ]]; then
      url=$i
    elif ((extra < 0)); then
      extra=$i
    fi
  done
  ((url >= 0)) || hub::exec_git merge "$@"
  if ((extra >= 0)); then
    hub::usage_error \
      "unexpected argument: $(hub::shown "${args[extra]}") (a pull request is merged alone)"
  fi
  hub::require_repo
  hub::require_gh
  out=$(gh pr view "${args[url]}" --json number,title,headRepositoryOwner,headRefName --jq \
    '"Merge pull request #\(.number) from \(.headRepositoryOwner.login)/\(.headRefName)", .title') \
    || exit
  ((squash || ff)) || opts+=(--no-ff)
  ((squash || message)) || opts+=(-m "${out%%$'\n'*}" -m "${out#*$'\n'}")
  hub::parse_github_url "${args[url]}"
  # gh reads the number in decimal (pull/012 is #12); the ref must name that pull request too.
  number=$((10#${HUB_URL[number]}))
  source=$(hub::fetch_source "${HUB_URL[host]}" "${HUB_URL[owner]}" "${HUB_URL[repo]}")
  # --refmap= keeps a configured refs/pull/* refspec from updating local branches.
  hub::git fetch --quiet --no-tags --refmap= -- "$source" "refs/pull/$number/head" || exit
  oid=FETCH_HEAD
  # FETCH_HEAD is shared with every other fetch: read it at once and merge by the oid.
  [[ ${HUB_NOOP-} == 1 ]] || oid=$(git rev-parse --verify --quiet FETCH_HEAD) \
    || hub::die "could not read refs/pull/$number/head from FETCH_HEAD"
  args[url]=$oid
  hub::exec_git merge "${opts[@]}" "${args[@]}"
}
