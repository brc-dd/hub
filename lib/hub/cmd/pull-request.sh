# shellcheck shell=bash
# Summary: Open a pull request (gh pr create, with hub's options).
# Usage: hub pull-request [-m MESSAGE... | -F FILE] [-e | --no-edit] [-b BASE] [-h HEAD] [-p] [-f] [-d]
#          [-r REVIEWERS] [-a ASSIGNEES] [-M MILESTONE] [-l LABELS] [--no-maintainer-edits] [-o] [-c] [gh options]
#        hub pull-request -i ISSUE [-b BASE] [-h HEAD] [-p] [-f] [-d] [--no-maintainer-edits] [-o] [-c]
#
#   -m, --message MSG        Title (the first paragraph) and body; repeat to add paragraphs.
#   -F, --file FILE          Read the title and body from FILE ("-" for standard input).
#   -e, --edit               Edit the title and body in gh's editor.
#       --no-edit            Use the first commit's message (gh --fill-first).
#   -b, --base BASE          The branch to merge into: BRANCH, OWNER:BRANCH or OWNER/REPO:BRANCH.
#   -h, --head HEAD          The branch with the changes: BRANCH or OWNER:BRANCH.
#   -p, --push               Push the head first.
#   -f, --force              Name the head as it already is on GitHub, so gh neither pushes nor forks.
#   -d, --draft              Open it as a draft.
#   -r, --reviewer LIST      Request reviews from users or ORG/TEAMs.
#   -a, --assign LIST        Assign users.
#   -M, --milestone NAME     Add it to a milestone.
#   -l, --labels LIST        Add labels.
#       --no-maintainer-edits  Don't let maintainers push to the head branch.
#   -o, --browse             Open the new pull request in the browser.
#   -c, --copy               Copy its URL to the clipboard.
#   -i, --issue ISSUE        Turn an issue (a number or URL) into the pull request.
#
# Other options go to gh, and -R [HOST/]OWNER/REPO replaces the --repo HOST/OWNER/REPO hub always
# passes; spell gh's -b, -F, -m and -p as --body, --body-file, --milestone and --project.
# --dry-run never pushes: hub prints the push, and names the head for gh.
# Before -p pushes, and where -f, --dry-run or -i name the head, the push URLs of the branch's
# push remote must all name one repository on the base's host: the base (head BRANCH), a fork of
# it or a sibling fork (head OWNER:BRANCH); -p -h OWNER:BRANCH pushes to OWNER's remote that does.
# A head owned by an organization is refused (gh pr create can't take it), except with -i.
# -i converts the issue (in the issue URL's repository, else the base repository) through gh api,
# onto that repository's default branch unless -b names another.
#
#   $ hub pull-request -p -m "Fix the frobnicator" -b develop
#   > git push --set-upstream origin HEAD:refs/heads/feature
#   > gh pr create --title "Fix the frobnicator" --body "" --repo github.com/mislav/dotfiles --base develop --head feature

hub_cmd_pull_request() {
  # The options that take a value: hub's, then those of gh pr create that hub passes on.
  local takes=' -m --message -F --file -b -B --base -h -H --head -r --reviewer -a --assign -M --milestone -l --labels -i --issue -R --repo -t --title -T --template --body --body-file --label --assignee --project --attach --recover '
  local -a messages=() opts=() rest=() push_cmd=() cmd=()
  local arg value r file='' base='' head='' issue='' repo='' edit=0 draft=0 no_maint=0 push=0 force=0 browse=0 copy=0 dry_run=0

  while (($#)); do
    arg=$1
    shift
    unset value
    if [[ $arg == -[!-]?* ]]; then # -pf is -p -f; -mMSG and -m=MSG are -m MSG, as in gh
      value=${arg:2}
      if [[ $takes == *" ${arg:0:2} "* ]]; then set -- "${arg:0:2}" "${value#=}" "$@"; else set -- "${arg:0:2}" "-$value" "$@"; fi
      continue
    elif [[ $arg == --*=* && $takes == *" ${arg%%=*} "* ]]; then
      set -- "${arg%%=*}" "${arg#*=}" "$@"
      continue
    elif [[ $takes == *" $arg "* ]]; then
      [[ $arg == -h ]] && (($# == 0)) && hub::usage
      (($#)) || hub::die "Aborted: $arg needs a value."
      value=$1
      shift
    fi
    case $arg in
      --help) hub::usage ;;
      -m | --message) messages+=("$value") ;;
      -F | --file) file=$value ;;
      -b | -B | --base) base=$value ;;
      -h | -H | --head)
        [[ -z $head || $head == "$value" ]] || hub::die "Aborted: two different heads: $head and $value."
        head=$value
        ;;
      -r | --reviewer) opts+=(--reviewer "$value") ;;
      -a | --assign) opts+=(--assignee "$value") ;;
      -M | --milestone) opts+=(--milestone "$value") ;;
      -l | --labels) opts+=(--label "$value") ;;
      -i | --issue) issue=$value ;;
      -e | --edit) edit=1 opts+=(--editor) ;;
      --no-edit) opts+=(--fill-first) ;;
      -d | --draft) draft=1 ;;
      --no-maintainer-edits) no_maint=1 ;;
      -p | --push) push=1 ;;
      -f | --force) force=1 ;;
      -o | --browse) browse=1 ;;
      -c | --copy) copy=1 ;;
      -R | --repo)
        # the push rule needs the base, and gh would read an empty -R as none
        [[ $value =~ ^([A-Za-z0-9.:-]+/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
          || hub::die "Aborted: not a repository: '$value' (use $arg [HOST/]OWNER/REPO)"
        repo=$value
        opts+=("$arg" "$value")
        ;;
      --dry-run | --dry-run=*)
        case ${arg#--dry-run} in # Go's booleans: gh rejects any other value, but only after hub has pushed
          '' | =1 | =t | =T | =TRUE | =true | =True) dry_run=1 ;;
          =0 | =f | =F | =FALSE | =false | =False) dry_run=0 ;;
          *) hub::die "Aborted: not a boolean: $arg" ;;
        esac
        opts+=("$arg")
        ;;
      --)
        rest=(-- "$@")
        break
        ;;
      -?*) opts+=("$arg" ${value+"$value"}) ;;
      *)
        if [[ -z $issue ]] && hub::parse_github_url "$arg" && [[ $HUB_URL_KIND == issues ]]; then issue=$arg; else opts+=("$arg"); fi
        ;;
    esac
  done
  if [[ -n $issue ]] && { ((${#messages[@]} || ${#opts[@]} || ${#rest[@]})) || [[ -n $file ]]; }; then
    hub::die "Aborted: -i keeps the issue's title and body, and takes only -b, -h, -p, -f, -d, --no-maintainer-edits, -o and -c."
  fi
  hub::require_repo

  # The base repository, as HOST/OWNER/REPO: the issue URL's, -R's, -b OWNER[/REPO]:BRANCH's, else the current one.
  local target='' number=''
  if [[ $issue =~ ^#?([0-9]+)$ ]]; then
    number=${BASH_REMATCH[1]}
  elif [[ -n $issue ]]; then
    hub::parse_github_url "$issue" && [[ $HUB_URL_KIND == issues ]] || hub::die "Aborted: not an issue number or URL: $issue"
    target=$HUB_URL_HOST/$HUB_URL_OWNER/$HUB_URL_REPO number=$HUB_URL_NUMBER
  elif [[ -n $repo ]]; then
    target=$repo
    [[ $repo == */*/* ]] || target=$(hub::host)/$repo # gh's default host, as gh reads -R
  fi
  if [[ $base == *:* ]]; then
    [[ -z $target ]] || hub::die "Aborted: name the base repository once: with -R, -b OWNER[/REPO]:BRANCH or an issue URL."
    [[ $base =~ ^([^:/]+)(/[^:/]+)?:(.+)$ ]] || hub::die "Aborted: not a base: $base (use [OWNER[/REPO]:]BRANCH)"
    target=${BASH_REMATCH[1]}${BASH_REMATCH[2]} base=${BASH_REMATCH[3]}
    hub::main_project >/dev/null
    [[ $target == */* ]] || target+=/${HUB_PROJECT#*/}
    target=$HUB_PROJECT_HOST/$target
  elif [[ -z $target ]]; then
    hub::main_project >/dev/null
    target=$HUB_PROJECT_HOST/$HUB_PROJECT
  fi

  # The head: where -p pushes it, and where -f, --dry-run and -i name it unless -h does (the push rule).
  if ((push || (${#head} == 0 && (force || dry_run || ${#issue})))); then
    local host=${target%%/*} owner=${head%%:*} name=${target##*/} branch remote=origin dest pushed p kind
    local -a remotes same=() other=()
    branch=$(hub::current_branch) || branch=''
    dest=$branch
    if [[ -n $branch ]] && hub::push_target "$branch" && [[ $HUB_PUSH_REMOTE != . ]]; then # . is this repository
      remote=$HUB_PUSH_REMOTE dest=$HUB_PUSH_BRANCH
    fi
    [[ -z $head ]] || dest=${head#*:}
    [[ -n $dest ]] || hub::die "Aborted: not currently on any branch; name the head with -h [OWNER:]BRANCH."
    if [[ $head == *:* ]]; then
      # OWNER's remotes: the push remote first, those of the base's name before the rest.
      mapfile -t remotes < <(hub::git_query remote)
      for r in "$remote" "${remotes[@]}"; do
        p=$(_hub_pull_request_push_repo "$r" "$host") || continue
        p=${p,,}
        [[ ${p%%/*} == "${owner,,}" && " ${same[*]} ${other[*]} " != *" $r "* ]] || continue
        if [[ ${p#*/} == "${name,,}" ]]; then same+=("$r"); else other+=("$r"); fi
      done
      remote=''
      for r in "${same[@]}" "${other[@]}"; do
        pushed=$(_hub_pull_request_push_repo "$r" "$host")
        if _hub_pull_request_in_network "$host/$pushed" "$target"; then
          remote=$r
          break
        fi
      done
      [[ -n $remote ]] || hub::die "Aborted: no remote here pushes to a repository of $owner's that is ${target#*/}, a fork of it or a sibling fork."
    else
      pushed=$(_hub_pull_request_push_repo "$remote" "$host") \
        || hub::die "Aborted: remote $remote must push to one repository on $host (git remote get-url --push --all $remote)."
      _hub_pull_request_in_network "$host/$pushed" "$target" \
        || hub::die "Aborted: remote $remote pushes to $pushed, which is not ${target#*/}, a fork of it or a sibling fork."
    fi
    if ((push)); then
      push_cmd=(push "$remote" "HEAD:refs/heads/$dest")
      [[ -n $head ]] || push_cmd=(push --set-upstream "$remote" "HEAD:refs/heads/$dest")
    fi
    if [[ ${host,,}/${pushed,,} == "${target,,}" ]]; then
      head=${head:-$dest}
    else
      [[ $head == *:* ]] || head=${pushed%%/*}:$dest
      if [[ -z $issue ]]; then # the REST API that -i uses takes such a head
        kind=$(hub::gh_query api --hostname "$host" "users/${head%%:*}" -q .type) || hub::die "Aborted: could not look up ${head%%:*} on $host."
        [[ $kind != Organization ]] || hub::die "Aborted: gh pr create cannot take a head owned by an organization ($head); use gh api repos/${target#*/}/pulls."
      fi
    fi
  fi

  # The gh command: gh api for -i, else gh pr create.
  if [[ -n $issue ]]; then
    if [[ -z $base ]] && r=$(hub::remote_for_project "${target#*/}" "${target%%/*}"); then
      base=$(hub::default_branch "$r")
    elif [[ -z $base ]]; then
      base=$(hub::gh_query repo view "$target" --json defaultBranchRef -q .defaultBranchRef.name) && [[ -n $base ]] \
        || hub::die "Aborted: could not look up the default branch of ${target#*/}; give the base with -b BRANCH."
    fi
    cmd=(api --hostname "${target%%/*}" "repos/${target#*/}/pulls" -F "issue=$number" -F "head=$head" -f "base=$base")
    ((draft)) && cmd+=(-F draft=true)
    ((no_maint)) && cmd+=(-F maintainer_can_modify=false)
    cmd+=(--jq .html_url)
  else
    cmd=(pr create)
    if ((${#messages[@]})) || [[ -n $file ]]; then
      hub::message "$file" "${messages[@]}"
      [[ -n $HUB_MSG_TITLE ]] || ((edit)) || hub::die "Aborted: the pull request title is empty."
      [[ -z $HUB_MSG_TITLE ]] || cmd+=(--title "$HUB_MSG_TITLE" --body "$HUB_MSG_BODY") # an empty body too: gh then doesn't prompt
    fi
    [[ -n $repo ]] || cmd+=(--repo "$target")
    [[ -z $base ]] || cmd+=(--base "$base")
    [[ -z $head ]] || cmd+=(--head "$head")
    ((draft)) && cmd+=(--draft)
    ((no_maint)) && cmd+=(--no-maintainer-edit)
    cmd+=("${opts[@]}" "${rest[@]}")
  fi

  if ((${#push_cmd[@]})); then
    if ((dry_run)); then HUB_NOOP=1 hub::git "${push_cmd[@]}"; else hub::git "${push_cmd[@]}" || exit; fi
  fi
  if ((HUB_NOOP || dry_run || ! (browse || copy))); then
    hub::gh "${cmd[@]}"
    return
  fi
  local out
  out=$(hub::gh_query "${cmd[@]}") || exit # to open or copy the URL gh prints (gh can't prompt then)
  printf '%s\n' "$out"
  if ((browse)); then hub::open_url "${out##*$'\n'}"; fi
  if ((copy)); then hub::copy "${out##*$'\n'}"; fi
}

# _hub_pull_request_push_repo REMOTE HOST : print the OWNER/REPO that every push URL of REMOTE
# names on HOST (git remote get-url --push --all applies insteadOf and pushInsteadOf). Fails if
# REMOTE has none, or one is a path, on another host or another repository.
_hub_pull_request_push_repo() {
  local url repo=''
  while IFS= read -r url; do
    hub::parse_remote_url "$url" || return 1
    hub::same_host "$HUB_URL_HOST" "$2" || hub::same_host "$(hub::ssh_hostname "$HUB_URL_HOST")" "$2" || return 1
    [[ -z $repo || ${repo,,} == "${HUB_URL_OWNER,,}/${HUB_URL_REPO,,}" ]] || return 1
    repo=$HUB_URL_OWNER/$HUB_URL_REPO
  done < <(hub::git_query remote get-url --push --all "$1")
  [[ -n $repo ]] && printf '%s\n' "$repo"
}

# _hub_pull_request_in_network HOST/OWNER/REPO BASE : true if that repository is BASE (also
# HOST/OWNER/REPO), a fork of it, or a fork of BASE's parent. Dies if GitHub can't be asked.
_hub_pull_request_in_network() {
  local base=${2#*/} parent base_parent jq='.parent // empty | .owner.login + "/" + .name' # gh's parent has no nameWithOwner
  [[ ${1,,} == "${2,,}" ]] && return 0
  parent=$(hub::gh_query repo view "$1" --json parent -q "$jq") || hub::die "Aborted: could not look up $1."
  [[ -n $parent ]] || return 1
  [[ ${parent,,} == "${base,,}" ]] && return 0
  base_parent=$(hub::gh_query repo view "$2" --json parent -q "$jq") || hub::die "Aborted: could not look up $2."
  [[ ${parent,,} == "${base_parent,,}" ]]
}
