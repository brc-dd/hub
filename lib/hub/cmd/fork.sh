# shellcheck shell=bash
# Summary: Fork the project on GitHub and add the fork as a remote.
# Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME]
#                 [--default-branch-only] [ORG]
#
# hub's own command: these are all of its options. Forks the current project (GH_REPO, else the
# first GitHub remote among upstream, github, origin and the rest) under your account, or under
# the organization ORG, with gh repo fork, and adds the fork gh names as the remote NAME:
# --remote-name, else ORG, else your login. The remote name must be valid and free before gh
# runs. A fork that already exists is reused. The remote's URL follows gh's git_protocol for the
# host. Nothing is fetched: run git fetch NAME once GitHub has made the fork.
#
# --no-remote only forks; it works outside a repository when GH_REPO names the project.
#
# Options:
#   --no-remote             Fork without adding a remote.
#   --remote-name NAME      Name the new remote NAME.
#   --org ORG               Fork into the organization ORG; an ORG operand means the same.
#   --fork-name NAME        Name the fork NAME on GitHub.
#   --default-branch-only   Copy only the default branch into the fork.
#
#   $ hub fork
#   > gh repo fork github.com/dotcom/dotfiles --clone=false
#   > git remote add -- mislav https://github.com/mislav/dotfiles.git
#   $ hub fork --no-remote acme
#   > gh repo fork github.com/dotcom/dotfiles --clone=false --org=acme

hub_cmd_fork() {
  local no_remote=0 branch_only=0 remote='' org='' fork_name='' project host owner repo out fork
  local -a opts=() operands=()
  hub::normalize_opts '' '--remote-name --org --fork-name' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -h | --help) hub::usage ;;
      --no-remote) no_remote=1 ;;
      --default-branch-only) branch_only=1 ;;
      --remote-name | --org | --fork-name)
        [[ -n ${2-} ]] || hub::usage_error "$1 needs a value"
        case $1 in
          --remote-name) remote=$2 ;;
          --org) org=$2 ;;
          --fork-name) fork_name=$2 ;;
        esac
        shift
        ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $1" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} <= 1)) || hub::usage_error "unexpected argument: ${operands[1]}"
  if ((${#operands[@]})); then
    [[ -n ${operands[0]} ]] || hub::usage_error 'empty organization'
    [[ -z $org || ${org,,} == "${operands[0],,}" ]] \
      || hub::usage_error "two organizations: --org $org and ${operands[0]} (name one)"
    org=${org:-${operands[0]}}
  fi
  ((! no_remote)) || [[ -z $remote ]] \
    || hub::usage_error '--no-remote adds no remote to name (drop --remote-name)'
  [[ -z $org ]] || opts+=("--org=$org")
  [[ -z $fork_name ]] || opts+=("--fork-name=$fork_name")
  ((! branch_only)) || opts+=(--default-branch-only)

  if ((! no_remote)) || [[ -z ${GH_REPO-} ]]; then hub::require_repo; fi
  project=$(hub::project) || exit 1
  read -r host owner repo <<<"$project"
  ((! no_remote)) || hub::exec_gh repo fork "$host/$owner/$repo" --clone=false "${opts[@]}"
  [[ -n $remote ]] || remote=${org:-$(hub::login "$host")} || exit 1
  hub::require_new_remote "$remote"

  # gh ignores GH_REPO here and refuses --remote with a repository argument, so hub adds the
  # remote itself, for the fork whose web URL gh prints (an existing fork keeps its own name).
  out=$(hub::gh repo fork "$host/$owner/$repo" --clone=false "${opts[@]}") || exit
  if [[ ${HUB_NOOP-} == 1 ]]; then
    printf '%s\n' "$out"
    out=https://$host/${org:-$(hub::login "$host")}/${fork_name:-$repo}
  fi
  fork=${out##*$'\n'}
  fork=${fork#*://*/}
  if [[ $fork != */* ]] || ! hub::is_shorthand "$fork"; then
    hub::die "gh did not print the fork's URL: $out (add the remote with git remote add)"
  fi
  hub::git remote add -- "$remote" "$(hub::clone_url "$host" "${fork%%/*}" "${fork#*/}")"
}
