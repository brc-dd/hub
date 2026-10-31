# shellcheck shell=bash
# Summary: Clone a GitHub repository by its [OWNER/]REPO name.
# Usage: hub clone [-p] [<git-clone options>] [OWNER/]REPO [DIR]
#
# A git command hub extends: git clone's options apply, and hub recognizes one operand, the
# repository. When it is a GitHub shorthand, OWNER/REPO or REPO (one of your own repositories),
# hub replaces it with the clone URL on gh's default host and runs git clone with every other
# argument in place. REPO.wiki is a wiki, and a name may start with a dot, as .github. Nothing is
# looked up on GitHub.
#
# An operand that git could read as a local source stays with git: an existing path, a NAME.git
# directory holding a repository or a NAME.bundle file (git's own suffix rules). To clone a local
# repository whose name looks like a shorthand, write its path: ./NAME. URLs, and anything that
# is not lexically a shorthand, go to git unchanged.
#
# hub finds the operand by knowing which of git clone's options take a value (git 2.54). An
# abbreviated long option (--dep 1 for --depth 1) is not recognized, so its value would be taken
# for the repository: spell options out when mixing them with a shorthand.
#
# Options:
#   -p   Clone over SSH. Otherwise hub.protocol, else gh's git_protocol, else HTTPS.
#
#   $ hub clone rtomayko/ronn
#   > git clone https://github.com/rtomayko/ronn.git
#
#   $ hub clone -p dotfiles --depth 1
#   > git clone git@github.com:YOUR-LOGIN/dotfiles.git --depth 1
#
#   $ hub clone .github
#   > git clone https://github.com/YOUR-LOGIN/.github.git

hub_ext_clone() {
  local -a args=()
  local arg proto='' pos=-1 ended=0 value=0 repo
  for arg in "$@"; do
    if ((value)); then
      value=0
    elif ((ended)) || [[ $arg != -?* ]]; then
      ((pos >= 0)) || pos=${#args[@]}
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
  if ((pos < 0)) || ! hub::is_project_name "${args[pos]}" || hub::local_source "${args[pos]}" bundle; then
    hub::exec_git clone "${args[@]}"
  fi
  repo=$(hub::expand_project "${args[pos]}") || exit
  args[pos]=$(hub::git_url "${repo%.git}" '' "$proto") || exit
  hub::exec_git clone "${args[@]}"
}

# _hub_clone_takes_value OPTION : git clone's options whose value is the next argument (git 2.54).
# Attached values (--depth=1, -bmain) and the optional value of --recurse-submodules take none.
_hub_clone_takes_value() {
  case $1 in
    --branch | --bundle-uri | --config | --depth | --filter | --jobs | --origin | --ref-format) return 0 ;;
    --reference | --reference-if-able | --revision | --separate-git-dir | --server-option) return 0 ;;
    --shallow-exclude | --shallow-since | --template | --upload-pack) return 0 ;;
  esac
  [[ $1 =~ ^-[^-bcjou]*[bcjou]$ ]] # -b -c -j -o -u last in a cluster (-qb main)
}
