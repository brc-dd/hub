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
# git merge.
#
#   $ hub merge https://github.com/jingweno/gh/pull/73
#   > git fetch --quiet --no-tags --refmap= -- origin refs/pull/73/head
#   > git merge --no-ff -m 'Merge pull request #73 from jingweno/feature' -m TITLE OID
#
# git's own manual: git merge --help

hub_cmd_merge() {
  local valued='-m --message -F --file -s --strategy -X --strategy-option --into-name --cleanup'
  local cares=' --squash --no-squash --ff --no-ff --ff-only --message --file --no-message'
  cares+=' --abort --quit --continue '
  local word name care i url=-1 extra=-1 ended=0 squash=0 ff=0 message=0 number out source oid
  local -a args=("$@") opts=()
  local -A kind=()
  _hub_merge_scan "$valued" "$@"
  for i in "${HUB_OPERANDS[@]}"; do kind[$i]=operand; done
  for i in "${HUB_VALUES[@]}"; do kind[$i]=value; done
  for ((i = 0; i < $#; i++)); do
    word=${args[i]}
    case ${kind[$i]-} in
      value) continue ;;
      operand)
        if ((! ended && url < 0)) && _hub_merge_is_pull "$word"; then
          url=$i
        elif ((extra < 0)); then
          extra=$i
        fi
        continue
        ;;
    esac
    name=${word%%=*}
    # git expands an abbreviation (--squ, --no-mess=X): hub could misread it.
    if [[ $name == --?* && $cares != *" $name "* ]]; then
      for care in $cares; do
        [[ $care != "$name"?* ]] || hub::exec_git merge "$@"
      done
    fi
    case $word in
      -- | --end-of-options) ended=1 ;;
      --abort | --quit | --continue) hub::exec_git merge "$@" ;;
      --squash) squash=1 ;;
      --no-squash) squash=0 ;;
      --ff | --no-ff | --ff-only) ff=1 ;;
      -m* | -F* | --message* | --file* | --no-message) message=1 ;;
    esac
  done
  ((url >= 0)) || hub::exec_git merge "$@"
  if ((extra >= 0)); then
    hub::die "a pull request is merged alone (unexpected argument: $(hub::quote "${args[extra]}"))"
  fi
  hub::require_repo
  hub::require_gh
  out=$(gh pr view "${args[url]}" --json number,title,headRepositoryOwner,headRefName --jq \
    '"Merge pull request #\(.number) from \(.headRepositoryOwner.login)/\(.headRefName)", .title') \
    || exit 1
  ((squash || ff)) || opts+=(--no-ff)
  ((squash || message)) || opts+=(-m "${out%%$'\n'*}" -m "${out#*$'\n'}")
  hub::parse_github_url "${args[url]}"
  number=${HUB_URL[number]}
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

# _hub_merge_is_pull WORD : WORD is the URL of a pull request (not of a commit or patch of it).
_hub_merge_is_pull() {
  hub::parse_github_url "$1" && [[ ${HUB_URL[kind]} == pull && -n ${HUB_URL[number]-} ]] \
    && [[ -z ${HUB_URL[sha]-}${HUB_URL[format]-} ]]
}

# _hub_merge_scan VALUED ARGS... : hub::scan, which also sets HUB_VALUES (the indexes of separate
# values), reads -S as taking the rest of its word (the key) and hands -h in any cluster to git.
_hub_merge_scan() {
  local valued=" $1 " word long i j
  shift
  local -a args=("$@")
  HUB_OPERANDS=() HUB_VALUES=()
  for ((i = 0; i < $#; i++)); do
    word=${args[i]}
    case $word in
      -- | --end-of-options) for ((i += 1; i < $#; i++)); do HUB_OPERANDS+=("$i"); done ;;
      --help) hub::exec_git merge "$@" ;;
      --*=*) ;;
      --*)
        if [[ $valued == *" $word "* ]]; then
          ((i + 1 < $#)) || hub::exec_git merge "$@"
          HUB_VALUES+=($((i += 1)))
          continue
        fi
        for long in $valued; do
          [[ $long != "$word"?* ]] || hub::exec_git merge "$@"
        done
        ;;
      -?*)
        if [[ $valued == *" ${word:0:2} "* ]]; then
          ((${#word} > 2 || i + 1 < $#)) || hub::exec_git merge "$@"
          ((${#word} > 2)) || HUB_VALUES+=($((i += 1)))
          continue
        fi
        for ((j = 1; j < ${#word}; j++)); do
          [[ ${word:j:1} != S ]] || break
          [[ ${word:j:1} != h && $valued != *" -${word:j:1} "* ]] || hub::exec_git merge "$@"
        done
        ;;
      *) HUB_OPERANDS+=("$i") ;;
    esac
  done
}
