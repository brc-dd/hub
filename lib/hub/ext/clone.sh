# shellcheck shell=bash
# Summary: Clone a GitHub repository by its [OWNER/]REPO name.
# Usage: hub clone [-p] [<git-clone options>] [OWNER/]REPO[.wiki] [DIR]
#        hub clone [-p] [<git-clone options>] HOST/OWNER/REPO [DIR]
#
# Expands the repository name to a clone URL and runs git clone with every
# other argument unchanged and in place, so git clone options can go before or
# after it. A bare REPO means one of your own repositories (your login comes
# from gh), and REPO.wiki is a repository's wiki. URLs, local paths and anything else that
# is not a repository name go to git untouched.
#
# The host is the one in HOST/OWNER/REPO, else GH_HOST, else github.com. The URL
# uses SSH or HTTPS according to `git config hub.protocol`, else gh's
# git_protocol for that host, else HTTPS. Nothing is looked up on GitHub first:
# git reports a repository that does not exist.
#
# Options:
#   -p   Clone over SSH, whatever the configured protocol.
#
#   $ hub clone rtomayko/ronn
#   > git clone https://github.com/rtomayko/ronn.git
#
#   $ hub clone -p dotfiles --depth 1
#   > git clone git@github.com:YOUR-LOGIN/dotfiles.git --depth 1
#
#   $ hub clone ghe.example.com/tools/deploy
#   > git clone https://ghe.example.com/tools/deploy.git
#
# For git's own options, see `man git-clone`.

hub_ext_clone() {
  local -a args=()
  local arg proto='' pos=-1 ended=0 value=0
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      ((pos >= 0)) || pos=${#args[@]} # the first operand is the repository
    else
      case $arg in
        --) ended=1 ;;
        --help) hub::usage ;;
        -p)
          proto=ssh
          continue
          ;;
        *) _hub_clone_takes_value "$arg" && value=1 ;;
      esac
    fi
    args+=("$arg")
  done
  local repo
  if ((pos >= 0)) && repo=$(_hub_clone_shorthand "${args[pos]}"); then
    args[pos]=$(_hub_clone_url "$repo" "$proto") || exit 1
  fi
  hub::exec_git clone "${args[@]}"
}

# _hub_clone_takes_value OPTION : true if OPTION consumes the next argument as its value.
_hub_clone_takes_value() {
  case $1 in
    --branch | --bundle-uri | --config | --depth | --filter | --jobs | --origin | --ref-format) return 0 ;;
    --reference | --reference-if-able | --revision | --separate-git-dir | --server-option) return 0 ;;
    --shallow-exclude | --shallow-since | --template | --upload-pack) return 0 ;;
    --*) return 1 ;;
  esac
  # In a cluster of short options, a value option (-b -c -j -o -u) takes the rest of
  # the cluster as its value (-bmain), or the next argument when it comes last (-qb main).
  local opts=${1#-} head
  head=${opts%%[bcjou]*}
  [[ $head != "$opts" ]] && ((${#head} + 1 == ${#opts}))
}

# _hub_clone_shorthand ARG : print ARG without a .git suffix if it names a GitHub repository
# (HOST/OWNER/REPO, OWNER/REPO or a bare REPO); return 1 for URLs, existing paths and the rest.
_hub_clone_shorthand() {
  local arg=$1
  [[ $arg == -* || -e $arg ]] && return 1
  if [[ $arg =~ ^([A-Za-z0-9][A-Za-z0-9.-]*)/[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$ ]]; then
    [[ ${BASH_REMATCH[1]} == *.* ]] || hub::is_known_host "${BASH_REMATCH[1]}" || return 1
  elif ! hub::is_shorthand "$arg"; then
    [[ $arg =~ ^[A-Za-z0-9_.-]+$ ]] || return 1 # a bare REPO may contain dots: dotfiles.wiki, mislav.github.io
  fi
  [[ ${arg##*/} == ?*.git ]] && arg=${arg%.git}
  printf '%s\n' "$arg"
}

# _hub_clone_url REPO [PROTOCOL] : clone URL for HOST/OWNER/REPO, OWNER/REPO or a bare REPO of your own.
_hub_clone_url() {
  local repo=$1 host user
  case $repo in
    */*/*)
      host=${repo%%/*}
      repo=${repo#*/}
      ;;
    */*) host=$(hub::host) ;;
    *)
      host=$(hub::host)
      user=$(hub::current_user) || return 1
      repo=$user/$repo
      ;;
  esac
  # GH_HOST makes hub::protocol read gh's git_protocol for this host.
  GH_HOST=$host hub::git_url "$repo" "$host" "${2-}"
}
