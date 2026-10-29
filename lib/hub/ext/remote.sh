# shellcheck shell=bash
# Summary: Add or change a remote using a GitHub OWNER[/REPO] name.
# Usage: hub remote add [-p] [<git-remote-add options>] [NAME] OWNER[/REPO]
#        hub remote set-url [-p] [--push | --add] NAME OWNER[/REPO] [OLDURL]
#
# Expands OWNER[/REPO] to a clone URL for `git remote add` or `git remote
# set-url`. A bare OWNER means OWNER's copy of the current repository: REPO
# defaults to the current project's name on GitHub (GH_REPO, else the upstream,
# github or origin remote), else to the name of the work tree's directory. NAME
# defaults to OWNER.
#
# The URL is on the current project's host (else GH_HOST, else github.com) and
# uses SSH or HTTPS as `hub clone` does. Nothing is looked up on GitHub. URLs,
# paths and the other `git remote` subcommands go to git untouched.
#
# Options:
#   -p   Use SSH for the URL, whatever the configured protocol.
#
#   $ hub remote add jingweno
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#
#   $ hub remote add -f upstream github/hub
#   > git remote add -f upstream https://github.com/github/hub.git
#
#   $ hub remote set-url --push origin mislav
#   > git remote set-url --push origin https://github.com/mislav/REPO.git
#
# For git's own options, see `man git-remote`.

hub_ext_remote() {
  local sub=${1-}
  case $sub in
    --help) hub::usage ;;
    add | set-url) shift ;;
    *) hub::exec_git remote "$@" ;;
  esac
  local -a args=() flags=() pos=() sep=()
  local arg proto='' value=0 delete=0
  for arg in "$@"; do
    if ((value)); then
      value=0
      flags+=("$arg")
    elif ((${#sep[@]})) || [[ $arg != -?* ]]; then
      pos+=("$arg")
    else
      case $arg in
        --) sep=(--) ;;
        --help) hub::usage ;;
        -p)
          proto=ssh
          continue
          ;;
        --delete)
          delete=1
          flags+=("$arg")
          ;;
        *)
          flags+=("$arg")
          [[ $sub == add ]] && _hub_remote_takes_value "$arg" && value=1
          ;;
      esac
    fi
    args+=("$arg")
  done
  local name spec url
  case $sub:${#pos[@]}:$delete in
    add:1:*)
      spec=${pos[0]}
      name=${spec%%/*}
      ;;
    add:2:* | set-url:[23]:0)
      name=${pos[0]}
      spec=${pos[1]}
      ;;
    *) hub::exec_git remote "$sub" "${args[@]}" ;;
  esac
  hub::is_shorthand "$spec" || hub::exec_git remote "$sub" "${args[@]}"
  url=$(_hub_remote_url "$spec" "$proto") || exit 1
  hub::exec_git remote "$sub" "${flags[@]}" "${sep[@]}" "$name" "$url" "${pos[@]:2}"
}

# _hub_remote_takes_value OPTION : true if a `git remote add` OPTION consumes the next argument.
_hub_remote_takes_value() {
  case $1 in
    --track | --master) return 0 ;;
    --*) return 1 ;;
  esac
  # -t and -m take the rest of a short option cluster (-tmain), or the next argument when last (-ft main).
  local opts=${1#-} head
  head=${opts%%[tm]*}
  [[ $head != "$opts" ]] && ((${#head} + 1 == ${#opts}))
}

# _hub_remote_url OWNER[/REPO] [PROTOCOL] : clone URL on the current project's host;
# a bare OWNER gets the current project's repository name.
_hub_remote_url() {
  local spec=$1 host repo
  read -r host repo <<<"$(_hub_remote_project)"
  [[ $spec == */* ]] || spec=$spec/$repo
  [[ ${spec##*/} == ?*.git ]] && spec=${spec%.git}
  # GH_HOST makes hub::protocol read gh's git_protocol for this host.
  GH_HOST=$host hub::git_url "$spec" "$host" "${2-}"
}

# _hub_remote_project : print "HOST REPO" for the current project: its GitHub host and repository
# name (hub::main_project), else the default host and the work tree's directory name.
_hub_remote_project() {
  local info name
  if info=$(hub::main_project 2>/dev/null && printf '%s\n' "$HUB_PROJECT_HOST"); then
    name=${info%%$'\n'*}
    printf '%s %s\n' "${info##*$'\n'}" "${name#*/}"
    return 0
  fi
  name=$(hub::git_query rev-parse --show-toplevel) || name=$PWD
  name=${name##*/}
  name=${name%.git}
  printf '%s %s\n' "$(hub::host)" "${name//[^A-Za-z0-9_.-]/-}"
}
