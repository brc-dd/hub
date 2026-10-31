# shellcheck shell=bash
# Summary: Open a pull request for the current branch (gh pr create, with hub's options).
# Usage: hub pull-request [-fpdoc] [-b [OWNER:]BASE] [-h [OWNER:]HEAD] [-r REVIEWERS] [-a ASSIGNEES]
#          [-M MILESTONE] [-l LABELS] [--no-maintainer-edits] [-m MESSAGE... | -F FILE] [-e | --no-edit]
#        hub pull-request [-fpdoc] [-b [OWNER:]BASE] [-h [OWNER:]HEAD] [--no-maintainer-edits] -i ISSUE
#        hub pull-request [-fpdoc] [-b BASE] [-h [OWNER:]HEAD] [--no-maintainer-edits] ISSUE-URL
#
# A hub-owned command: these are all of its options, and anything else is an error. The pull
# request is opened with `gh pr create` in the current project (GH_REPO, else the upstream, github
# or origin remote), or in the repository that -b OWNER[/REPO]:BASE or an issue URL names, on the
# project's host.
#
# The head is the current branch, named for gh as it is where `git push` sends it: on the remote
# git would push to (remote.*.push, branch.*.pushRemote, remote.pushDefault, branch.*.remote and
# push.default), under its name there, in the repository that remote's push URL names, written
# OWNER:BRANCH when that is not the base repository. A branch without an upstream goes to the
# remote `git push -u` would take; one that `git push` would not push as configured (push.default
# nothing, or remote.*.push refspecs that map other branches) is refused. Without -p, the branch
# must already be pushed there, which its remote-tracking branch shows; a remote that fetches
# from one repository and pushes to another shows nothing, and is refused without -p or -f. -f
# skips that check. -h BRANCH names a branch on that remote instead, pushed from HEAD with -p; -h
# OWNER:BRANCH names a branch in OWNER's repository, pushed with -p to the remote here whose push
# URL names it (owner and repository names compare without regard to case, as on GitHub). gh pr
# create cannot open a pull request from a repository owned by an organization; the API that -i
# uses can, and gets the head repository's name (head_repo) when it is another repository than
# the base and a remote here pushes to it, as the API requires within one organization.
#
# The base defaults to branch.BRANCH.gh-merge-base of the current branch, else the default branch
# of the base repository (refs/remotes/REMOTE/HEAD when it points at a branch that still exists,
# else gh's answer). Without -m, -F, -e or --no-edit, gh asks for the title and body, which needs a
# terminal; -o and -c leave the prompts alone and look the URL up afterwards.
#
# Options:
#   -m, --message MESSAGE  The title (the text up to the first blank line) and the body; repeated
#                          MESSAGEs are joined as paragraphs.
#   -F, --file FILE        Read the title and body from FILE ("-" for standard input).
#   -e, --edit             Open gh's editor for the title and body, filled from -m or -F if given.
#       --no-edit          Use the message of the first commit on the branch, without an editor.
#   -i, --issue ISSUE      Convert an issue (a number or URL) into the pull request through the
#                          API, which keeps its title and body; takes only -b, -h, -p, -f, -d,
#                          --no-maintainer-edits, -o and -c.
#   -b, --base BASE        The branch to merge into: BRANCH, OWNER:BRANCH or OWNER/REPO:BRANCH.
#   -h, --head HEAD        The branch with the changes: BRANCH or OWNER:BRANCH.
#   -p, --push             Push HEAD to the head branch first, with --set-upstream when the
#                          current branch has no upstream, once every check has passed.
#   -f, --force            Skip the check that the current branch is pushed.
#   -d, --draft            Open it as a draft.
#   -r, --reviewer LIST    Request reviews from users or ORG/TEAMs (comma-separated, repeatable).
#   -a, --assign LIST      Assign users (comma-separated, repeatable).
#   -M, --milestone NAME   Add it to a milestone.
#   -l, --labels LIST      Add labels (comma-separated, repeatable).
#       --no-maintainer-edits  Don't let the base repository's maintainers push to the head.
#   -o, --browse           Open the new pull request in the browser.
#   -c, --copy             Copy its URL to the clipboard.
#
# -o and -c look the URL up with gh pr view once the pull request exists. The command fails when
# gh, the browser or the clipboard tool fails, after what already happened is done.
#
#   $ hub pull-request -p -m "Fix the frobnicator" -b develop
#   > git push --set-upstream origin HEAD:refs/heads/feature
#   > gh pr create --repo github.com/mislav/dotfiles --base develop --head feature --title Fix\ the\ frobnicator --body ''
#   $ hub pull-request -i 12
#   > gh api --hostname github.com -X POST repos/mislav/dotfiles/pulls -F issue=12 -f head=feature -f base=main --jq .html_url

hub_cmd_pull_request() {
  local usage='Usage: hub pull-request [-fpdoc] [-b [OWNER:]BASE] [-h [OWNER:]HEAD] [-r REVIEWERS] [-a ASSIGNEES] [-M MILESTONE] [-l LABELS] [--no-maintainer-edits] [-m MESSAGE... | -F FILE] [-e | --no-edit] | -i ISSUE | ISSUE-URL'
  hub::normalize_opts mFbhraMli '--message --file --base --head --reviewer --assign --milestone --labels --issue' "$@"
  set -- "${HUB_ARGS[@]}"
  local -a messages=() reviewers=() assignees=() labels=() operands=()
  local arg value file='' base='' head='' issue='' milestone=''
  local edit=0 no_edit=0 draft=0 no_maint=0 push=0 force=0 browse=0 copy=0
  while (($#)); do
    arg=$1
    shift
    case $arg in
      --help) hub::usage ;;
      -m | --message | -F | --file | -b | --base | -h | --head | -r | --reviewer | -a | --assign | -M | --milestone | -l | --labels | -i | --issue)
        if (($# == 0)); then
          [[ $arg == -h ]] && hub::usage # a bare -h asks for the manual
          hub::die "Aborted: $arg needs a value."
        fi
        value=$1
        shift
        case $arg in
          -m | --message) messages+=("$value") ;;
          -F | --file) file=$value ;;
          -b | --base) base=$value ;;
          -h | --head) head=$value ;;
          -r | --reviewer) reviewers+=("$value") ;;
          -a | --assign) assignees+=("$value") ;;
          -M | --milestone) milestone=$value ;;
          -l | --labels) labels+=("$value") ;;
          -i | --issue) issue=$value ;;
        esac
        [[ -n $value || $arg == -m || $arg == --message ]] || hub::die "Aborted: $arg needs a value."
        ;;
      -e | --edit) edit=1 ;;
      --no-edit) no_edit=1 ;;
      -d | --draft) draft=1 ;;
      --no-maintainer-edits) no_maint=1 ;;
      -p | --push) push=1 ;;
      -f | --force) force=1 ;;
      -o | --browse) browse=1 ;;
      -c | --copy) copy=1 ;;
      --)
        operands+=("$@")
        break
        ;;
      -?*) hub::die "hub pull-request: unknown option: $arg"$'\n'"$usage" ;;
      *) operands+=("$arg") ;;
    esac
  done
  for arg in "${operands[@]}"; do # the only operand is an issue URL, which stands for -i URL
    if ! hub::parse_github_url "$arg" || [[ $HUB_URL_KIND != issues ]]; then
      hub::die "hub pull-request: unexpected argument: $arg"$'\n'"$usage"
    fi
    [[ -z $issue || $issue == "$arg" ]] || hub::die "Aborted: name the issue once (-i $issue and $arg)."
    issue=$arg
  done
  hub::require_repo

  # Combinations gh and the API cannot take.
  if [[ -n $issue ]] && { ((${#messages[@]} || ${#reviewers[@]} || ${#assignees[@]} || ${#labels[@]} || edit || no_edit)) || [[ -n $file || -n $milestone ]]; }; then
    hub::die "Aborted: -i converts an issue, which keeps its title and body; it takes only -b, -h, -p, -f, -d, --no-maintainer-edits, -o and -c."
  fi
  ((edit && no_edit)) && hub::die "Aborted: -e and --no-edit cannot be used together."
  if ((no_edit)) && { ((${#messages[@]})) || [[ -n $file ]]; }; then
    hub::die "Aborted: --no-edit takes the message from the first commit; -m and -F give one."
  fi
  local title='' body='' have_message=0
  if ((${#messages[@]})) || [[ -n $file ]]; then
    hub::message "$file" "${messages[@]}"
    title=$HUB_MSG_TITLE body=$HUB_MSG_BODY
    if [[ -n $title ]]; then
      have_message=1
    else
      ((edit)) || hub::die "Aborted: the pull request title is empty."
    fi
  fi

  # The base repository: the issue URL's, -b OWNER[/REPO]:BRANCH's, else the current project.
  local number='' base_host='' base_proj=''
  if [[ $issue =~ ^#?([0-9]+)$ ]]; then
    number=${BASH_REMATCH[1]}
  elif [[ -n $issue ]]; then
    if ! hub::parse_github_url "$issue" || [[ $HUB_URL_KIND != issues ]]; then
      hub::die "Aborted: not an issue number or URL: $issue"
    fi
    base_host=$HUB_URL_HOST base_proj=$HUB_URL_OWNER/$HUB_URL_REPO number=$HUB_URL_NUMBER
  fi
  if [[ $base == *:* ]]; then
    [[ -z $base_proj ]] || hub::die "Aborted: the issue URL names the base repository; give -b as BRANCH alone."
    [[ $base =~ ^([A-Za-z0-9][A-Za-z0-9-]*)(/[A-Za-z0-9_.-]+)?:([^:]+)$ ]] || hub::die "Aborted: not a base: $base (use [OWNER[/REPO]:]BRANCH)"
    local base_owner=${BASH_REMATCH[1]} base_repo=${BASH_REMATCH[2]}
    base=${BASH_REMATCH[3]}
    hub::main_project >/dev/null # its own matches clobber BASH_REMATCH
    base_host=$HUB_PROJECT_HOST base_proj=$base_owner${base_repo:-/${HUB_PROJECT#*/}}
  fi
  if [[ -z $base_proj ]]; then
    hub::main_project >/dev/null
    base_host=$HUB_PROJECT_HOST base_proj=$HUB_PROJECT
  fi
  [[ -z $base ]] || _hub_pull_request_branch_name "$base" -b

  # The head branch, and the remote it is (or with -p will be) on.
  local branch head_owner='' head_name='' remote='' head_proj='' head_known=0 set_upstream=0
  branch=$(hub::current_branch) || branch=''
  case $head in
    '')
      [[ -n $branch ]] || hub::die "Aborted: not currently on any branch; name the head with -h [OWNER:]BRANCH."
      head_name=$branch
      ;;
    *:*)
      head_owner=${head%%:*} head_name=${head#*:}
      [[ $head_owner =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || hub::die "Aborted: not a head: $head (use [OWNER:]BRANCH)"
      ;;
    *) head_name=$head ;;
  esac
  _hub_pull_request_branch_name "$head_name" -h
  if [[ -n $head_owner ]]; then
    head_proj=$head_owner/${base_proj#*/}
    if ((push)); then
      remote=$(_hub_pull_request_remote_of "$head_owner" "$base_host" "${base_proj#*/}" "$branch") \
        || hub::die "Aborted: no remote here pushes to a repository of $head_owner's on $base_host; add one (git remote add $head_owner) or push the branch yourself."
      hub::remote_project "$remote" push >/dev/null
      head_proj=$HUB_PROJECT head_known=1
    fi
  else
    if [[ -z $head ]]; then
      if hub::push_target "$branch"; then
        remote=$HUB_PUSH_REMOTE head_name=$HUB_PUSH_BRANCH
      elif [[ $HUB_PUSH_WHY == upstream ]] && ! hub::git_query config --get "branch.$branch.merge" >/dev/null; then
        remote=$HUB_PUSH_REMOTE # no upstream yet: where `git push -u` would go
      else
        case $HUB_PUSH_WHY in
          remote) hub::die "Aborted: there is no remote $(_hub_pull_request_push_remote "$branch") to push $branch to; add one, or name the head with -h [OWNER:]BRANCH." ;;
          refspec) hub::die "Aborted: git push would not push $branch: remote.$HUB_PUSH_REMOTE.push is configured, and none of its refspecs maps $branch; push it yourself (git push $HUB_PUSH_REMOTE $branch), or name the head with -h [OWNER:]BRANCH." ;;
          destination) hub::die "Aborted: remote.$HUB_PUSH_REMOTE.push maps $branch to something that is not a branch; name the head with -h [OWNER:]BRANCH." ;;
          *) hub::die "Aborted: git push would refuse to push $branch as configured (push.default, branch.$branch.remote and branch.$branch.merge); push it yourself, e.g. git push -u $HUB_PUSH_REMOTE $branch, or name the head with -h [OWNER:]BRANCH." ;;
        esac
      fi
    else
      remote=$(_hub_pull_request_push_remote "$branch")
      hub::remote_exists "$remote" || hub::die "Aborted: there is no remote $remote to find $head_name on; name the head with -h OWNER:BRANCH."
    fi
    hub::remote_project "$remote" push >/dev/null || hub::die "Aborted: remote $remote does not push to a GitHub repository hub knows (git remote get-url --push $remote; see hub.host)."
    hub::same_host "$HUB_PROJECT_HOST" "$base_host" || hub::die "Aborted: remote $remote pushes to $HUB_PROJECT_HOST, but the pull request is for $base_host/$base_proj."
    head_proj=$HUB_PROJECT head_known=1
  fi
  [[ -n $branch ]] && ! hub::git_query config --get "branch.$branch.merge" >/dev/null && set_upstream=1
  local label=$head_name
  [[ ${head_proj,,} == "${base_proj,,}" ]] || label=${head_proj%%/*}:$head_name # as the remote spells the owner, when one is known

  # The base branch: -b, the current branch's gh-merge-base, else the base repository's default.
  local r
  if [[ -z $base && -z $head && -n $branch ]]; then
    base=$(hub::git_query config --get "branch.$branch.gh-merge-base") || base=''
  fi
  if [[ -z $base ]]; then
    if r=$(hub::remote_for_project "$base_proj" "$base_host"); then
      base=$(hub::default_branch "$r")
    elif ! base=$(hub::gh_query repo view "$base_host/$base_proj" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) || [[ -z $base ]]; then
      hub::die "Aborted: could not look up the default branch of $base_proj; give the base with -b BRANCH."
    fi
  fi
  [[ $label == *:* || $head_name != "$base" ]] || hub::die "Aborted: the head and the base are the same branch, $base of $base_proj; name another base with -b or another head with -h."

  # Checks that need no network before the ones that do.
  if ((! push && ! force)) && [[ -z $head ]]; then
    local track n
    # The remote-tracking branches came from the fetch URL: when the remote pushes somewhere else,
    # they show nothing about the repository the head is in.
    if ! hub::remote_project "$remote" >/dev/null || [[ ${HUB_PROJECT,,} != "${head_proj,,}" ]] || ! hub::same_host "$HUB_PROJECT_HOST" "$base_host"; then
      hub::die "Aborted: $remote pushes to $head_proj but fetches from another repository, so hub cannot tell whether $branch is pushed there (use -p to push it, or -f to skip this check)."
    fi
    track=$(hub::git_query for-each-ref --format='%(push)' -- "refs/heads/$branch")
    if [[ -z $track ]] || ! hub::git_query show-ref --verify --quiet -- "$track"; then
      hub::die "Aborted: $branch seems not yet pushed to $remote (use -p to push it, or -f to skip this check)."
    fi
    n=$(hub::git_query rev-list --count "$track..HEAD")
    if ((n == 1)); then
      hub::die "Aborted: 1 commit of $branch is not yet pushed to ${track#refs/remotes/} (use -p to push it, or -f to skip this check)."
    elif ((n > 1)); then
      hub::die "Aborted: $n commits of $branch are not yet pushed to ${track#refs/remotes/} (use -p to push them, or -f to skip this check)."
    fi
  fi
  if ((push)) && [[ -z $issue ]]; then # what gh would refuse after the push, without a terminal
    local can_prompt=0
    [[ -t 0 && -t 1 && -z ${GH_PROMPT_DISABLED:-} ]] && can_prompt=1
    ((! edit || can_prompt)) || hub::die "Aborted: -e needs a terminal (gh opens its editor only in interactive mode); not pushing."
    ((have_message || no_edit || edit || can_prompt)) || hub::die "Aborted: give the title and body with -m or -F (gh asks for them only in interactive mode); not pushing."
  fi
  if ((no_edit)); then
    _hub_pull_request_first_commit "$base_proj" "$base_host" "$base"
    title=$HUB_MSG_TITLE body=$HUB_MSG_BODY have_message=1
  fi
  if [[ $label == *:* && -z $issue ]]; then
    local kind
    kind=$(hub::gh_query api --hostname "$base_host" "users/${label%%:*}" -q .type 2>/dev/null) || hub::die "Aborted: could not look up ${label%%:*} on $base_host."
    [[ $kind != Organization ]] || hub::die "Aborted: gh pr create cannot take a head owned by an organization ($label); convert an issue with -i, or use gh api repos/$base_proj/pulls."
  fi

  local -a cmd
  if [[ -n $issue ]]; then
    cmd=(api --hostname "$base_host" -X POST "repos/$base_proj/pulls" -F "issue=$number" -f "head=$label")
    # the API needs the head repository's name when both belong to one organization; given whenever it is known
    ((head_known)) && [[ ${head_proj,,} != "${base_proj,,}" ]] && cmd+=(-f "head_repo=${head_proj#*/}")
    cmd+=(-f "base=$base")
    ((draft)) && cmd+=(-F draft=true)
    ((no_maint)) && cmd+=(-F maintainer_can_modify=false)
    cmd+=(--jq .html_url)
  else
    cmd=(pr create --repo "$base_host/$base_proj" --base "$base" --head "$label")
    ((have_message)) && cmd+=(--title "$title" --body "$body") # an empty body too, or gh asks for one
    ((edit)) && cmd+=(--editor)
    ((draft)) && cmd+=(--draft)
    ((no_maint)) && cmd+=(--no-maintainer-edit)
    for r in "${reviewers[@]}"; do cmd+=(--reviewer "$r"); done
    for r in "${assignees[@]}"; do cmd+=(--assignee "$r"); done
    [[ -z $milestone ]] || cmd+=(--milestone "$milestone")
    for r in "${labels[@]}"; do cmd+=(--label "$r"); done
  fi

  # Side effects, in order: the push, the pull request, the URL, the browser and the clipboard.
  if ((push)); then
    local -a push_cmd=(push)
    ((set_upstream)) && push_cmd+=(--set-upstream)
    hub::git "${push_cmd[@]}" "$remote" "HEAD:refs/heads/$head_name" || exit
  fi
  local url
  if [[ -n $issue ]]; then
    if ((HUB_NOOP)); then
      hub::gh "${cmd[@]}"
      return 0
    fi
    url=$(hub::gh "${cmd[@]}") || exit # the API answers with the pull request; nothing to prompt for
    printf '%s\n' "$url"
  else
    hub::gh "${cmd[@]}" || exit # gh's prompts and output are the user's; it prints the URL
    ((browse || copy)) || return 0
    if ((HUB_NOOP)); then
      hub::gh pr view "$label" --repo "$base_host/$base_proj" --json url --jq .url
      return 0
    fi
    if ! url=$(hub::gh_query pr view "$label" --repo "$base_host/$base_proj" --json url --jq .url) || [[ $url != http* ]]; then
      hub::die "Aborted: the pull request exists, but its URL could not be looked up (gh pr view $label --repo $base_host/$base_proj)."
    fi
  fi
  local status=0
  if ((copy)); then hub::copy "$url" || status=$?; fi
  if ((browse)); then hub::open_url "$url" || status=$?; fi
  return "$status"
}

# _hub_pull_request_branch_name NAME OPTION : NAME is a well-formed branch name (given with OPTION).
_hub_pull_request_branch_name() {
  hub::git_query check-ref-format "refs/heads/$1" || hub::die "Aborted: not a branch name: $1 (given with $2)"
}

# _hub_pull_request_push_remote [BRANCH] : the remote `git push` would take for BRANCH
# (branch.*.pushRemote, remote.pushDefault, branch.*.remote), else remote.pushDefault, else origin.
_hub_pull_request_push_remote() {
  local r=''
  [[ -z ${1-} ]] || r=$(hub::git_query for-each-ref --format='%(push:remotename)' -- "refs/heads/$1")
  [[ -n $r ]] || r=$(hub::git_query config --get remote.pushDefault) || r=origin
  printf '%s\n' "$r"
}

# _hub_pull_request_remote_of OWNER HOST NAME [BRANCH] : the remote whose push URL names a repository
# of OWNER's on HOST: the one BRANCH pushes to when it does, else one of the repository NAME, else any.
_hub_pull_request_remote_of() {
  local owner=${1,,} host=$2 name=${3,,} branch=${4-} r proj first='' any=''
  local -a remotes
  [[ -z $branch ]] || first=$(hub::git_query for-each-ref --format='%(push:remotename)' -- "refs/heads/$branch")
  mapfile -t remotes < <(hub::git_query remote)
  for r in ${first:+"$first"} "${remotes[@]}"; do
    hub::remote_project "$r" push >/dev/null || continue
    hub::same_host "$HUB_PROJECT_HOST" "$host" || continue
    proj=${HUB_PROJECT,,} # GitHub names compare without regard to case
    [[ ${proj%%/*} == "$owner" ]] || continue
    if [[ $r == "$first" || ${proj#*/} == "$name" ]]; then
      printf '%s\n' "$r"
      return 0
    fi
    [[ -n $any ]] || any=$r
  done
  [[ -n $any ]] && printf '%s\n' "$any"
}

# _hub_pull_request_first_commit OWNER/REPO HOST BASE : HUB_MSG_TITLE and HUB_MSG_BODY from the first
# commit of HEAD that is not on BASE as fetched from the remote here that points at the base
# repository (for --no-edit; gh's --fill-first would read a local branch named like the head).
_hub_pull_request_first_commit() {
  local r ref
  local -a commits
  r=$(hub::remote_for_project "$1" "$2") || hub::die "Aborted: --no-edit takes the message from the commits since $3, but no remote here points at $2/$1 to compare with."
  ref=refs/remotes/$r/$3
  hub::git_query show-ref --verify --quiet -- "$ref" || hub::die "Aborted: --no-edit needs $r/$3 locally; run git fetch $r first."
  mapfile -t commits < <(hub::git_query rev-list --reverse "$ref..HEAD")
  ((${#commits[@]})) || hub::die "Aborted: no commits between $r/$3 and HEAD to take the message from."
  HUB_MSG_TITLE=$(hub::git_query log -1 --format=%s "${commits[0]}")
  HUB_MSG_BODY=$(hub::git_query log -1 --format=%b "${commits[0]}")
  HUB_MSG_BODY=${HUB_MSG_BODY%"${HUB_MSG_BODY##*[![:space:]]}"}
  [[ -n $HUB_MSG_TITLE ]] || hub::die "Aborted: the first commit since $r/$3, ${commits[0]:0:7}, has no subject to use as the title."
}
