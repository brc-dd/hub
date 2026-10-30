# shellcheck shell=bash
# Summary: Add or change a remote using a GitHub OWNER[/REPO] name.
# Usage: hub remote add [-p] [<git-remote-add options>] [NAME] OWNER[/REPO]
#        hub remote set-url [-p] [--push | --add] NAME OWNER[/REPO] [OLDURL]
#
# Expands OWNER[/REPO] to a clone URL on the current project's host and runs git
# remote with every other argument in place. REPO defaults to the current
# project's name (GH_REPO, else the upstream, github or origin remote, else the
# work tree's directory), and NAME to OWNER. `hub remote add origin` alone adds
# your own copy of the current repository. URLs, paths and the other
# subcommands go to git unchanged.
#
# Options:
#   -p   Use SSH. Otherwise hub.protocol, else gh's git_protocol, else HTTPS.
#
#   $ hub remote add jingweno
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#
#   $ hub remote add origin
#   > git remote add origin https://github.com/YOUR-LOGIN/REPO.git

hub_ext_remote() {
  local sub=${1-}
  case $sub in
    --help) hub::usage ;;
    add | set-url) shift ;;
    *) hub::exec_git remote "$@" ;;
  esac
  local -a args=() pos=()
  local arg proto='' value=0 ended=0 i name='' spec host repo
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      pos+=("${#args[@]}")
    else
      case $arg in
        --) ended=1 ;;
        --help) hub::usage ;;
        --delete) hub::exec_git remote "$sub" "$@" ;; # its URL is a regex
        -p) proto=ssh && continue ;;
        *) [[ $sub == add ]] && _hub_remote_takes_value "$arg" && value=1 ;;
      esac
    fi
    args+=("$arg")
  done
  case $sub:${#pos[@]} in
    add:1) i=${pos[0]} name=${args[pos[0]]%%/*} ;;
    add:2 | set-url:2 | set-url:3) i=${pos[1]} ;;
    *) hub::exec_git remote "$sub" "${args[@]}" ;;
  esac
  spec=${args[i]}
  hub::is_shorthand "$spec" || hub::exec_git remote "$sub" "${args[@]}"
  read -r host repo <<<"$(hub::project_or_dir)"
  if [[ -n $name && $spec == origin ]]; then # your own copy, not a user named origin
    spec=$(hub::current_user "$host") || exit
  fi
  [[ $spec == */* ]] || spec=$spec/$repo
  args[i]=$(hub::git_url "${spec%.git}" "$host" "$proto")
  hub::exec_git remote "$sub" "${args[@]:0:i}" ${name:+"$name"} "${args[@]:i}"
}

_hub_remote_takes_value() { [[ $1 == --track || $1 == --master || $1 =~ ^-[^-tm]*[tm]$ ]]; }
