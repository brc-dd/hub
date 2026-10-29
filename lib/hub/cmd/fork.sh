# shellcheck shell=bash
# Summary: Fork the current repository on GitHub and add the fork as a remote.
# Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [gh repo fork options]
#
# Forks the current repository with `gh repo fork`, adds the fork as a remote
# named after your GitHub login (or after ORG with --org), and fetches it.
# Existing remotes, origin included, are left as they are, so afterwards
# `git push <login> BRANCH` pushes to your fork.
#
# Plain `gh repo fork --remote` does it the other way around: the fork becomes
# "origin" and the existing origin is renamed to "upstream".
#
# Options:
#   --no-remote         Fork without adding a remote.
#   --remote-name NAME  Name the new remote NAME.
#   --org ORG           Fork into the organization ORG.
# Other options, such as --fork-name NAME or --default-branch-only, are passed
# to gh repo fork.
#
#   $ hub fork
#   > gh repo fork --remote --remote-name mislav
#   > git fetch mislav
#   $ hub fork --org myorg
#   > gh repo fork --remote --remote-name myorg --org myorg
#   > git fetch myorg

hub_cmd_fork() {
  local no_remote=0 remote='' org='' proj
  local -a extra=()
  while (($#)); do
    case $1 in
      --no-remote | --remote=false) no_remote=1 ;;
      --remote-name)
        (($# >= 2)) || hub::die "hub fork: $1 needs a NAME"
        remote=$2
        shift
        ;;
      --remote-name=*) remote=${1#*=} ;;
      --org)
        (($# >= 2)) || hub::die "hub fork: $1 needs an ORG"
        org=$2
        shift
        ;;
      --org=*) org=${1#*=} ;;
      -h | --help) hub::usage ;;
      *) extra+=("$1") ;;
    esac
    shift
  done
  hub::require_repo
  [[ -n $org ]] && extra=(--org "$org" "${extra[@]}")

  if ((no_remote)); then
    hub::exec_gh repo fork --remote=false "${extra[@]}"
  fi
  if [[ -z $remote ]]; then
    if [[ -n $org ]]; then
      remote=$org
    else
      # Your login on the host of the repository being forked.
      proj=$(hub::main_project && printf '%s\n' "$HUB_PROJECT_HOST") || exit 1
      remote=$(hub::current_user "${proj##*$'\n'}") || exit 1
    fi
  fi
  hub::gh repo fork --remote --remote-name "$remote" "${extra[@]}" || exit
  # gh adds the remote but does not fetch it.
  hub::git fetch "$remote"
}
