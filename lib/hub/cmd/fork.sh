# shellcheck shell=bash
# Summary: Fork the project on GitHub and add the fork as a remote.
# Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME]
#                 [--default-branch-only] [ORG]
#
# hub's own command: these are all of its options. Forks the current project (GH_REPO, else the
# first GitHub remote among upstream, github, origin and the rest) under your account, or under
# the organization ORG, with GitHub's fork API through gh api, and adds the fork GitHub answers
# with as the remote NAME: --remote-name, else ORG, else your login. The remote name must be
# valid and free before gh runs. A fork that already exists is reused under its own name, even
# with --fork-name. The remote's URL follows gh's git_protocol for the host. Nothing is fetched:
# run git fetch NAME once GitHub has made the fork.
#
# --no-remote only forks and prints the fork's OWNER/NAME; it works outside a repository when
# GH_REPO names the project.
#
# Options:
#   --no-remote             Fork without adding a remote.
#   --remote-name NAME      Name the new remote NAME.
#   --org ORG               Fork into the organization ORG; an ORG operand means the same.
#   --fork-name NAME        Name the fork NAME on GitHub.
#   --default-branch-only   Copy only the default branch into the fork.
#
#   $ hub fork
#   > gh api --hostname github.com --method POST repos/dotcom/dotfiles/forks --jq .full_name
#   > git remote add -- mislav https://github.com/mislav/dotfiles.git
#   $ hub fork --no-remote acme
#   > gh api --hostname github.com --method POST repos/dotcom/dotfiles/forks \
#   >   -f organization=acme --jq .full_name

hub_cmd_fork() {
  local no_remote=0 branch_only=0 remote='' org='' fork_name='' project host owner repo fork
  local -a opts=() operands=()
  hub::normalize_opts '' '--remote-name --org --fork-name' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      -h | --help) hub::usage ;;
      --no-remote) no_remote=1 ;;
      --default-branch-only) branch_only=1 ;;
      --remote-name | --org | --fork-name)
        (($# > 1)) || hub::usage_error "$1 needs a value"
        case $1 in
          --remote-name) remote=$2 && [[ -n $2 ]] || hub::die "not a remote name: ''" ;;
          --org) org=$2 && [[ -n $2 ]] || hub::usage_error 'empty organization' ;;
          --fork-name) fork_name=$2 && [[ -n $2 ]] || hub::usage_error 'empty fork name' ;;
        esac
        shift
        ;;
      --) shift && operands+=("$@") && break ;;
      -?*) hub::usage_error "unknown option: $(hub::shown "$1")" ;;
      *) operands+=("$1") ;;
    esac
    shift
  done
  ((${#operands[@]} <= 1)) \
    || hub::usage_error "unexpected argument: $(hub::shown "${operands[1]}")"
  if ((${#operands[@]})); then
    [[ -n ${operands[0]} ]] || hub::usage_error 'empty organization'
    [[ -z $org || ${org,,} == "${operands[0],,}" ]] \
      || hub::usage_error "two organizations: --org $(hub::shown "$org") and $(hub::shown \
        "${operands[0]}") (name one)"
    org=${org:-${operands[0]}}
  fi
  ((! no_remote)) || [[ -z $remote ]] \
    || hub::usage_error '--no-remote adds no remote to name (drop --remote-name)'
  [[ -z $org ]] || opts+=(-f "organization=$org")
  [[ -z $fork_name ]] || opts+=(-f "name=$fork_name")
  ((! branch_only)) || opts+=(-F default_branch_only=true)

  hub::require_gh
  if ((! no_remote)) || [[ -z ${GH_REPO-} ]]; then hub::require_repo; fi
  project=$(hub::project) || exit 1
  read -r host owner repo <<<"$project"
  # GitHub answers with the fork, new or existing, so its OWNER/NAME is read, never guessed.
  set -- api --hostname "$host" --method POST "repos/$owner/$repo/forks" "${opts[@]}" \
    --jq .full_name
  ((! no_remote)) || hub::exec_gh "$@"
  [[ -n $remote ]] || remote=${org:-$(hub::login "$host")} || exit 1
  hub::require_new_remote "$remote"

  fork=$(hub::gh "$@") || exit
  if [[ ${HUB_NOOP-} == 1 ]]; then
    # A prediction from the names as given: GitHub may normalize them, so nothing is checked.
    printf '%s\n' "$fork"
    fork=$org
    [[ -n $fork ]] || fork=$(hub::login "$host") || exit 1
    fork+=/${fork_name:-$repo}
  elif [[ $fork != */* ]] || ! hub::is_shorthand "$fork"; then
    hub::die "GitHub did not name the fork: $(hub::shown "$fork")" \
      '(add the remote with git remote add)'
  fi
  hub::git remote add -- "$remote" "$(hub::clone_url "$host" "${fork%%/*}" "${fork#*/}")"
}
