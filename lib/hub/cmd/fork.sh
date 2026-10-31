# shellcheck shell=bash
# Summary: Fork the current project on GitHub and add the fork as a remote.
# Usage: hub fork [--no-remote] [--remote-name REMOTE] [--org ORGANIZATION] [--fork-name NAME] [--default-branch-only] [ORGANIZATION]
#
# A hub-owned command: these are all of its options, and anything else is an error. Forks the
# current project (GH_REPO, else the upstream, github or origin remote) under your account, or
# under ORGANIZATION, with gh's compound command `gh repo fork --remote --remote-name REMOTE`,
# run with GH_REPO set to that project so that gh forks exactly it. gh adds the fork as the remote
# REMOTE: your login, or ORGANIZATION, unless --remote-name says otherwise. A fork that already
# exists is reused, and a remote that already points at the fork is kept instead of adding one.
# Nothing is fetched: run `git fetch REMOTE` once GitHub has finished creating the fork.
#
# The remote gets the clone URL hub's protocol gives (git config hub.protocol, else gh's
# git_protocol, else https); gh takes the protocol of the remote that points at the forked
# repository, so when its choice differs, hub sets the URL right after gh is done.
#
# Everything local is checked before gh runs: that this is a repository, that REMOTE is a remote
# name, and that no remote of that name exists yet. --no-remote only forks, with
# `gh repo fork HOST/OWNER/REPO --clone=false`, and works outside a repository when GH_REPO names
# the project.
#
# Options:
#   --no-remote            Fork without adding a remote.
#   --remote-name REMOTE   Name the new remote REMOTE.
#   --org ORGANIZATION     Fork into ORGANIZATION; an ORGANIZATION operand means the same.
#   --fork-name NAME       Ask GitHub to name the fork NAME.
#   --default-branch-only  Fork only the default branch.
#
#   $ hub fork
#   > env GH_REPO=github.com/dotcom/dotfiles gh repo fork --remote --remote-name mislav
#   $ hub fork --no-remote
#   > gh repo fork github.com/dotcom/dotfiles --clone=false

hub_cmd_fork() {
  local usage='Usage: hub fork [--no-remote] [--remote-name REMOTE] [--org ORGANIZATION] [--fork-name NAME] [--default-branch-only] [ORGANIZATION]'
  hub::normalize_opts '' '--remote-name --org --fork-name' "$@"
  set -- "${HUB_ARGS[@]}"
  local arg value no_remote=0 branch_only=0 remote='' org='' fork_name=''
  local -a operands=()
  while (($#)); do
    arg=$1
    shift
    case $arg in
      -h | --help) hub::usage ;;
      --remote-name | --org | --fork-name)
        if (($# == 0)) || [[ -z $1 ]]; then hub::die "Aborted: $arg needs a value."; fi
        value=$1
        shift
        case $arg in
          --remote-name) remote=$value ;;
          --org) org=$value ;;
          --fork-name) fork_name=$value ;;
        esac
        ;;
      --no-remote) no_remote=1 ;;
      --default-branch-only) branch_only=1 ;;
      --)
        operands+=("$@")
        break
        ;;
      -?*) hub::die "hub fork: unknown option: $arg"$'\n'"$usage" ;;
      *) operands+=("$arg") ;;
    esac
  done
  ((${#operands[@]} <= 1)) || hub::die "hub fork: too many arguments"$'\n'"$usage"
  if ((${#operands[@]})); then
    [[ -z $org || $org == "${operands[0]}" ]] || hub::die "Aborted: name the organization once (--org $org and ${operands[0]})."
    org=${operands[0]}
  fi
  [[ -z $org || $org =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || hub::die "Aborted: not an organization name: $org (letters, digits and - only)"
  [[ -z $fork_name || $fork_name =~ ^[A-Za-z0-9_.-]+$ ]] || hub::die "Aborted: not a repository name: $fork_name (letters, digits, -, _ and . only)"
  ((! no_remote)) || [[ -z $remote ]] || hub::die "Aborted: --no-remote and --remote-name cannot be used together."

  hub::main_project >/dev/null
  local proj=$HUB_PROJECT host=$HUB_PROJECT_HOST
  local -a opts=()
  [[ -z $org ]] || opts+=(--org "$org")
  [[ -z $fork_name ]] || opts+=(--fork-name "$fork_name")
  ((branch_only)) && opts+=(--default-branch-only)
  ((no_remote)) && hub::exec_gh repo fork "$host/$proj" --clone=false "${opts[@]}"

  # Local checks before the fork: a repository to add the remote to, and a free, well-formed name.
  hub::git_dir >/dev/null || hub::die "fatal: not a git repository (or any of the parent directories): .git"
  local owner
  if [[ -n $org ]]; then
    owner=$org
  else
    owner=$(hub::current_user "$host") || exit 1
  fi
  [[ -n $remote ]] || remote=$owner
  hub::valid_remote_name "$remote" || hub::die "Aborted: not a remote name: '$remote'"
  ! hub::remote_exists "$remote" || hub::die "Aborted: a remote named '$remote' already exists; pick another name with --remote-name NAME."

  hub::require_gh
  hub::run env "GH_REPO=$host/$proj" gh repo fork --remote --remote-name "$remote" "${opts[@]}" || exit
  _hub_fork_fix_url "$remote" "$host" "$proj" "$owner/${fork_name:-${proj#*/}}"
}

# _hub_fork_fix_url REMOTE HOST OWNER/REPO FORK : give the remote gh added the clone URL hub's
# protocol gives when gh chose another (under --noop, as predicted for FORK: gh takes the protocol
# of the remote that points at OWNER/REPO, else its git_protocol for HOST).
_hub_fork_fix_url() {
  local remote=$1 host=$2 proj=$3 fork=$4 want have='' url r
  want=$(hub::protocol "$host")
  if ((HUB_NOOP)); then
    if r=$(hub::remote_for_project "$proj" "$host") && url=$(hub::git_query remote get-url --push -- "$r") && hub::parse_remote_url "$url"; then
      have=$HUB_URL_SCHEME
    else
      have=$(hub::gh_query config get git_protocol -h "$host" 2>/dev/null) || have=''
    fi
  else
    url=$(hub::git_query remote get-url -- "$remote") || return 0 # gh kept a remote that already pointed at the fork
    hub::parse_remote_url "$url" || return 0
    have=$HUB_URL_SCHEME fork=$HUB_URL_OWNER/$HUB_URL_REPO
  fi
  [[ $have == ssh ]] || have=https
  [[ $want == "$have" ]] && return 0
  hub::git remote set-url "$remote" "$(hub::git_url "$fork" "$host" "$want")"
}
