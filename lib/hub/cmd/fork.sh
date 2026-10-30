# shellcheck shell=bash
# Summary: Fork the current repository on GitHub and add the fork as a remote.
# Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME] [--default-branch-only]
#
# Forks the current project (GH_REPO, else the upstream, github or origin remote) on its host
# with `gh api -X POST repos/OWNER/REPO/forks`, adds the fork GitHub returns as a remote named
# after your login (or ORG), and fetches it, fetching again for a while if GitHub is still
# creating it. An existing remote of that name is kept if it points at the fork; otherwise hub
# stops, before forking when it can tell. Other remotes, origin included, are left alone.
#
# Options:
#   --no-remote            Fork without adding a remote; print the fork's OWNER/REPO.
#   --remote-name NAME     Name the new remote NAME.
#   --org ORG              Fork into the organization ORG.
#   --fork-name NAME       Name a new fork NAME instead of after the repository.
#   --default-branch-only  Fork only the default branch.
#
#   $ hub fork
#   > gh api --hostname github.com -X POST repos/dotcom/dotfiles/forks --jq .full_name
#   > git remote add mislav https://github.com/mislav/dotfiles.git
#   > git fetch mislav

hub_cmd_fork() {
  local no_remote=0 branch_only=0 remote='' org='' name='' opt val proj host owner want full url current existing=''
  while (($#)); do
    opt=$1 val=''
    case $1 in
      --remote-name=* | --org=* | --fork-name=*) opt=${1%%=*} val=${1#*=} ;;
      --remote-name | --org | --fork-name)
        val=${2-}
        shift
        ;;
    esac
    case $opt in
      --remote-name | --org | --fork-name) [[ -n $val ]] || hub::die "hub fork: $opt needs a value" ;;&
      --remote-name) remote=$val ;;
      --org) org=$val ;;
      --fork-name) name=$val ;;
      --default-branch-only) branch_only=1 ;;
      --no-remote) no_remote=1 ;;
      -h | --help) hub::usage ;;
      -*) hub::die "hub fork: unknown option: $1" ;;
      *) hub::die "Usage: hub fork [--no-remote] [--remote-name NAME] [--org ORG] [--fork-name NAME] [--default-branch-only]" ;;
    esac
    shift
  done
  hub::main_project >/dev/null
  proj=$HUB_PROJECT host=$HUB_PROJECT_HOST
  local -a api=(api --hostname "$host" -X POST "repos/$proj/forks" ${org:+-f "organization=$org"} ${name:+-f "name=$name"})
  ((branch_only)) && api+=(-F default_branch_only=true)
  api+=(--jq .full_name) # GitHub answers with the fork, new or already there, under its real name
  ((no_remote)) && hub::exec_gh "${api[@]}"

  if [[ -n $org ]]; then owner=$org; else owner=$(hub::current_user "$host") || exit 1; fi
  want=$owner/${name:-${proj#*/}}
  remote=${remote:-$owner}
  if current=$(hub::git_query remote get-url "$remote"); then
    hub::remote_project "$remote" >/dev/null && hub::same_host "$HUB_PROJECT_HOST" "$host" \
      && [[ ${HUB_URL_OWNER,,} == "${owner,,}" ]] \
      || hub::die "Aborted: a remote named '$remote' already exists for $current, not for $owner's fork; pick another name with --remote-name NAME."
    existing=$HUB_PROJECT
  fi

  if ((HUB_NOOP)); then
    hub::gh "${api[@]}"
    full=$want
  else
    full=$(hub::gh_query "${api[@]}") || exit
    [[ $full == ?*/?* ]] || hub::die "Aborted: expected the fork's OWNER/REPO from GitHub, got '$full'."
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
  _hub_fork_fetch "$remote" "$full"
}

_hub_fork_fetch() {
  local remote=$1 fork=$2 log status why pause retry=0
  local -a pauses=(2 4 8 16) fetch=(fetch)
  [[ -t 2 ]] && fetch+=(--progress) # git shows no progress meter on a pipe
  fetch+=("$remote")
  log=$(mktemp) || exit
  # shellcheck disable=SC2064  # expand $log now
  trap "rm -f -- $(printf '%q' "$log")" EXIT
  while :; do
    { # git's messages go to the terminal and to $log
      hub::git "${fetch[@]}" 2>&1 >&3 3>&- | tee "$log" >&2
      status=${PIPESTATUS[0]}
    } 3>&1
    ((status)) || return 0
    # GitHub creates the fork in the background; until it is done, git finds no repository there.
    why=$(grep -Ei -- "repository( '[^']*')? not found|does not appear to be a git repository|repository.* does not exist|empty repository" "$log" | tail -n 1)
    [[ -n $why ]] \
      || hub::die "error: could not fetch the fork $fork. The fork and the remote '$remote' exist; run 'git fetch $remote' later."
    ((retry < ${#pauses[@]})) \
      || hub::die "error: could not fetch the fork $fork after $((retry + 1)) attempts: ${why%.}. Either GitHub has not finished creating it (run 'git fetch $remote' later) or this account cannot read it."
    pause=${HUB_FORK_RETRY_DELAY:-${pauses[retry]}} # tests set it to 0
    retry=$((retry + 1))
    hub::warn "GitHub may still be creating the fork $fork; fetching it again in ${pause}s (retry $retry of ${#pauses[@]})."
    sleep "$pause"
  done
}
