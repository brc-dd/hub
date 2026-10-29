# shellcheck shell=bash
# Summary: Open a pull request (gh pr create, with hub's options).
# Usage: hub pull-request [-m MESSAGE ... | -F FILE] [-e] [-b BASE] [-h HEAD] [-p] [-f] [-d]
#                         [-r REVIEWERS] [-a ASSIGNEES] [-M MILESTONE] [-l LABELS]
#                         [--no-maintainer-edits] [-o] [-c] [gh pr create options]
#        hub pull-request -i ISSUE | ISSUE-URL [-b BASE] [-h HEAD] [-p] [-d] [-o] [-c]
#
# Creates the pull request with `gh pr create`. The options are hub's and are
# translated for gh; any other option is passed to gh unchanged (--fill,
# -T TEMPLATE, -R OWNER/REPO for a base in another repository, --dry-run, ...).
#
#   -m, --message MSG      The first paragraph is the title, the rest the body.
#                          Repeat -m to add paragraphs.
#   -F, --file FILE        Read the title and body from FILE ("-" for stdin).
#   -e, --edit             Edit the title and body in gh's editor (gh --editor).
#       --no-edit          Use the first commit's message (gh --fill-first).
#   -b, --base BRANCH      The branch to merge into (gh --base).
#   -h, --head [OWNER:]BRANCH  The branch with the changes (gh --head).
#   -d, --draft            Open it as a draft.
#   -r, --reviewer LIST    Request reviews from users or ORG/TEAMs (comma-separated).
#   -a, --assign LIST      Assign users (gh --assignee).
#   -M, --milestone NAME   Add it to a milestone, by title.
#   -l, --labels LIST      Add labels; they must already exist (gh --label).
#       --no-maintainer-edits  Don't let maintainers push to the branch.
#   -p, --push             First push the current branch to its push remote
#                          (branch.<name>.pushRemote, remote.pushDefault,
#                          branch.<name>.remote, else origin).
#   -f, --force            Use the branch as it already is on GitHub, so gh neither
#                          pushes nor forks (gh --head BRANCH, or OWNER:BRANCH when
#                          the branch's push remote is a fork).
#   -o, --browse           Open the new pull request in the browser.
#   -c, --copy             Copy the new pull request's URL to the clipboard.
#   -i, --issue ISSUE      Turn an issue (number or URL) into the pull request.
#
# Without -m, -F, -e or --no-edit, gh asks for the title and body. With -o or
# -c, hub reads the URL gh prints, so gh cannot prompt: give a title (-m, -F,
# --no-edit or --fill) and push first (-p) unless the branch is already pushed.
#
# -i uses the "issue" field of GitHub's create-pull-request REST API, which
# GitHub still supports but gh does not expose, so hub calls `gh api`. The
# issue keeps its number, title, body and comments. The head defaults to
# OWNER:BRANCH for the current branch and its push remote, the base to the
# default branch. -m, -F, -e, -r, -a, -M and -l don't apply; add reviewers and
# labels afterwards with `gh pr edit`.
#
#   $ hub pull-request -p -m "Fix the frobnicator" -b develop -r alice
#   > git push --set-upstream origin HEAD
#   > gh pr create --title "Fix the frobnicator" --body "" --base develop --reviewer alice
#
#   $ hub pull-request -i 123
#   > gh api repos/{owner}/{repo}/pulls -F issue=123 -F head=mislav:feature -f base=main --jq .html_url

hub_cmd_pull_request() {
  local -a messages=() reviewers=() assignees=() labels=() passthrough=() cmd=()
  local file='' base='' head='' milestone='' issue='' arg after_option=0 follows_option
  local edit=0 no_edit=0 draft=0 no_maint=0 push=0 force=0 browse=0 copy=0

  while (($#)); do
    arg=$1
    shift
    follows_option=$after_option after_option=0
    if [[ $arg == -[!-]?* ]]; then
      # Split clusters: -pf -> -p -f, -mMSG -> -m MSG. A cluster that starts with
      # a letter hub doesn't know is one of gh's and goes through untouched.
      case ${arg:1:1} in
        [edpfoc])
          set -- "${arg:0:2}" "-${arg:2}" "$@"
          continue
          ;;
        [mFbhraMli])
          set -- "${arg:0:2}" "${arg:2}" "$@"
          continue
          ;;
      esac
    fi
    case $arg in
      --help) hub::usage ;;
      --message=* | --file=* | --base=* | --head=* | --reviewer=* | --assign=* | --milestone=* | --labels=* | --issue=*)
        set -- "${arg%%=*}" "${arg#*=}" "$@"
        ;;
      -h | --head)
        [[ $arg == -h && ($# -eq 0 || $1 == -*) ]] && hub::usage # a bare -h asks for help
        _hub_pull_request_need "$arg" $#
        head=$1
        shift
        ;;
      -m | --message)
        _hub_pull_request_need "$arg" $#
        messages+=("$1")
        shift
        ;;
      -F | --file)
        _hub_pull_request_need "$arg" $#
        file=$1
        shift
        ;;
      -b | --base)
        _hub_pull_request_need "$arg" $#
        base=$1
        shift
        ;;
      -r | --reviewer)
        _hub_pull_request_need "$arg" $#
        reviewers+=("$1")
        shift
        ;;
      -a | --assign)
        _hub_pull_request_need "$arg" $#
        assignees+=("$1")
        shift
        ;;
      -M | --milestone)
        _hub_pull_request_need "$arg" $#
        milestone=$1
        shift
        ;;
      -l | --labels)
        _hub_pull_request_need "$arg" $#
        labels+=("$1")
        shift
        ;;
      -i | --issue)
        _hub_pull_request_need "$arg" $#
        issue=$1
        shift
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
        passthrough+=(-- "$@")
        break
        ;;
      --*=*) passthrough+=("$arg") ;;
      -?*)
        # One of gh's options. If it stands alone, the next word may be its value.
        passthrough+=("$arg")
        [[ ${#arg} -eq 2 || $arg == --* ]] && after_option=1
        ;;
      *)
        if ((! follows_option)) && [[ -z $issue ]] && _hub_pull_request_issue_url "$arg"; then
          issue=$arg
        else
          passthrough+=("$arg")
        fi
        ;;
    esac
  done

  hub::require_repo
  if ((${#messages[@]})) && [[ -n $file ]]; then
    hub::die "Aborted: -m and -F cannot be used together."
  fi
  local branch
  branch=$(hub::current_branch) || branch=''

  if [[ -n $issue ]]; then
    if ((${#messages[@]} || edit || no_edit)) || [[ -n $file ]]; then
      hub::die "Aborted: -i uses the issue's title and body; drop -m, -F, -e and --no-edit."
    fi
    if ((${#reviewers[@]} || ${#assignees[@]} || ${#labels[@]})) || [[ -n $milestone ]]; then
      hub::die "Aborted: -i cannot add reviewers, assignees, labels or a milestone; add them afterwards with gh pr edit."
    fi
    if ((${#passthrough[@]})); then
      hub::die "Aborted: -i does not take gh pr create options: $(hub::quote "${passthrough[@]}")"
    fi
    local repo='{owner}/{repo}' host number owner
    if _hub_pull_request_issue_url "$issue"; then
      repo=$HUB_URL_OWNER/$HUB_URL_REPO host=$HUB_URL_HOST number=$HUB_URL_NUMBER
    else
      number=${issue#\#}
      [[ $number =~ ^[0-9]+$ ]] || hub::die "Aborted: not an issue number or issue URL: $issue"
      hub::main_project >/dev/null # sets HUB_PROJECT_HOST
      host=$HUB_PROJECT_HOST
    fi
    if [[ -z $head ]]; then
      [[ -n $branch ]] || hub::die "Aborted: not currently on any branch."
      owner=$(hub::remote_project "$(_hub_pull_request_push_remote "$branch")") \
        || owner=$(hub::main_project) || exit
      head=${owner%%/*}:$branch
    fi
    [[ -n $base ]] || base=$(hub::default_branch)
    cmd=(api)
    [[ ${host,,} == github.com ]] || cmd+=(--hostname "$host")
    cmd+=("repos/$repo/pulls" -F "issue=$number" -F "head=$head" -f "base=$base")
    ((draft)) && cmd+=(-F draft=true)
    ((no_maint)) && cmd+=(-F maintainer_can_modify=false)
    cmd+=(--jq .html_url)
  else
    local text='' have_text=0 value
    if ((${#messages[@]})); then
      for value in "${messages[@]}"; do text+=${text:+$'\n\n'}$value; done
      have_text=1
    elif [[ $file == - ]]; then
      text=$(cat)
      have_text=1
    elif [[ -n $file ]]; then
      [[ -r $file && ! -d $file ]] || hub::die "Aborted: cannot read $file"
      text=$(<"$file")
      have_text=1
    fi
    cmd=(pr create)
    if ((have_text)); then
      hub::split_message "$text"
      if [[ -n $HUB_MSG_TITLE ]]; then
        cmd+=(--title "$HUB_MSG_TITLE" --body "$HUB_MSG_BODY") # an explicit body, even empty, stops gh prompting
      elif ((! edit)); then
        hub::die "Aborted: the pull request title is empty."
      fi
    fi
    if ((force)) && [[ -z $head ]]; then
      [[ -n $branch ]] || hub::die "Aborted: not currently on any branch."
      head=$(_hub_pull_request_force_head "$branch")
    fi
    ((edit)) && cmd+=(--editor)
    ((no_edit)) && cmd+=(--fill-first)
    [[ -n $base ]] && cmd+=(--base "$base")
    [[ -n $head ]] && cmd+=(--head "$head")
    ((draft)) && cmd+=(--draft)
    for value in "${reviewers[@]}"; do cmd+=(--reviewer "$value"); done
    for value in "${assignees[@]}"; do cmd+=(--assignee "$value"); done
    [[ -n $milestone ]] && cmd+=(--milestone "$milestone")
    for value in "${labels[@]}"; do cmd+=(--label "$value"); done
    ((no_maint)) && cmd+=(--no-maintainer-edit)
    cmd+=("${passthrough[@]}")
  fi

  if ((push)); then
    [[ -n $branch ]] || hub::die "Aborted: not currently on any branch."
    hub::git push --set-upstream "$(_hub_pull_request_push_remote "$branch")" HEAD || exit
  fi
  _hub_pull_request_create "$browse" "$copy" "${cmd[@]}"
}

# _hub_pull_request_need OPTION ARGS-LEFT : die unless OPTION still has a value after it.
_hub_pull_request_need() { (($2)) || hub::die "Aborted: $1 needs a value."; }

# _hub_pull_request_issue_url STR : true if STR is a GitHub issue URL (sets HUB_URL_*).
_hub_pull_request_issue_url() { hub::parse_github_url "$1" && [[ $HUB_URL_KIND == issues ]]; }

# _hub_pull_request_push_remote BRANCH : the remote `git push` sends BRANCH to:
# branch.BRANCH.pushRemote, remote.pushDefault, branch.BRANCH.remote, else origin.
_hub_pull_request_push_remote() {
  local key remote
  for key in "branch.$1.pushRemote" remote.pushDefault "branch.$1.remote"; do
    remote=$(hub::git_query config --get "$key") || continue
    if [[ -n $remote && $remote != . ]]; then
      printf '%s\n' "$remote"
      return 0
    fi
  done
  printf 'origin\n'
}

# _hub_pull_request_force_head BRANCH : BRANCH, or OWNER:BRANCH when BRANCH's push
# remote belongs to someone other than the main project's owner (a fork).
_hub_pull_request_force_head() {
  local fork main
  fork=$(hub::remote_project "$(_hub_pull_request_push_remote "$1")") || fork=''
  main=$(hub::main_project 2>/dev/null) || main=''
  fork=${fork%%/*} main=${main%%/*}
  if [[ -n $fork && ${fork,,} != "${main,,}" ]]; then
    printf '%s:%s\n' "$fork" "$1"
  else
    printf '%s\n' "$1"
  fi
}

# _hub_pull_request_create BROWSE COPY GH-ARGS... : run gh, which prints the new
# pull request's URL. To open or copy the URL, capture it (gh can't prompt then).
_hub_pull_request_create() {
  local browse=$1 copy=$2 out status=0
  shift 2
  if ((HUB_NOOP || ! (browse || copy))); then
    hub::gh "$@"
    return
  fi
  out=$(hub::gh_query "$@") || status=$?
  [[ -n $out ]] && printf '%s\n' "$out"
  ((status == 0)) || return "$status"
  if ((browse)); then hub::open_url "${out##*$'\n'}"; fi
  if ((copy)); then hub::copy "${out##*$'\n'}"; fi
}
