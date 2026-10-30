# shellcheck shell=bash
# Summary: Clone a GitHub repository by its [OWNER/]REPO name.
# Usage: hub clone [-p] [<git-clone options>] [[HOST/]OWNER/]REPO [DIR]
#
# Expands the repository name to a clone URL and runs git clone with every other
# argument in place. A bare REPO is one of your own repositories and REPO.wiki is
# a wiki. The host is HOST, else gh's default host. URLs and paths go to git
# unchanged, and nothing is looked up on GitHub.
#
# Options:
#   -p   Clone over SSH. Otherwise hub.protocol, else gh's git_protocol, else HTTPS.
#
#   $ hub clone rtomayko/ronn
#   > git clone https://github.com/rtomayko/ronn.git
#
#   $ hub clone -p dotfiles --depth 1
#   > git clone git@github.com:YOUR-LOGIN/dotfiles.git --depth 1

hub_ext_clone() {
  local -a args=()
  local arg proto='' pos=-1 ended=0 value=0 repo host
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      ((pos >= 0)) || pos=${#args[@]}
    else
      case $arg in
        --) ended=1 ;;
        --help) hub::usage ;;
        -p) proto=ssh && continue ;;
        *) _hub_clone_takes_value "$arg" && value=1 ;;
      esac
    fi
    args+=("$arg")
  done
  ((pos >= 0)) || hub::exec_git clone "${args[@]}"
  repo=${args[pos]} host=${args[pos]%%/*}
  if [[ $repo =~ ^[A-Za-z0-9][A-Za-z0-9.-]*/[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$ && ! -e $repo ]] \
    && { [[ $host == *.* ]] || hub::is_known_host "$host"; }; then
    repo=${repo#*/}
  elif hub::is_shorthand "$repo"; then
    host=$(hub::host)
    [[ $repo == */* ]] || repo=$(hub::current_user "$host")/$repo || exit
  else
    hub::exec_git clone "${args[@]}"
  fi
  args[pos]=$(hub::git_url "${repo%.git}" "$host" "$proto")
  hub::exec_git clone "${args[@]}"
}

_hub_clone_takes_value() {
  case $1 in
    --branch | --bundle-uri | --config | --depth | --filter | --jobs | --origin | --ref-format) return 0 ;;
    --reference | --reference-if-able | --revision | --separate-git-dir | --server-option) return 0 ;;
    --shallow-exclude | --shallow-since | --template | --upload-pack) return 0 ;;
  esac
  [[ $1 =~ ^-[^-bcjou]*[bcjou]$ ]] # -b -c -j -o -u last in a cluster (-qb main)
}
