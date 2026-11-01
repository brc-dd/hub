# shellcheck shell=bash
# Summary: Clone a GitHub repository by its [OWNER/]REPO name.
# Usage: hub clone [-p] [GIT-CLONE-OPTIONS...] [OWNER/]REPO [DIR]
#
# A git command hub extends: git clone's options apply. When the repository operand is a
# shorthand, OWNER/REPO or REPO (one of your own repositories), hub replaces it with its clone
# URL on gh's default host and runs git clone with every other argument in place. REPO.wiki is
# the wiki. Only your login for REPO comes from gh (its stored account, else GitHub's API);
# nothing else is looked up on GitHub. A URL, a path, HOST/OWNER/REPO, or a name git reads as a
# local repository (an existing path, NAME.git holding a repository, a NAME.bundle file) is
# plain git clone; write ./NAME to clone a local repository named like a shorthand. The URL uses
# gh's git_protocol for the host (gh config set git_protocol ssh), else https.
#
# Options:
#   -p   Clone over ssh this time.
#
#   $ hub clone rtomayko/ronn
#   > git clone https://github.com/rtomayko/ronn.git
#   $ hub clone -p dotfiles --depth 1
#   > git clone git@github.com:LOGIN/dotfiles.git --depth 1
#
# git's own manual: git clone --help

hub_cmd_clone() {
  local -a table=(-o --origin -b --branch -u --upload-pack --reference --reference-if-able
    --separate-git-dir --depth --shallow-since --shallow-exclude -j --jobs --template -c
    --config --filter --bundle-uri --server-option --ref-format --revision)
  local valued="${table[*]}" word flags repo owner host protocol="" i j
  local -a args=("$@") line=()
  # hub's -p is dropped first, so every line handed to git, by hub::scan too, is git's alone.
  for ((i = 0; i < $#; i++)); do
    word=${args[i]}
    if [[ $word == -- || $word == --end-of-options ]]; then
      line+=("${args[@]:i}")
      break
    elif _hub_clone_takes_next "$word" "$valued"; then
      line+=("${args[@]:i:2}")
      ((i += 1))
    else
      # -p alone or among the flags before a letter that takes a value (-qp, -pomine).
      for ((j = 1; j < ${#word}; j++)); do [[ $valued != *" -${word:j:1} "* ]] || break; done
      flags=${word:1:j-1}
      if [[ $word == -[A-Za-z]* && $flags =~ ^[A-Za-z]+$ && $flags == *p* ]]; then
        protocol=ssh
        word=-${flags//p/}${word:j}
        [[ $word != - ]] || continue
      fi
      line+=("$word")
    fi
  done
  hub::scan "$valued" "${line[@]}"
  ((${#HUB_OPERANDS[@]})) || hub::exec_git clone "${line[@]}"
  i=${HUB_OPERANDS[0]}
  repo=${line[i]%.git}
  if ! hub::is_shorthand "$repo" || _hub_clone_local_source "${line[i]}"; then
    hub::exec_git clone "${line[@]}"
  fi
  host=$(hub::host)
  if [[ $repo == */* ]]; then
    owner=${repo%%/*} repo=${repo#*/}
  else
    hub::require_gh
    owner=$(hub::login "$host") || exit 1
  fi
  # Without gh there is no git_protocol setting to read: https.
  if [[ -z $protocol ]] && command -v gh >/dev/null; then protocol=$(hub::protocol "$host"); fi
  line[i]=$(hub::clone_url "$host" "$owner" "$repo" "${protocol:-https}")
  hub::exec_git clone "${line[@]}"
}

# _hub_clone_takes_next WORD VALUED : git may read the word after WORD as WORD's value.
_hub_clone_takes_next() {
  local word=$1 valued=" $2 " long j
  [[ $valued != *" $word "* ]] || return 0
  case $word in
    --*=* | --) return 1 ;;
    --*)
      # An abbreviation, such as --dep for --depth.
      for long in $valued; do [[ $long != "$word"?* ]] || return 0; done
      ;;
    -?*)
      # In a cluster the first letter that takes a value takes the rest, or the next word.
      for ((j = 1; j < ${#word}; j++)); do
        if [[ $valued == *" -${word:j:1} "* ]]; then
          ((j == ${#word} - 1))
          return
        fi
      done
      ;;
  esac
  return 1
}

# _hub_clone_local_source STR : git reads STR as a local repository; hub::local_source misses
# STR.git/.git, a work tree named STR.git.
_hub_clone_local_source() {
  hub::local_source "$1" bundle || git rev-parse --resolve-git-dir "$1.git/.git" >/dev/null 2>&1
}
