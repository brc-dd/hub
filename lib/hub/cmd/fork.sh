# shellcheck shell=bash
# Summary: Fork the current repository on GitHub and add the fork as a remote.
# Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME] [gh repo fork options]
#
# Forks the current project (GH_REPO, else the upstream, github or origin
# remote) with `gh repo fork HOST/OWNER/REPO --clone=false`, so that gh forks
# the repository hub works with, on its host, rather than one it picks itself.
# Then hub adds the fork as a remote named after your login on that host (or
# after ORG with --org) and fetches it. Existing remotes, origin included, are
# left as they are, so afterwards `git push <login> BRANCH` pushes to your fork.
#
# hub checks the remote name before it forks: a remote of that name that
# already points at the fork is kept as it is (and fetched); one that points
# anywhere else stops hub before anything is created. The new remote's URL uses
# SSH or HTTPS as `hub clone` does.
#
# Plain `gh repo fork --remote` does it the other way around: the fork becomes
# "origin" and the existing origin is renamed to "upstream".
#
# Options:
#   --no-remote         Fork without adding a remote.
#   --remote-name NAME  Name the new remote NAME.
#   --org ORG           Fork into the organization ORG.
#   --fork-name NAME    Name the fork NAME instead of after the repository.
# Other options, such as --default-branch-only, are passed to gh repo fork.
# hub fork takes no repository argument and does not clone; gh repo fork
# OWNER/REPO --clone does that.
#
#   $ hub fork
#   > gh repo fork github.com/dotcom/dotfiles --clone=false
#   > git remote add mislav https://github.com/mislav/dotfiles.git
#   > git fetch mislav
#   $ hub fork --org myorg
#   > gh repo fork github.com/dotcom/dotfiles --clone=false --org myorg
#   > git remote add myorg https://github.com/myorg/dotfiles.git
#   > git fetch myorg

hub_cmd_fork() {
  local no_remote=0 remote='' org='' name='' opt val proj host owner url current reuse=0
  local -a extra=() fork=()
  while (($#)); do
    opt=$1 val=''
    case $1 in
      --remote-name=* | --org=* | --fork-name=*) opt=${1%%=*} val=${1#*=} ;;
      --remote-name | --org | --fork-name)
        (($# >= 2)) || hub::die "hub fork: $1 needs a value"
        val=$2
        shift
        ;;
    esac
    case $opt in
      --remote-name | --org | --fork-name) [[ -n $val ]] || hub::die "hub fork: $opt needs a value" ;;&
      --remote-name) remote=$val ;;
      --org) org=$val ;;
      --fork-name) name=$val ;;
      --no-remote | --remote=false) no_remote=1 ;;
      --remote | --remote=true) no_remote=0 ;; # gh's spelling of hub's default
      --clone=false) ;;
      --clone | --clone=*)
        hub::die "Aborted: hub fork adds the fork as a remote of this repository and does not clone it; use gh repo fork OWNER/REPO --clone for that."
        ;;
      -h | --help) hub::usage ;;
      --)
        extra+=("$@")
        break
        ;;
      -*) extra+=("$1") ;;
      *) hub::die "Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME] [gh repo fork options]" ;;
    esac
    shift
  done
  # hub works out the remote's URL from these names, so refuse the ones gh or git would change or reject.
  if [[ -n $name && ! $name =~ ^[A-Za-z0-9_.-]+$ ]]; then
    hub::die "Aborted: '$name' is not a repository name GitHub keeps as it is; use letters, digits, '-', '_' and '.'."
  fi
  if [[ -n $remote ]] && { [[ $remote == -* ]] || ! hub::git_query check-ref-format "refs/remotes/$remote/HEAD"; }; then
    hub::die "Aborted: '$remote' is not a valid remote name."
  fi
  hub::require_repo

  # Name the repository to fork, host included: left to itself, gh picks the base repository its
  # own way (gh repo set-default, then its own order of remotes) and on its default host.
  proj=$(hub::main_project && printf '%s\n' "$HUB_PROJECT_HOST") || exit 1
  host=${proj##*$'\n'} proj=${proj%%$'\n'*}
  fork=(repo fork "$host/$proj" --clone=false)
  [[ -z $org ]] || fork+=(--org "$org")
  [[ -z $name ]] || fork+=(--fork-name "$name")
  fork+=("${extra[@]}")
  ((no_remote)) && hub::exec_gh "${fork[@]}"

  # The fork is ORG's or yours, and named NAME or after the repository.
  if [[ -n $org ]]; then
    owner=$org
  else
    owner=$(hub::current_user "$host") || exit 1
  fi
  [[ -n $name ]] || name=${proj#*/}
  [[ -n $remote ]] || remote=$owner
  url=$(hub::git_url "$owner/$name" "$host") || exit 1

  # Settle the remote before anything is created on GitHub.
  if current=$(hub::git_query remote get-url "$remote"); then
    if ! hub::remote_project "$remote" >/dev/null \
      || [[ ${HUB_PROJECT_HOST,,}/${HUB_URL_OWNER,,}/${HUB_URL_REPO,,} != "${host,,}/${owner,,}/${name,,}" ]]; then
      hub::die "Aborted: a remote named '$remote' already exists for $current, not for the fork $owner/$name; pick another name with --remote-name NAME."
    fi
    reuse=1
  fi

  hub::gh "${fork[@]}" || exit
  if ((reuse)); then
    hub::warn "Using the existing remote '$remote' for $owner/$name."
  else
    hub::git remote add "$remote" "$url" || exit
  fi
  hub::git fetch "$remote"
}
