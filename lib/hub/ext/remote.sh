# shellcheck shell=bash
# Summary: Add or change a remote using a GitHub OWNER[/REPO] name.
# Usage: hub remote add [-p] [<git-remote-add options>] [NAME] OWNER[/REPO]
#        hub remote set-url [-p] [--push | --add] NAME OWNER[/REPO] [OLDURL]
#
# A git command hub extends: git remote's options apply, and hub recognizes one operand, the
# OWNER[/REPO] in the URL's place. It is expanded to a clone URL on the current project's host,
# and git remote runs with every other argument in place. REPO defaults to the current project's
# name (GH_REPO, else the upstream, github or origin remote, else the work tree's directory,
# without a .git suffix), and NAME to OWNER. `hub remote add origin` alone adds your own copy of
# the current repository. URLs, paths and the other subcommands go to git unchanged.
#
# With two operands, an OWNER[/REPO] that git could read as a local path (an existing path, or
# NAME.git holding a repository) stays what git makes of it; with one operand there is nothing
# git could mean, so it is always expanded. When set-url's --delete is in effect (the last of
# --delete and --no-delete counts, as in git), the operand is a regex for git, not a name.
#
# hub reads the subcommand's options as the installed git does, from the option table git keeps
# for its completion: which ones take a value (--track main, -t main, in clusters too) and what
# an abbreviation stands for (--tra main); --mirror, which git lists with a value, takes only an
# attached one (--mirror=fetch). An option git would refuse leaves the command line to git.
#
# Options:
#   -p   Use SSH. Otherwise hub.protocol, else gh's git_protocol, else HTTPS.
#
#   $ hub remote add jingweno
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#
#   $ hub remote add origin
#   > git remote add origin https://github.com/YOUR-LOGIN/REPO.git
#
#   $ hub remote set-url -p upstream github/hub
#   > git remote set-url upstream git@github.com:github/hub.git

hub_ext_remote() {
  local sub=${1-}
  case $sub in
    --help) hub::usage ;;
    add | set-url) shift ;;
    *) hub::exec_git remote "$@" ;;
  esac
  local -a args=() pos=()
  local arg opt shorts='' proto='' value=0 ended=0 delete=0 i name='' spec host repo
  [[ $sub == add ]] && shorts=tm
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      pos+=("${#args[@]}")
    else
      case $arg in
        --) ended=1 ;;
        --help) hub::usage ;;
        -p)
          proto=ssh
          continue
          ;;
        *)
          hub::git_option "remote $sub" "$shorts" '' "$arg" || hub::exec_git remote "$sub" "$@" # an option git refuses
          # git lists --mirror with a value for its completion, but reads one only when it is attached
          [[ ${HUB_OPTS[-1]} == --mirror ]] && HUB_OPT_NEXT=0
          for opt in "${HUB_OPTS[@]}"; do
            case $opt in
              --delete) delete=1 ;;
              --no-delete) delete=0 ;;
            esac
          done
          ((HUB_OPT_NEXT)) && value=1
          ;;
      esac
    fi
    args+=("$arg")
  done
  ((delete)) && hub::exec_git remote "$sub" "${args[@]}" # the URL operand is a regex
  case $sub:${#pos[@]} in
    add:1) i=${pos[0]} name=${args[pos[0]]%%/*} ;;
    add:2 | set-url:2 | set-url:3) i=${pos[1]} ;;
    *) hub::exec_git remote "$sub" "${args[@]}" ;;
  esac
  spec=${args[i]}
  hub::is_project_name "$spec" || hub::exec_git remote "$sub" "${args[@]}"
  if [[ -z $name ]] && hub::local_source "$spec"; then hub::exec_git remote "$sub" "${args[@]}"; fi
  read -r host repo <<<"$(hub::project_or_dir)"
  [[ -n $repo ]] || exit 1
  if [[ -n $name && $spec == origin ]]; then # your own copy, not a user named origin
    spec=$(hub::current_user "$host") || exit
  fi
  [[ $spec == */* ]] || spec=$spec/$repo
  args[i]=$(hub::git_url "${spec%.git}" "$host" "$proto") || exit
  hub::exec_git remote "$sub" "${args[@]:0:i}" ${name:+"$name"} "${args[@]:i}"
}
