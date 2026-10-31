# shellcheck shell=bash
# Summary: Create a GitHub repository for the current project and add it as a remote.
# Usage: hub create [-p | --public | --internal] [-d DESCRIPTION] [-h HOMEPAGE] [--remote-name REMOTE] [--push] [-o] [-c] [[[HOST/]OWNER/]NAME]
#
# A hub-owned command: these are all of its options, and anything else is an error. Creates the
# repository on GitHub from the current repository with gh's compound command
# `gh repo create HOST/OWNER/NAME --source=TOP --remote=REMOTE`, which also adds it as the remote
# REMOTE (origin unless --remote-name says otherwise). TOP is the top of the work tree (or the
# bare repository), passed to gh as a path, so hub runs where you are. The remote gets the clone
# URL hub's protocol gives (git config hub.protocol, else gh's git_protocol, else https); when gh
# chose another, hub sets it right after gh is done.
#
# The repository is private unless --public or --internal says otherwise. It is named after the
# top directory of the work tree unless NAME is given (a .git suffix is dropped), owned by you
# unless OWNER/NAME names an organization, and created on the default host (GH_HOST, else the host
# gh is logged in to) unless HOST/OWNER/NAME or a repository URL names one.
#
# Everything local is checked before gh runs: that this is a repository whose top directory holds
# its .git directory (gh does not create from a linked work tree, or through --git-dir or GIT_DIR),
# that NAME is a repository name (letters, digits, -, _ and .), that REMOTE is a remote name, and
# that no remote of that name exists yet.
#
# Options:
#   -p, --private           Make the repository private (the default).
#       --public            Make it public.
#       --internal          Make it internal to its organization.
#   -d, --description TEXT  The repository description.
#   -h, --homepage URL      The repository home page.
#       --remote-name NAME  Add the repository as the remote NAME instead of origin.
#       --push              Push the current branch to the new repository too (gh's --push; from
#                           a bare repository, whose every ref gh's --push would mirror, hub
#                           pushes the branch HEAD names itself).
#   -o, --browse            Open the new repository, https://HOST/OWNER/NAME, in the browser.
#   -c, --copy              Copy that URL to the clipboard.
#
# The command fails when gh, the browser or the clipboard tool fails; the repository exists on
# GitHub once gh has printed its URL.
#
#   $ hub create --public -d 'My dotfiles' myorg/dotfiles
#   > gh repo create github.com/myorg/dotfiles --source=/home/me/dotfiles --remote=origin --public --description My\ dotfiles

hub_cmd_create() {
  local usage='Usage: hub create [-p | --public | --internal] [-d DESCRIPTION] [-h HOMEPAGE] [--remote-name REMOTE] [--push] [-o] [-c] [[[HOST/]OWNER/]NAME]'
  hub::normalize_opts dh '--description --homepage --remote-name' "$@"
  set -- "${HUB_ARGS[@]}"
  local arg value visibility=--private remote=origin description='' homepage='' push=0 browse=0 copy=0
  local -a operands=()
  while (($#)); do
    arg=$1
    shift
    case $arg in
      --help) hub::usage ;;
      -p | --private) visibility=--private ;;
      --public | --internal) visibility=$arg ;;
      -d | --description | -h | --homepage | --remote-name)
        if (($# == 0)); then
          [[ $arg == -h ]] && hub::usage # a bare -h asks for the manual
          hub::die "Aborted: $arg needs a value."
        fi
        value=$1
        shift
        case $arg in
          -d | --description) description=$value ;;
          -h | --homepage) homepage=$value ;;
          --remote-name)
            [[ -n $value ]] || hub::die "Aborted: $arg needs a value."
            remote=$value
            ;;
        esac
        ;;
      --push) push=1 ;;
      -o | --browse) browse=1 ;;
      -c | --copy) copy=1 ;;
      --)
        operands+=("$@")
        break
        ;;
      -?*) hub::die "hub create: unknown option: $arg"$'\n'"$usage" ;;
      *) operands+=("$arg") ;;
    esac
  done
  ((${#operands[@]} <= 1)) || hub::die "hub create: too many arguments"$'\n'"$usage"

  # The repository to create from: the top of the work tree, or the bare repository, laid out as
  # gh accepts it (`git rev-parse --git-dir` there must say .git or .).
  local src gitdir
  if ! src=$(hub::toplevel); then
    [[ $(hub::git_query rev-parse --is-bare-repository) == true ]] || hub::require_repo
    src=$(hub::git_query rev-parse --absolute-git-dir)
  fi
  gitdir=$(hub::git_query -C "$src" rev-parse --git-dir)
  [[ $gitdir == .git || $gitdir == . ]] || hub::die "Aborted: gh repo create --source takes a work tree with its .git directory inside it, not a linked work tree (git worktree) or a repository reached through --git-dir or GIT_DIR (the git directory of $src is $gitdir); run hub create from the main work tree."

  # The repository to create: [[HOST/]OWNER/]NAME, else your login and the directory's name. Every
  # local check comes before the login lookup, the first thing that asks gh.
  local name=${operands[0]-} host owner='' repo
  if ((${#operands[@]})) && [[ -z $name ]]; then
    hub::die "Aborted: not a repository name: '' (use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)"
  elif [[ -z $name ]]; then
    read -r host repo < <(hub::project_or_dir)
  elif [[ $name == */* ]]; then
    hub::parse_project "$name" || hub::die "Aborted: not a repository name: $name (use NAME, OWNER/NAME, HOST/OWNER/NAME or a repository URL)"
    host=$HUB_PROJECT_HOST owner=${HUB_PROJECT%%/*} repo=${HUB_PROJECT#*/}
  else
    host=$(hub::host) repo=${name%.git}
  fi
  [[ $repo =~ ^[A-Za-z0-9_.-]+$ && $repo != . && $repo != .. ]] || hub::die "Aborted: not a repository name: $repo (letters, digits, -, _ and . only)"
  [[ -z $owner || $owner =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || hub::die "Aborted: not a GitHub owner: $owner (letters, digits and - only)"
  hub::valid_remote_name "$remote" || hub::die "Aborted: not a remote name: '$remote'"
  ! hub::remote_exists "$remote" || hub::die "Aborted: a remote named '$remote' already exists; pick another name with --remote-name NAME."
  if [[ -z $owner ]]; then owner=$(hub::current_user "$host") || exit 1; fi

  # The URL gh gives the remote follows gh's git_protocol; hub's protocol wins when it is configured.
  local fix_url='' want have
  if [[ -n ${HUB_PROTOCOL:-} ]] || hub::git_query config --get hub.protocol >/dev/null; then
    want=$(hub::protocol "$host")
    have=$(hub::gh_query config get git_protocol -h "$host" 2>/dev/null) || have=''
    [[ $have == ssh ]] || have=https
    [[ $want == "$have" ]] || fix_url=$(hub::git_url "$owner/$repo" "$host" "$want")
  fi

  local -a cmd=(repo create "$host/$owner/$repo" --source="$src" --remote="$remote" "$visibility")
  [[ -z $description ]] || cmd+=(--description "$description")
  [[ -z $homepage ]] || cmd+=(--homepage "$homepage")
  local bare=0
  [[ $gitdir != . ]] || bare=1
  ((push && ! bare)) && cmd+=(--push) # from a bare repository gh's --push mirrors every ref: see below
  hub::gh "${cmd[@]}" || exit
  if [[ -n $fix_url ]]; then hub::git remote set-url "$remote" "$fix_url" || exit; fi
  if ((push && bare)); then hub::git push --set-upstream "$remote" HEAD || exit; fi
  local url=https://$host/$owner/$repo status=0
  if ((copy)); then hub::copy "$url" || status=$?; fi
  if ((browse)); then hub::open_url "$url" || status=$?; fi
  return "$status"
}
