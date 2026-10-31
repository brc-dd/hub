# shellcheck shell=bash
# shellcheck disable=SC2154  # cur, prev, words and cword are set by git's completion
# bash completion for hub, and for git when it is an alias for hub: git's own
# completion plus hub's commands. Source it from ~/.bashrc or install it into a
# bash_completion.d directory (make install does). It runs in the user's shell,
# which may be bash 3.2.
#
# Plain git keeps git's completion untouched, git aliases and _git_CMD functions
# of the user's included: hub's commands, and their arguments, are offered only
# when the command is hub or a shell alias for it (alias git=hub), and never in
# place of a _git_CMD function that already exists.

__hub_commands='alias api browse ci-status compare create delete fork gist issue pr pull-request release sync'

# Load git's completion: through bash-completion, else from where git installs it.
if ! declare -F __git_main >/dev/null 2>&1; then
  if declare -F _comp_load >/dev/null 2>&1; then
    _comp_load git >/dev/null 2>&1
  elif declare -F _completion_loader >/dev/null 2>&1; then
    _completion_loader git >/dev/null 2>&1
  fi
fi
if ! declare -F __git_main >/dev/null 2>&1; then
  for __hub_file in \
    /usr/share/bash-completion/completions/git \
    /opt/homebrew/etc/bash_completion.d/git-completion.bash \
    /usr/local/etc/bash_completion.d/git-completion.bash \
    /usr/share/git/completion/git-completion.bash \
    /usr/share/git-core/contrib/completion/git-completion.bash \
    /Library/Developer/CommandLineTools/usr/share/git-core/git-completion.bash \
    /Applications/Xcode.app/Contents/Developer/usr/share/git-core/git-completion.bash; do
    if [[ -r $__hub_file ]]; then
      # shellcheck source=/dev/null
      . "$__hub_file" && break
    fi
  done
  unset __hub_file
fi

if declare -F __git_main >/dev/null 2>&1 && declare -F __git_complete >/dev/null 2>&1; then
  # __hub_invoked : the command word is hub, or a shell alias whose command is hub.
  __hub_invoked() {
    local w=${words[0]}
    [[ ${w##*/} == hub ]] && return 0
    w=$(alias "$w" 2>/dev/null) || return 1
    w=${w#*=} w=${w#[\'\"]} w=${w%% *} w=${w%[\'\"]}
    [[ ${w##*/} == hub ]]
  }

  # __hub_main : git's completion, plus, for hub, its commands where the command word goes
  # and their arguments after it.
  __hub_main() {
    local i=1 drop=0 cmd='' fn
    local -a w=("${words[0]}")
    if ! __hub_invoked; then
      __git_main
      return 0
    fi
    # Find the command word as bin/hub does: after git's global options, skipping the value of
    # the ones that take one. git's completion does not know that --config-env, --attr-source,
    # --super-prefix and --shallow-file take a value, so those go, with their values, before it
    # looks for the command word itself.
    while ((i < cword)); do
      case ${words[i]} in
        --config-env | --attr-source | --super-prefix | --shallow-file)
          ((i + 1 < cword)) || return 0 # its value is being completed
          ((i += 2, drop += 2))
          continue
          ;;
        -C | -c | --git-dir | --work-tree | --namespace)
          w+=("${words[i]}" "${words[i + 1]}") # the value may be the word being completed
          ((i += 2))
          continue
          ;;
        --version | -v | --help | -h | --exec-path | --html-path | --man-path | --info-path | --list-cmds=*)
          cmd=${words[i]} # git's own command word, or an option git answers by itself: no hub command follows
          break
          ;;
        -*) ;;
        *)
          cmd=${words[i]}
          break
          ;;
      esac
      w+=("${words[i]}")
      ((i++))
    done
    if ((drop)); then
      w+=("${words[@]:i}")
      words=("${w[@]}")
      cword=$((cword - drop))
      prev=${words[cword - 1]}
    fi
    fn=_git_${cmd//-/_}
    if [[ -n $cmd && " $__hub_commands " == *" $cmd "* ]] && ! declare -F "$fn" >/dev/null 2>&1; then
      # git's completion calls _git_CMD for the arguments of CMD. hub's is defined for this one
      # completion only, so that plain git, and a _git_CMD of the user's, never see it.
      eval "$fn() { __hub_complete $cmd; }"
      __git_main
      unset -f "$fn"
      return 0
    fi
    __git_main
    [[ -z $cmd && $cur != -* ]] || return 0
    case $prev in -C | -c | --git-dir | --work-tree | --namespace) return 0 ;; esac
    local have=" ${COMPREPLY[*]-} "
    for cmd in $__hub_commands; do
      [[ $cmd == "$cur"* && $have != *" $cmd "* ]] && COMPREPLY+=("$cmd ")
    done
    return 0
  }
  __git_complete hub __hub_main
  __git_complete git __hub_main

  # __hub_complete CMD : the arguments of hub's command CMD.
  __hub_complete() {
    local cmd=$1 subcommands='' options='' word i n=0
    case $cmd in
      gist) subcommands='list view show create edit delete clone rename' ;;
      issue) subcommands='list status view show create close reopen comment edit transfer delete develop lock unlock pin unpin' ;;
      pr) subcommands='list status view show create checkout diff checks comment review merge edit close reopen ready lock unlock revert update-branch' ;;
      release) subcommands='list view show create edit download upload delete delete-asset verify verify-asset' ;;
    esac
    case $cmd in
      alias) options='-s' ;;
      api) options='--method --field --raw-field --header --include --input --jq --template --paginate --slurp --cache --hostname --silent --verbose --preview' ;;
      browse) options='--url --copy' ;;
      ci-status) options='--verbose' ;;
      compare) options='--url --copy --base' ;;
      create) options='--public --private --internal --description --homepage --remote-name --browse --copy --push' ;;
      delete) options='--yes' ;;
      fork) options='--no-remote --remote-name --org --fork-name --default-branch-only' ;;
      pull-request) options='--message --file --edit --no-edit --base --head --draft --reviewer --assign --milestone --labels --no-maintainer-edits --push --force --browse --copy --issue' ;;
      sync) options='--color' ;;
    esac
    if [[ -n $subcommands && -z $(__git_find_on_cmdline "$subcommands") && $cur != -* ]]; then
      __gitcomp "$subcommands"
      return
    fi
    case $cur in
      -*)
        [[ -n $options ]] && __gitcomp "$options"
        return
        ;;
    esac
    case $cmd,$prev in
      compare,-b | compare,--base | pull-request,-b | pull-request,--base | pull-request,-h | pull-request,--head)
        __git_complete_refs
        return
        ;;
    esac
    case $cmd in
      alias) __gitcomp 'bash zsh sh ksh dash fish csh tcsh' ;;
      browse)
        # A SUBPAGE comes after the repository (or `--`).
        for ((i = ${__git_cmd_idx:-1} + 1; i < cword; i++)); do
          word=${words[i]}
          case $word in -u | -c | --url | --copy) ;; *) ((n++)) ;; esac
        done
        if ((n == 1)); then
          __gitcomp 'issues pulls wiki commits branches tags releases actions projects security pulse settings'
        fi
        ;;
      ci-status) __git_complete_refs ;;
      compare) __git_complete_revlist ;;
      sync) __gitcomp_nl "$(__git_remotes)" ;;
    esac
  }
else
  # Without git's completion: hub's commands where the command word goes, then file names.
  __hub_fallback() {
    local i=1 cmd
    COMPREPLY=()
    while ((i < COMP_CWORD)); do
      case ${COMP_WORDS[i]} in
        -C | -c | --config-env | --git-dir | --work-tree | --namespace | --attr-source | --super-prefix | --shallow-file) ((i++)) ;;
        --version | -v | --help | -h | --exec-path | --html-path | --man-path | --info-path | --list-cmds=*) return 0 ;;
        -*) ;;
        *) return 0 ;; # the command word is already there
      esac
      ((i++))
    done
    ((i == COMP_CWORD)) || return 0 # the value of a global option is being completed
    [[ ${COMP_WORDS[COMP_CWORD]} != -* ]] || return 0
    for cmd in $__hub_commands; do
      [[ $cmd == "${COMP_WORDS[COMP_CWORD]}"* ]] && COMPREPLY+=("$cmd")
    done
    return 0
  }
  complete -o bashdefault -o default -F __hub_fallback hub
fi
