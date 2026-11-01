# shellcheck shell=bash
# Summary: Clone a GitHub repository by its [OWNER/]REPO name.
# Usage: hub clone [-p] [GIT-CLONE-OPTIONS...] [OWNER/]REPO [DIR]
#
# A git command hub extends: git clone's options apply. When the repository operand is a
# shorthand, OWNER/REPO or REPO (one of your own repositories), hub replaces it with its clone
# URL on the default host and runs git clone with every other argument in place. REPO.wiki is
# the wiki. Only your login for REPO comes from gh: its stored account, or GitHub's API when a
# token variable (GH_TOKEN, GITHUB_TOKEN, ...) is set; nothing else is looked up on GitHub. A
# URL, a path, HOST/OWNER/REPO, or a name git reads as a local repository (an existing path,
# NAME.git holding a repository, a NAME.bundle file) is plain git clone; write ./NAME to clone a
# local repository named like a shorthand. The URL uses gh's git_protocol for the host (gh
# config set git_protocol ssh), else https.
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
  local valued="${table[*]}" repo owner host protocol="" i
  local -a line
  # hub's -p is dropped first, so no line handed to git, by hub::scan either, carries it.
  ! hub::drop_flag p "$valued" "$@" || protocol=ssh
  line=("${HUB_ARGS[@]}")
  hub::scan "$valued" "${line[@]}"
  ((${#HUB_OPERANDS[@]})) || hub::exec_git clone "${line[@]}"
  i=${HUB_OPERANDS[0]}
  repo=${line[i]%.git}
  if ! hub::is_shorthand "$repo" || hub::local_source "${line[i]}" bundle; then
    hub::exec_git clone "${line[@]}"
  fi
  host=$(hub::host) || exit 1
  if [[ $repo == */* ]]; then
    owner=${repo%%/*} repo=${repo#*/}
  else
    owner=$(hub::login "$host") || exit 1
  fi
  line[i]=$(hub::clone_url "$host" "$owner" "$repo" "$protocol")
  hub::exec_git clone "${line[@]}"
}
