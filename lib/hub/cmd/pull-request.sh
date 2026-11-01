# shellcheck shell=bash
# Summary: Open a pull request for the current branch.
# Usage: hub pull-request [-fpdoc] [-b [OWNER[/REPO]:]BASE] [-h [OWNER:]HEAD] [-m MESSAGE]...
#                         [-F FILE] [-e | --no-edit] [-r REVIEWERS] [-a ASSIGNEES] [-M MILESTONE]
#                         [-l LABELS] [--no-maintainer-edits]
#
# hub's own command: these are all of its options. Runs gh pr create in the project, or in
# OWNER's copy of it with -b OWNER:BASE. Without -h the head is the current branch, under its
# own name, in the repository it pushes to: branch.NAME.pushRemote, remote.pushDefault, an
# upstream of the same name, the only remote, your fork, then origin. It must be pushed there
# already, unless -p pushes it or -f skips the check. Without -b, gh takes the default branch.
#
# The first paragraph of the message is the title, the rest is the body. Without -m, -F, -e or
# --no-edit, gh asks for them, which needs a terminal, as -e does.
#
# Options:
#   -m, --message MESSAGE   A paragraph of the message; repeat it for more.
#   -F, --file FILE         Read the message from FILE (- is standard input).
#   -e, --edit              Write the message in gh's editor (in a terminal), from -m or -F.
#       --no-edit           Take the message from the first commit (gh's --fill-first).
#   -b, --base BASE         The branch to merge into: BRANCH, OWNER:BRANCH or OWNER/REPO:BRANCH.
#   -h, --head HEAD         The branch with the changes, BRANCH or OWNER:BRANCH; not checked.
#   -p, --push              Push the current branch first (git push [-u] REMOTE HEAD:BRANCH).
#   -f, --force             Skip the check that the current branch is pushed.
#   -d, --draft             Open it as a draft.
#   -r, --reviewer LIST     Request reviews from these users or ORG/TEAMs (comma-separated).
#   -a, --assign LIST       Assign these users (comma-separated).
#   -M, --milestone NAME    Add it to this milestone.
#   -l, --labels LIST       Add these labels (comma-separated).
#       --no-maintainer-edits
#                           Do not let maintainers push to the head branch.
#   -o, --browse            Open the pull request in the browser.
#   -c, --copy              Copy the pull request's URL.
#
#   $ hub pull-request -p -m 'Fix the bug'
#   > git push --set-upstream origin HEAD:refs/heads/feature
#   > gh pr create --repo github.com/mislav/dotfiles --head feature --title 'Fix the bug' --body ''
#   $ hub pull-request -b alice:main -F message.txt -r bob
#   > gh pr create --repo github.com/alice/dotfiles --base main --head mislav:feature ...

hub_cmd_pull_request() {
  local push=0 force=0 edit=0 no_edit=0 browse=0 copy=0 draft=0 no_maintainer=0 have_file=0
  local file='' base='' head=''
  local host owner repo project branch remote label text title body url milestone='' rc=0
  local -a messages=() create=() reviewers=() assignees=() labels=() head_project
  hub::normalize_opts bhmFraMl \
    '--base --head --message --file --reviewer --assign --milestone --labels' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -p | --push) push=1 ;;
      -f | --force) force=1 ;;
      -d | --draft) draft=1 ;;
      -o | --browse) browse=1 ;;
      -c | --copy) copy=1 ;;
      -e | --edit) edit=1 ;;
      --no-edit) no_edit=1 ;;
      --no-maintainer-edits) no_maintainer=1 ;;
      --help) hub::usage ;;
      -b | --base | -h | --head | -m | --message | -F | --file | -r | --reviewer | -a | --assign | \
        -M | --milestone | -l | --labels)
        (($# >= 2)) || hub::usage_error "$1 needs a value"
        case $1 in
          -b | --base | -h | --head) [[ -n $2 ]] || hub::usage_error "$1 needs a branch name" ;;&
          -b | --base) base=$2 ;;
          -h | --head) head=$2 ;;
          -m | --message) messages+=("$2") ;;
          -F | --file) file=$2 have_file=1 ;;
          -r | --reviewer) reviewers+=(--reviewer "$2") ;;
          -a | --assign) assignees+=(--assignee "$2") ;;
          -M | --milestone) milestone=$2 ;;
          -l | --labels) labels+=(--label "$2") ;;
        esac
        shift
        ;;
      -i | --issue)
        text='use gh api to attach a pull request to an issue, or link it in the body'
        hub::usage_error "$1 is not supported ($text)"
        ;;
      --) (($# == 1)) || hub::usage_error "unexpected argument: $2" ;;
      -?*) hub::usage_error "unknown option: $1" ;;
      *) hub::usage_error "unexpected argument: $1" ;;
    esac
    shift
  done

  ((${#messages[@]} == 0 || have_file == 0)) || hub::usage_error '-m and -F cannot be combined'
  ((edit == 0 || no_edit == 0)) || hub::usage_error '-e and --no-edit cannot be combined'
  ((no_edit == 0 || ${#messages[@]} + have_file == 0)) \
    || hub::usage_error '--no-edit takes the message from the first commit (drop -m and -F)'
  [[ -z $head || $no_edit == 0 ]] \
    || hub::usage_error '--no-edit cannot be used with -h (give the message with -m or -F)'
  [[ -z $head || $push == 0 ]] \
    || hub::die '-p pushes the current branch; push the head yourself and name it with -h'
  ((! have_file)) || [[ -n $file ]] || hub::usage_error '-F needs a file name'

  if ((have_file)); then
    text=$(cat -- "$file") || hub::die "cannot read the message from $file"
  else
    text=$(printf '%s\n\n' "${messages[@]}")
  fi
  if ((have_file || ${#messages[@]})); then
    text=$(_hub_pull_request_split "$text")
    title=${text%%$'\n'*} body=''
    [[ $text != *$'\n'* ]] || body=${text#*$'\n'}
    [[ -n $title || $edit == 1 ]] || hub::die 'the title is empty (give it with -m or -F)'
    [[ -z $title ]] || create+=(--title "$title" --body "$body")
  fi
  # gh prompts, and opens its editor, only when it can prompt; it refuses -e otherwise.
  if ! [[ -t 0 && -t 1 && -z ${GH_PROMPT_DISABLED+set} ]]; then
    ((! edit)) || hub::die "-e opens gh's editor, which needs a terminal (give the message with" \
      '-m or -F)'
    ((have_file || ${#messages[@]} || no_edit)) \
      || hub::die 'give the title and body with -m or -F (gh prompts for them only in a terminal)'
  fi
  ((! edit)) || create+=(--editor)
  ((! no_edit)) || create+=(--fill-first)
  ((! draft)) || create+=(--draft)
  create+=("${reviewers[@]}" "${assignees[@]}" ${milestone:+--milestone "$milestone"})
  create+=("${labels[@]}")
  ((! no_maintainer)) || create+=(--no-maintainer-edit)

  if [[ -z $head ]]; then
    hub::require_repo
  fi
  project=$(hub::project) || exit 1
  read -r host owner repo <<<"$project"
  if [[ $base == *:* ]]; then
    text=$base owner=${base%%:*} base=${base#*:}
    [[ $owner != */* ]] || repo=${owner#*/} owner=${owner%%/*}
    hub::is_shorthand "$owner/$repo" && [[ -n $base ]] \
      || hub::usage_error "not a base: $text (use -b [OWNER[/REPO]:]BRANCH)"
  fi

  if [[ -n $head ]]; then
    label=$head
  else
    branch=$(hub::current_branch) \
      || hub::die 'not on a branch (name the head with -h [OWNER:]BRANCH)'
    remote=$(hub::push_remote "$branch") \
      || hub::die "cannot tell where $branch pushes (git push -u REMOTE $branch first, or name" \
        'the head with -h)'
    read -r -a head_project < <(hub::remote_project "$remote" push) \
      || hub::die "$remote does not push to a GitHub repository (name the head with -h)"
    [[ ${head_project[0]} == "$host" ]] \
      || hub::die "$remote pushes to ${head_project[0]}, not to $host (name the head with -h)"
    label=$branch
    [[ "${head_project[1],,}/${head_project[2],,}" == "${owner,,}/${repo,,}" ]] \
      || label=${head_project[1]}:$branch
    if ((! push && ! force)); then
      _hub_pull_request_check_pushed "$branch" "$remote"
    fi
  fi

  hub::require_gh
  if ((push)); then
    _hub_pull_request_push "$branch" "$remote" || exit
  fi
  hub::gh pr create --repo "$host/$owner/$repo" ${base:+--base "$base"} --head "$label" \
    "${create[@]}" || exit
  ((browse || copy)) || return 0
  if [[ ${HUB_NOOP-} == 1 ]]; then
    url='URL'
    hub::quote gh pr view "$label" --repo "$host/$owner/$repo" --json url --jq .url
  else
    url=$(gh pr view "$label" --repo "$host/$owner/$repo" --json url --jq .url)
    [[ $url == http* ]] \
      || hub::die "the pull request was created, but its URL could not be looked up (gh pr view" \
        "$label --repo $host/$owner/$repo)"
  fi
  # Subshells, so that a missing clipboard tool or browser does not cancel the other action.
  if ((copy)); then (hub::copy "$url") || rc=$?; fi
  if ((browse)); then (hub::open_url "$url") || rc=$?; fi
  return "$rc"
}

# _hub_pull_request_split TEXT : the title on the first line, then the body.
_hub_pull_request_split() {
  local line title='' in_title=1 first=-1 last=-1 i
  local -a body=()
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    if ((in_title)); then
      if [[ $line == *[![:space:]]* ]]; then
        line=${line#"${line%%[![:space:]]*}"}
        title+=${title:+ }${line%"${line##*[![:space:]]}"}
      elif [[ -n $title ]]; then
        in_title=0
      fi
      continue
    fi
    body+=("$line")
    if [[ $line == *[![:space:]]* ]]; then
      ((first >= 0)) || first=$((${#body[@]} - 1))
      last=$((${#body[@]} - 1))
    fi
  done <<<"$1"
  printf '%s\n' "$title"
  ((first < 0)) || for ((i = first; i <= last; i++)); do printf '%s\n' "${body[i]}"; done
}

# _hub_pull_request_check_pushed BRANCH REMOTE : die unless BRANCH is pushed to REMOTE.
_hub_pull_request_check_pushed() {
  local count rc=0
  count=$(hub::pushed "$1" "$2") || rc=$?
  case $rc in
    0) ;;
    1) hub::die "$1 is not pushed to $2 (use -p to push it, or -f to skip the check)" ;;
    *)
      if ((count == 1)); then
        hub::die "1 commit of $1 is not pushed to $2/$1 (use -p to push it, or -f to skip" \
          'the check)'
      fi
      hub::die "$count commits of $1 are not pushed to $2/$1 (use -p to push them, or -f to skip" \
        'the check)'
      ;;
  esac
}

# _hub_pull_request_push BRANCH REMOTE : push HEAD as BRANCH to REMOTE, -u unless it is tracked.
_hub_pull_request_push() {
  local up_remote up_ref
  read -r up_remote up_ref < <(git for-each-ref \
    --format='%(upstream:remotename) %(upstream:remoteref)' "refs/heads/$1")
  # A local upstream (remote .) is a start point; one on another remote is a triangular setup.
  [[ $up_remote != . ]] || up_remote=''
  if [[ -z $up_remote || ($up_remote == "$2" && $up_ref != "refs/heads/$1") ]]; then
    hub::git push --set-upstream "$2" "HEAD:refs/heads/$1"
  else
    hub::git push "$2" "HEAD:refs/heads/$1"
  fi
}
