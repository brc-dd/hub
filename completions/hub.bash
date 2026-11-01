# shellcheck shell=bash
# shellcheck disable=SC2154  # cur, prev, words and cword are set by git's __git_func_wrap
# Summary: bash completion for hub, and for git when git is an alias for hub.
# Usage: . completions/hub.bash
#
# git's completion, plus hub's commands where the command word goes and the options of hub's own
# commands, when the command is hub or a shell alias for it (alias git=hub). Plain git completes
# as before: a completion registered for git with -F FUNCTION, git's own or yours, keeps
# completing it; one registered otherwise (-C, -W) is left alone, and git then gets no hub
# commands. git's completion comes from bash-completion or Homebrew's git; source git's
# git-completion.bash before this file when it is elsewhere. make install links this file into a
# bash_completion.d directory. It runs in the user's shell, which may be bash 3.2.

__hub_commands='alias am api apply browse checkout cherry-pick ci-status clone compare create
  delete fetch fork gist help issue merge pr pull-request push release remote sync version'

# __hub_options CMD : the options of hub's own command CMD, as __gitcomp takes them.
__hub_options() {
  case $1 in
    alias) echo '-s' ;;
    browse) echo '--url --copy' ;;
    ci-status) echo '--verbose' ;;
    compare) echo '--base= --url --copy' ;;
    create)
      echo '--private --public --internal --description= --homepage= --remote-name= --push' \
        '--browse --copy'
      ;;
    delete) echo '--yes' ;;
    fork) echo '--no-remote --remote-name= --org= --fork-name= --default-branch-only' ;;
    pull-request)
      echo '--message= --file= --edit --no-edit --base= --head= --push --force --draft' \
        '--reviewer= --assign= --milestone= --labels= --no-maintainer-edits --browse --copy'
      ;;
    version) echo '--build-options' ;;
    *) return 1 ;;
  esac
}

# __hub_invoked WORD : WORD is hub, or a shell alias whose command is hub.
__hub_invoked() {
  local w=$1
  [[ ${w##*/} == hub ]] && return 0
  w=$(alias -- "$w" 2>/dev/null) || return 1
  w=${w#*=} w=${w#[\'\"]} w=${w%% *} w=${w%[\'\"]}
  [[ ${w##*/} == hub ]]
}

if ! declare -F __git_main >/dev/null; then
  if declare -F _comp_load >/dev/null; then
    _comp_load git >/dev/null 2>&1
  elif declare -F _completion_loader >/dev/null; then
    _completion_loader git >/dev/null 2>&1
  fi
fi
if ! declare -F __git_main >/dev/null; then
  for __hub_file in /usr/share/bash-completion/completions/git \
    /opt/homebrew/etc/bash_completion.d/git-completion.bash \
    /usr/local/etc/bash_completion.d/git-completion.bash; do
    # shellcheck source=/dev/null
    [[ -r $__hub_file ]] && . "$__hub_file" && break
  done
  unset __hub_file
fi

if declare -F __git_main >/dev/null && declare -F __git_func_wrap >/dev/null; then
  # __hub_main : git's completion for a hub command line.
  __hub_main() {
    local i=1 cmd='' fn have
    local -a kept=("${words[0]}")
    while ((i < cword)); do
      case ${words[i]} in
        # git's completion does not know that these take a value: they go, with it.
        --config-env | --attr-source | --super-prefix | --shallow-file)
          ((i + 1 < cword)) || return 0
          ((i += 2))
          continue
          ;;
        -C | -c | --git-dir | --work-tree | --namespace)
          kept+=("${words[i]}" "${words[i + 1]}")
          ((i += 2))
          continue
          ;;
        --version | -v | --help | -h | --exec-path | --html-path | --man-path | --info-path | \
          --list-cmds=* | [!-]*)
          cmd=${words[i]}
          break
          ;;
      esac
      kept+=("${words[i]}")
      ((i++))
    done
    ((i <= cword)) || cmd=- # the word being completed is a global option's value
    cword=$((cword - i + ${#kept[@]}))
    words=("${kept[@]}" "${words[@]:i}")
    fn=_git_${cmd//-/_}
    if __hub_options "$cmd" >/dev/null && ! declare -F "$fn" >/dev/null; then
      # Defined for this completion only: plain git and a _git_CMD of yours never see it.
      eval "$fn() { [[ \$cur != -* ]] || __gitcomp \"\$(__hub_options $cmd)\"; }"
      __git_main
      unset -f "$fn"
      return 0
    fi
    __git_main
    [[ -z $cmd && $cur != -* ]] || return 0
    have=" ${COMPREPLY[*]-} "
    for cmd in $__hub_commands; do
      [[ $cmd == "$cur"* && $have != *" $cmd "* ]] && COMPREPLY+=("$cmd ")
    done
    return 0
  }

  # __hub_wrap COMMAND WORD PREVIOUS : the completion of hub, and of git.
  __hub_wrap() {
    if __hub_invoked "${COMP_WORDS[0]}"; then
      __git_func_wrap __hub_main
    elif [[ -n $__hub_git_function ]]; then
      "$__hub_git_function" "$@"
    else
      __git_func_wrap __git_main
    fi
  }

  complete -o bashdefault -o default -o nospace -F __hub_wrap hub

  __hub_spec=$(complete -p git 2>/dev/null) || __hub_spec=''
  # complete -p prints -F FUNCTION last, before the name; a -F inside a quoted -X or -W value is
  # not a function name.
  __hub_function=${__hub_spec% git}
  __hub_function=${__hub_function##* -F }
  if [[ -z $__hub_spec ]]; then
    __hub_git_function=''
    complete -o bashdefault -o default -o nospace -F __hub_wrap git
  elif [[ $__hub_spec == *' -F '*' git' && $__hub_function != __hub_wrap ]] \
    && declare -F "$__hub_function" >/dev/null; then
    __hub_git_function=$__hub_function
    eval "${__hub_spec% -F "$__hub_function" git} -F __hub_wrap git"
  fi
  unset __hub_spec __hub_function
else
  # __hub_fallback : without git's completion, hub's commands as the first word, then file names.
  __hub_fallback() {
    local cmd
    COMPREPLY=()
    ((COMP_CWORD == 1)) || return 0
    for cmd in $__hub_commands; do
      [[ $cmd == "$2"* ]] && COMPREPLY+=("$cmd")
    done
    return 0
  }
  complete -o default -F __hub_fallback hub
fi
