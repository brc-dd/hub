# shellcheck shell=bash
# Summary: Fork the current repository on GitHub and add the fork as a remote.
# Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME] [--default-branch-only]
#
# Forks the current project (GH_REPO, else the upstream, github or origin
# remote) on its host through the GitHub API, with
# `gh api -X POST repos/OWNER/REPO/forks`, so that the repository hub works with
# is the one forked, whatever gh's default repository is. GitHub answers with
# the fork whether it creates it or you (or ORG) already have it, and under its
# real name, which need not be the one asked for: an existing fork keeps its
# name. hub adds that fork as a remote named after your login on that host (or
# after ORG with --org) and fetches it. Existing remotes, origin included, are
# left as they are, so afterwards `git push <login> BRANCH` pushes to your fork.
#
# A remote of that name that cannot be the fork (it is not GitHub's, or it is
# another host's or account's) stops hub before anything is forked. Once GitHub
# has named the fork, a remote of that name that points at it is kept as it is
# (and fetched), and one that points at another repository stops hub before the
# remote is touched. The new remote's URL uses SSH or HTTPS as `hub clone` does.
# Under --noop GitHub is not asked for the fork, so hub shows it as ORG's or
# yours, named NAME or after the repository.
#
# Plain `gh repo fork --remote` does it the other way around: the fork becomes
# "origin" and the existing origin is renamed to "upstream".
#
# Options:
#   --no-remote            Fork without adding a remote; print the fork's OWNER/REPO.
#   --remote-name NAME     Name the new remote NAME.
#   --org ORG              Fork into the organization ORG.
#   --fork-name NAME       Name a new fork NAME instead of after the repository.
#   --default-branch-only  Fork only the default branch.
# hub fork takes no repository argument and none of gh repo fork's other
# options, and does not clone; for that, use gh repo fork OWNER/REPO --clone.
#
#   $ hub fork
#   > gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name
#   > git remote add mislav https://github.com/mislav/dotfiles.git
#   > git fetch mislav
#   $ hub fork --org myorg
#   > gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks -f organization=myorg --jq .full_name
#   > git remote add myorg https://github.com/myorg/dotfiles.git
#   > git fetch myorg

hub_cmd_fork() {
  local no_remote=0 branch_only=0 remote='' org='' name='' opt val proj host owner want full url current existing=''
  local -a api=()
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
      --default-branch-only | --default-branch-only=true) branch_only=1 ;;
      --default-branch-only=false) branch_only=0 ;;
      --no-remote | --remote=false) no_remote=1 ;;
      --remote | --remote=true) no_remote=0 ;; # gh's spelling of hub's default
      --clone=false) ;;
      --clone | --clone=* | --) # gh repo fork takes git clone flags after --
        hub::die "Aborted: hub fork adds the fork as a remote of this repository and does not clone it; use gh repo fork OWNER/REPO --clone for that."
        ;;
      -h | --help) hub::usage ;;
      -*)
        hub::die "Aborted: hub fork does not take '$1'. It forks through the GitHub API, not gh repo fork, and its options are --no-remote, --remote-name NAME, --org ORG, --fork-name NAME and --default-branch-only."
        ;;
      *) hub::die "Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME] [--default-branch-only]" ;;
    esac
    shift
  done
  # Refuse a fork name GitHub would change (--noop shows the fork by it) and a remote name git rejects.
  if [[ -n $name && ! $name =~ ^[A-Za-z0-9_.-]+$ ]]; then
    hub::die "Aborted: '$name' is not a repository name GitHub keeps as it is; use letters, digits, '-', '_' and '.'."
  fi
  if [[ -n $remote ]] && { [[ $remote == -* ]] || ! hub::git_query check-ref-format "refs/remotes/$remote/HEAD"; }; then
    hub::die "Aborted: '$remote' is not a valid remote name."
  fi
  hub::require_repo

  # Name the repository to fork, host included: gh's default repository and host may be others.
  proj=$(hub::main_project && printf '%s\n' "$HUB_PROJECT_HOST") || exit 1
  host=${proj##*$'\n'} proj=${proj%%$'\n'*}
  # GitHub creates the fork, or finds the one there is, and answers with its OWNER/REPO.
  api=(api --hostname "$host" -X POST "repos/$proj/forks")
  [[ -z $org ]] || api+=(-f "organization=$org")
  [[ -z $name ]] || api+=(-f "name=$name")
  ((branch_only)) && api+=(-F default_branch_only=true)
  api+=(--jq .full_name)
  ((no_remote)) && hub::exec_gh "${api[@]}"

  # The fork is ORG's or yours, and named NAME or after the repository unless GitHub says otherwise.
  if [[ -n $org ]]; then
    owner=$org
  else
    owner=$(hub::current_user "$host") || exit 1
  fi
  want=$owner/${name:-${proj#*/}}
  [[ -n $remote ]] || remote=$owner

  # Before anything is forked: a remote of that name can only be the fork if it is the owner's on this host.
  if current=$(hub::git_query remote get-url "$remote"); then
    if ! hub::remote_project "$remote" >/dev/null \
      || [[ ${HUB_PROJECT_HOST,,}/${HUB_URL_OWNER,,} != "${host,,}/${owner,,}" ]]; then
      hub::die "Aborted: a remote named '$remote' already exists for $current, not for $owner's fork; pick another name with --remote-name NAME."
    fi
    existing=$HUB_URL_OWNER/$HUB_URL_REPO
  fi

  if ((HUB_NOOP)); then
    hub::gh "${api[@]}"
    full=$want
  else
    full=$(hub::gh_query "${api[@]}") || exit
    [[ $full =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
      || hub::die "Aborted: expected the fork's OWNER/REPO from GitHub, got '$full'."
  fi
  [[ ${full,,} != "${proj,,}" ]] \
    || hub::die "Aborted: GitHub gave $proj itself as the fork; a repository cannot be forked into the account that owns it."
  [[ ${full,,} == "${want,,}" ]] || hub::warn "The fork is $full, not $want."

  if [[ -n $existing ]]; then
    [[ ${existing,,} == "${full,,}" ]] \
      || hub::die "Aborted: a remote named '$remote' already exists for $current, not for the fork $full; pick another name with --remote-name NAME."
    hub::warn "Using the existing remote '$remote' for $full."
  else
    url=$(hub::git_url "$full" "$host") || exit 1
    hub::git remote add "$remote" "$url" || exit
  fi
  hub::git fetch "$remote"
}
