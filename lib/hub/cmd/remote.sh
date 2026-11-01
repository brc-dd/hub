# shellcheck shell=bash
# Summary: Add or change a remote by its GitHub OWNER[/REPO] name.
# Usage: hub remote add [-p] [GIT-REMOTE-ADD-OPTIONS...] NAME OWNER[/REPO]
#        hub remote add [-p] [GIT-REMOTE-ADD-OPTIONS...] USER
#        hub remote set-url [-p] [--push] [--add] NAME OWNER[/REPO]
#
# A git command hub extends: git remote's options apply. hub puts a clone URL in the place of
# OWNER[/REPO], on the current project's host (else gh's default host), and runs git remote with
# every other word as given. REPO defaults to the project's repository name, else the name of
# the repository's directory. With one operand, USER names both the remote and the owner, and
# origin alone means your own copy of the repository. With two operands, a word git can read
# as a local path stays a path. URLs, paths, set-url --delete, set-url with OLDURL and the
# other subcommands are plain git remote.
#
# Options:
#   -p   Use an ssh URL. Otherwise gh's git_protocol decides (gh config set git_protocol ssh),
#        else https.
#
#   $ hub remote add jingweno
#   > git remote add jingweno https://github.com/jingweno/REPO.git
#   $ hub remote add origin
#   > git remote add origin https://github.com/LOGIN/REPO.git
#   $ hub remote set-url -p upstream github/hub
#   > git remote set-url upstream git@github.com:github/hub.git
#
# git's own manual: git remote --help

hub_cmd_remote() {
  local valued='' proto='' delete=0 sub=0 cmd slot name='' spec owner repo project host top w i
  local -a words=("$@") args=() ops=() operand=()
  # git remote takes -v before its subcommand.
  for w in "$@"; do
    [[ $w =~ ^-v+$ || (${#w} -ge 3 && --verbose == "$w"*) ]] \
      || [[ ${#w} -ge 6 && --no-verbose == "$w"* ]] || break
    ((sub += 1))
  done
  cmd=${words[sub]-}
  case $cmd in
    add) valued='-t --track -m --master' ;;
    set-url) ;;
    *) hub::exec_git remote "$@" ;;
  esac
  hub::scan "$valued" "$@"
  for i in "${HUB_OPERANDS[@]}"; do operand[i]=1; done
  args=("${words[@]:0:sub+1}")
  # The same walk as hub::scan's, to drop hub's -p where it is an option and not a value.
  for ((i = sub + 1; i < $#; i++)); do
    w=${words[i]}
    if [[ -n ${operand[i]-} ]]; then
      ops+=("${#args[@]}")
    elif [[ " $valued " == *" $w "* ]]; then
      args+=("$w")
      ((i += 1))
    elif [[ $w =~ ^-[A-Za-z]*p[A-Za-z]*$ && " $valued " != *" ${w:0:2} "* ]]; then
      proto=ssh
      w=${w//p/}
      if [[ $w != - ]]; then args+=("$w"); fi
      continue
    elif [[ $cmd == set-url && ${#w} -ge 3 && --delete == "$w"* ]]; then
      delete=1
    fi
    args+=("${words[i]}")
  done
  # With --delete the URL operand is a regular expression for git.
  ((delete == 0)) || hub::exec_git remote "${args[@]}"
  hub::git_query rev-parse --git-dir >/dev/null || hub::exec_git remote "${args[@]}"
  case $cmd:${#ops[@]} in
    add:1)
      slot=${ops[0]} name=${args[slot]}
      [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || hub::exec_git remote "${args[@]}"
      ;;
    add:2 | set-url:2)
      slot=${ops[1]}
      spec=${args[slot]}
      # git reads a relative path from the top directory; one that exists here is a path too.
      top=$(hub::toplevel) || top=$(hub::git_query rev-parse --absolute-git-dir)
      if ! hub::is_shorthand "$spec" || hub::local_source "$spec" \
        || (cd "$top" && hub::local_source "$spec") \
        || [[ $spec != */* && ! $spec =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
        hub::exec_git remote "${args[@]}"
      fi
      ;;
    *) hub::exec_git remote "${args[@]}" ;;
  esac
  spec=${args[slot]}
  # origin alone needs your login.
  [[ $name != origin ]] || hub::require_gh
  # hub::repo_name also refuses an invalid GH_REPO.
  repo=$(hub::repo_name) || exit 1
  project=$(hub::project 2>/dev/null)
  host=${project%% *}
  [[ -n $host ]] || host=$(hub::host)
  if [[ $spec == */* ]]; then
    owner=${spec%%/*} repo=${spec#*/}
    [[ $repo != ?*.git ]] || repo=${repo%.git}
  else
    owner=$spec
    if [[ $name == origin ]]; then owner=$(hub::login "$host") || exit 1; fi
  fi
  # Without gh there is no git_protocol setting to read: https.
  if [[ -z $proto ]] && command -v gh >/dev/null; then proto=$(hub::protocol "$host"); fi
  hub::exec_git remote "${args[@]:0:slot}" ${name:+"$name"} \
    "$(hub::clone_url "$host" "$owner" "$repo" "${proto:-https}")" "${args[@]:slot+1}"
}
