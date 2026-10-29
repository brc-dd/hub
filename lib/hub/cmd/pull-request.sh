# shellcheck shell=bash
# Summary: Open a pull request (gh pr create, with hub's options).
# Usage: hub pull-request [-m MESSAGE ... | -F FILE] [-e] [-b BASE] [-h HEAD] [-p] [-f] [-d]
#                         [-r REVIEWERS] [-a ASSIGNEES] [-M MILESTONE] [-l LABELS]
#                         [--no-maintainer-edits] [-o] [-c] [gh pr create options]
#        hub pull-request -i ISSUE | ISSUE-URL [-b BASE] [-h HEAD] [-p] [-d] [-o] [-c]
#
# Creates the pull request with `gh pr create`. The options are hub's and are
# translated for gh; any other option is passed to gh unchanged, together with
# its value (--fill, --title TITLE, -T TEMPLATE, -R OWNER/REPO, --dry-run, ...).
# Where hub and gh use the same letter, hub's meaning wins: spell gh's -b, -F,
# -m and -p as --body, --body-file, --milestone and --project NAME. gh's -B and
# -H are the same as hub's -b and -h.
#
#   -m, --message MSG      The first paragraph is the title, the rest the body.
#                          Repeat -m to add paragraphs.
#   -F, --file FILE        Read the title and body from FILE ("-" for stdin).
#   -e, --edit             Edit the title and body in gh's editor (gh --editor).
#       --no-edit          Use the first commit's message (gh --fill-first).
#   -b, --base [OWNER[/REPO]:]BRANCH
#                          The branch to merge into (gh --base). OWNER/REPO:BRANCH
#                          is a base in another repository of the network (gh
#                          --repo HOST/OWNER/REPO, on the current repository's
#                          host); OWNER:BRANCH, in OWNER's repository of this name.
#   -h, --head [OWNER:]BRANCH  The branch with the changes (gh --head).
#   -d, --draft            Open it as a draft.
#   -r, --reviewer LIST    Request reviews from users or ORG/TEAMs (comma-separated).
#   -a, --assign LIST      Assign users (gh --assignee).
#   -M, --milestone NAME   Add it to a milestone, by title.
#   -l, --labels LIST      Add labels; they must already exist (gh --label).
#       --no-maintainer-edits  Don't let maintainers push to the branch.
#   -p, --push             First push the current branch to its push remote
#                          (branch.<name>.pushRemote, remote.pushDefault,
#                          branch.<name>.remote, else origin). With -h BRANCH,
#                          push HEAD to BRANCH on that remote (and name the
#                          remote's owner in the head if it is a fork); with
#                          -h OWNER:BRANCH, to BRANCH on the remote for OWNER's
#                          repository of this name, which must push nowhere
#                          else: hub stops if any URL it pushes to (git remote
#                          get-url --push --all) is another repository.
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
# gh's --dry-run never pushes, locally or through gh: hub only prints the push
# -p would make, and unless -h names the head, hub names it for gh as -f does,
# because gh's own dry run may push the branch or fork the repository when it
# has to work the head out itself. -o and -c do nothing then.
#
# -i uses the "issue" field of GitHub's create-pull-request REST API, which
# GitHub still supports but gh does not expose, so hub calls `gh api`. The
# issue keeps its number, title, body and comments, and the pull request opens
# in the issue's repository: an issue URL's, else the current one (or the one
# -b OWNER[/REPO]:BRANCH names). hub names that repository and its host itself
# (gh api --hostname HOST repos/OWNER/REPO/pulls), so gh's default repository
# and GH_HOST don't decide where it goes. The head defaults to OWNER:BRANCH for
# the current branch and its push remote, the base to the default branch of
# the issue's repository. -m, -F, -e, -r, -a, -M and -l don't apply; add
# reviewers and labels afterwards with `gh pr edit`.
#
#   $ hub pull-request -p -m "Fix the frobnicator" -b develop -r alice
#   > git push --set-upstream origin HEAD
#   > gh pr create --title "Fix the frobnicator" --body "" --base develop --reviewer alice
#
#   $ hub pull-request -i 123
#   > gh api --hostname github.com repos/mislav/dotfiles/pulls -F issue=123 -F head=mislav:feature -f base=main --jq .html_url

hub_cmd_pull_request() {
  local -a messages=() reviewers=() assignees=() labels=() passthrough=() rest=() cmd=() push_cmd=()
  local file='' base='' head='' milestone='' issue='' repo='' arg opt value i
  local edit=0 no_edit=0 draft=0 no_maint=0 push=0 force=0 browse=0 copy=0 dry_run=0 gh_head=0

  while (($#)); do
    arg=$1
    shift
    if [[ $arg == -[!-]?* ]]; then
      # Split clusters: -pf -> -p -f, -mMSG -> -m MSG. A cluster that starts with
      # a letter hub doesn't know is one of gh's and goes through untouched.
      case ${arg:1:1} in
        [edpfoc])
          set -- "${arg:0:2}" "-${arg:2}" "$@"
          continue
          ;;
        [mFbBhHraMli])
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
      -h | -H | --head)
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
      -b | -B | --base)
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
        rest=(-- "$@") # kept last, after anything hub adds for gh
        break
        ;;
      # gh's options from here on. Each goes to gh together with the value gh reads
      # from the next word, so that value is never taken for a hub option or an
      # issue URL. hub also notes --dry-run, the -R/--repo it is given and a head
      # given with -H inside a cluster of gh's short options (-wH BRANCH).
      --dry-run | --dry-run=*)
        passthrough+=("$arg")
        case ${arg#--dry-run} in
          '' | =1 | =t | =T | =true | =TRUE | =True) dry_run=1 ;;
          *) dry_run=0 ;;
        esac
        ;;
      -R?* | --repo=*)
        passthrough+=("$arg")
        repo=${arg#-R}
        repo=${repo#=} # gh takes -R=X as X
        repo=${repo#--repo=}
        ;;
      -?*)
        passthrough+=("$arg")
        # The option in it that takes a value: the word itself (--title), or the first
        # such letter of a cluster of short options (-wt), whose value is the rest of
        # the word (-wtTitle) if there is one. Otherwise gh reads the next word.
        opt=$arg value=''
        if [[ $arg != --* ]]; then
          opt=''
          if i=$(_hub_pull_request_gh_letter "$arg"); then
            opt=-${arg:i:1} value=${arg:i+1}
            [[ $value != =?* ]] || value=${value:1} # gh takes -wR=X as X
          fi
        fi
        if [[ -z $value ]] && (($#)) && _hub_pull_request_gh_value "$opt"; then
          value=$1
          passthrough+=("$1")
          shift
        fi
        case $opt in
          -R | --repo) repo=$value ;;
          -H) gh_head=1 ;;
        esac
        ;;
      *)
        if [[ -z $issue ]] && _hub_pull_request_issue_url "$arg"; then
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
  # here: the current project, base_repo: the one -b OWNER[/REPO]:BRANCH names, target:
  # the issue's (-i); all as HOST/OWNER/REPO, and empty until known.
  local branch here='' base_repo='' target='' base_target remote project number owner
  branch=$(hub::current_branch) || branch=''

  if [[ $base == *:* ]]; then
    [[ $base =~ ^([^:/]+)(/[^:/]+)?:(.+)$ ]] \
      || hub::die "Aborted: not a base: $base (use BRANCH, OWNER:BRANCH or OWNER/REPO:BRANCH)"
    base_repo=${BASH_REMATCH[1]}${BASH_REMATCH[2]} base=${BASH_REMATCH[3]}
    [[ -z $repo ]] || hub::die "Aborted: -b OWNER:BRANCH and -R/--repo both name the base repository; use one."
    here=$(_hub_pull_request_full_name hub::main_project) || exit
    [[ $base_repo == */* ]] || base_repo+=/${here##*/}
    base_repo=${here%%/*}/$base_repo
  fi

  if [[ -n $issue ]]; then
    if ((${#messages[@]} || edit || no_edit)) || [[ -n $file ]]; then
      hub::die "Aborted: -i uses the issue's title and body; drop -m, -F, -e and --no-edit."
    fi
    if ((${#reviewers[@]} || ${#assignees[@]} || ${#labels[@]})) || [[ -n $milestone ]]; then
      hub::die "Aborted: -i cannot add reviewers, assignees, labels or a milestone; add them afterwards with gh pr edit."
    fi
    if ((${#passthrough[@]} || ${#rest[@]})); then
      hub::die "Aborted: -i does not take gh pr create options: $(hub::quote "${passthrough[@]}" "${rest[@]}")"
    fi
    if _hub_pull_request_issue_url "$issue"; then
      number=$HUB_URL_NUMBER target=$HUB_URL_HOST/$HUB_URL_OWNER/$HUB_URL_REPO
      if [[ -n $base_repo && ${base_repo,,} != "${target,,}" ]]; then
        hub::die "Aborted: -b names ${base_repo#*/}, but the issue is in ${target#*/}."
      fi
    else
      number=${issue#\#}
      [[ $number =~ ^[0-9]+$ ]] || hub::die "Aborted: not an issue number or issue URL: $issue"
      # hub's current repository, not the one gh would pick (gh repo set-default, GH_HOST)
      [[ -n $here ]] || here=$(_hub_pull_request_full_name hub::main_project) || exit
      target=${base_repo:-$here}
    fi
  fi
  base_target=${target:-${base_repo:-$repo}} # the base repository, if not the current one

  if ((push)); then
    if [[ -z $head ]]; then
      [[ -n $branch ]] || hub::die "Aborted: not currently on any branch."
      push_cmd=(push --set-upstream "$(_hub_pull_request_push_remote "$branch")" HEAD)
    elif [[ $head == *:* ]]; then
      # OWNER:BRANCH: to BRANCH on the remote for OWNER's repository of this name,
      # provided that is the only repository the remote pushes to.
      [[ $head =~ ^[^:/]+:.+$ ]] || hub::die "Aborted: -p cannot push to $head; give the head as BRANCH or OWNER:BRANCH."
      [[ -n $here ]] || here=$(_hub_pull_request_full_name hub::main_project) || exit
      project=${here%%/*}/${head%%:*}/${here##*/}
      remote=$(_hub_pull_request_remote_for "$project" "$(_hub_pull_request_push_remote "$branch")") \
        || hub::die "Aborted: no remote for ${project#*/} to push ${head#*:} to; add one with git remote add, or push it yourself and drop -p."
      _hub_pull_request_check_push "$remote" "$project"
      push_cmd=(push "$remote" "HEAD:refs/heads/${head#*:}")
    else
      # BRANCH: to BRANCH on the push remote. gh looks for a bare BRANCH in the base
      # repository, so the head names the remote's owner when the remote is a fork.
      remote=$(_hub_pull_request_push_remote "$branch")
      push_cmd=(push "$remote" "HEAD:refs/heads/$head")
      head=$(_hub_pull_request_head "$remote" "$head" "$base_target")
    fi
  fi

  if [[ -n $issue ]]; then
    if [[ -z $head ]]; then
      [[ -n $branch ]] || hub::die "Aborted: not currently on any branch."
      owner=$(hub::remote_project "$(_hub_pull_request_push_remote "$branch")") \
        || owner=$(hub::main_project) || exit
      head=${owner%%/*}:$branch
    fi
    [[ -n $base ]] || base=$(_hub_pull_request_default_branch "$target") || exit
    cmd=(api --hostname "${target%%/*}" "repos/${target#*/}/pulls" -F "issue=$number" -F "head=$head" -f "base=$base")
    ((draft)) && cmd+=(-F draft=true)
    ((no_maint)) && cmd+=(-F maintainer_can_modify=false)
    cmd+=(--jq .html_url)
  else
    local text='' have_text=0
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
    if ((force && ! gh_head)) && [[ -z $head ]]; then
      [[ -n $branch ]] || hub::die "Aborted: not currently on any branch."
      head=$(_hub_pull_request_head "$(_hub_pull_request_push_remote "$branch")" "$branch" "$base_target")
    fi
    ((edit)) && cmd+=(--editor)
    ((no_edit)) && cmd+=(--fill-first)
    [[ -n $base_repo ]] && cmd+=(--repo "$base_repo")
    [[ -n $base ]] && cmd+=(--base "$base")
    [[ -n $head ]] && cmd+=(--head "$head")
    ((draft)) && cmd+=(--draft)
    for value in "${reviewers[@]}"; do cmd+=(--reviewer "$value"); done
    for value in "${assignees[@]}"; do cmd+=(--assignee "$value"); done
    [[ -n $milestone ]] && cmd+=(--milestone "$milestone")
    for value in "${labels[@]}"; do cmd+=(--label "$value"); done
    ((no_maint)) && cmd+=(--no-maintainer-edit)
    cmd+=("${passthrough[@]}")
    # gh's dry run may still push the branch or fork the repository while it works
    # out the head, but not when it is given one: name it, as -f does.
    if ((dry_run && ! gh_head)) && [[ -z $head ]]; then
      [[ -n $branch ]] || hub::die "Aborted: not currently on any branch; with --dry-run, name the head with -h [OWNER:]BRANCH."
      cmd+=(--head "$(_hub_pull_request_head "$(_hub_pull_request_push_remote "$branch")" "$branch" "$base_target")")
    fi
    cmd+=("${rest[@]}")
  fi

  if ((${#push_cmd[@]})); then
    if ((dry_run)); then
      HUB_NOOP=1 hub::git "${push_cmd[@]}" # gh --dry-run creates nothing, so push nothing either
    else
      hub::git "${push_cmd[@]}" || exit
    fi
  fi
  ((dry_run)) && browse=0 copy=0 # there is no new pull request to open or copy
  _hub_pull_request_create "$browse" "$copy" "${cmd[@]}"
}

# _hub_pull_request_need OPTION ARGS-LEFT : die unless OPTION still has a value after it.
_hub_pull_request_need() { (($2)) || hub::die "Aborted: $1 needs a value."; }

# _hub_pull_request_gh_value OPTION : true if OPTION is one of gh pr create's options that
# take a value, as gh spells them; this is the one list of them. Where hub has an option
# spelled the same (-b, -m, -p, --base, ...), hub's is matched first, so gh's meaning only
# applies inside a cluster of gh's short options, such as -wb BODY.
_hub_pull_request_gh_value() {
  case $1 in
    -a | --assignee | --attach | -B | --base | -b | --body | -F | --body-file | -H | --head | \
      -l | --label | -m | --milestone | -p | --project | -R | --repo | -r | --reviewer | \
      --recover | -T | --template | -t | --title)
      return 0
      ;;
  esac
  return 1
}

# _hub_pull_request_gh_letter WORD : for a cluster of gh's short options, print the index
# in WORD of its first letter that takes a value (the rest of WORD is that value, if there
# is any; gh reads the next word otherwise). Fails if no letter of WORD takes a value.
_hub_pull_request_gh_letter() {
  local i
  for ((i = 1; i < ${#1}; i++)); do
    if _hub_pull_request_gh_value "-${1:i:1}"; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  return 1
}

# _hub_pull_request_issue_url STR : true if STR is a GitHub issue URL (sets HUB_URL_*).
_hub_pull_request_issue_url() { hub::parse_github_url "$1" && [[ $HUB_URL_KIND == issues ]]; }

# _hub_pull_request_full_name hub::main_project | hub::remote_project REMOTE : print
# that project as HOST/OWNER/REPO.
_hub_pull_request_full_name() {
  local out
  out=$("$@" && printf '%s\n' "$HUB_PROJECT_HOST") || return 1
  printf '%s/%s\n' "${out#*$'\n'}" "${out%%$'\n'*}"
}

# _hub_pull_request_url_project URL : print HOST/OWNER/REPO for a GitHub remote URL, read
# the way hub::remote_project reads a remote's (an ssh_config alias stands for its
# HostName). Fails if URL is not a GitHub repository.
_hub_pull_request_url_project() {
  local host
  hub::parse_remote_url "$1" || return 1
  host=$HUB_URL_HOST
  if ! hub::is_known_host "$host"; then
    host=$(hub::ssh_hostname "$host")
    if [[ -z $host ]] || ! hub::is_known_host "$host"; then return 1; fi
  fi
  printf '%s/%s/%s\n' "$host" "$HUB_URL_OWNER" "$HUB_URL_REPO"
}

# _hub_pull_request_check_push REMOTE HOST/OWNER/REPO : die unless every URL that `git push
# REMOTE` sends to (git remote get-url --push --all, which applies insteadOf and
# pushInsteadOf) is that repository; a remote's push URLs need not be its fetch URL.
_hub_pull_request_check_push() {
  local url name
  while IFS= read -r url; do
    name=$(_hub_pull_request_url_project "$url") || name=''
    [[ ${name,,} == "${2,,}" ]] && continue
    [[ $url =~ ^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@(.*)$ ]] && url=${BASH_REMATCH[1]}${BASH_REMATCH[2]} # no credentials
    hub::die "Aborted: remote $1 is for $2, but it pushes to $url; fix its push URL (git remote set-url --push), or push it yourself and drop -p."
  done < <(hub::git_query remote get-url --push --all "$1")
}

# _hub_pull_request_push_remote [BRANCH] : the remote `git push` sends BRANCH to:
# branch.BRANCH.pushRemote, remote.pushDefault, branch.BRANCH.remote, else origin.
_hub_pull_request_push_remote() {
  local key remote
  for key in ${1:+"branch.$1.pushRemote"} remote.pushDefault ${1:+"branch.$1.remote"}; do
    remote=$(hub::git_query config --get "$key") || continue
    if [[ -n $remote && $remote != . ]]; then
      printf '%s\n' "$remote"
      return 0
    fi
  done
  printf 'origin\n'
}

# _hub_pull_request_remote_for HOST/OWNER/REPO [REMOTE] : the local remote for that
# project, by its fetch URL: REMOTE if it is one, else the first that is.
_hub_pull_request_remote_for() {
  local want=${1,,} r name
  local -a remotes
  mapfile -t remotes < <(hub::git_query remote)
  for r in ${2:+"$2"} "${remotes[@]}"; do
    name=$(_hub_pull_request_full_name hub::remote_project "$r") || continue
    if [[ ${name,,} == "$want" ]]; then
      printf '%s\n' "$r"
      return 0
    fi
  done
  return 1
}

# _hub_pull_request_head REMOTE BRANCH [BASE-REPO] : BRANCH, or OWNER:BRANCH when REMOTE
# belongs to someone other than the owner of the base repository (a fork). BASE-REPO is
# [HOST/]OWNER/REPO or a URL; without it, the base is the current project.
_hub_pull_request_head() {
  local fork base=${3:-}
  fork=$(hub::remote_project "$1") || fork=''
  [[ -n $base ]] || base=$(hub::main_project 2>/dev/null) || base=''
  base=${base#*://}
  [[ $base == */*/* ]] && base=${base#*/}
  fork=${fork%%/*} base=${base%%/*}
  if [[ -n $fork && ${fork,,} != "${base,,}" ]]; then
    printf '%s:%s\n' "$fork" "$2"
  else
    printf '%s\n' "$2"
  fi
}

# _hub_pull_request_default_branch HOST/OWNER/REPO : the default branch of that repository.
# The main remote's comes from hub::default_branch; another repository's from GitHub, and
# hub dies if it can't be found rather than guess.
_hub_pull_request_default_branch() {
  local remote here='' name
  if remote=$(hub::main_remote); then
    here=$(_hub_pull_request_full_name hub::remote_project "$remote") || here=''
  fi
  if [[ -n $here && ${1,,} == "${here,,}" ]]; then
    hub::default_branch "$remote"
    return
  fi
  name=$(hub::gh_query repo view "$1" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) || name=''
  [[ -n $name ]] || hub::die "Aborted: could not look up the default branch of ${1#*/}; give the base with -b BRANCH."
  printf '%s\n' "$name"
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
