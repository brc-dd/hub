# shellcheck shell=bash
# shellcheck disable=SC2154  # cur, prev, words and cword are set by git's completion (__git_func_wrap)
# bash completion for hub: hub completes like git, plus hub's own commands.
# It covers `hub`, and `git` too when git is an alias for hub
# (eval "$(hub alias -s)"). Source this file from ~/.bashrc, or install it
# into a bash_completion.d directory (make install does that).
#
# git's own bash completion (git-completion.bash) does the real work and is
# loaded first when it can be found. Without it, hub's command names are
# still completed. Works in bash 3.2 and later.
#
# The commands below are hub's commands that git does not have, as listed by
# the "# Summary:" lines of lib/hub/{cmd,ext}/*.sh. The git commands hub
# extends (clone, push, checkout, ...) are completed by git's completion.

__hub_commands='alias api browse ci-status compare create delete fork gist issue pr pull-request release sync'

# Load git's completion if it isn't loaded yet.
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
  # git's completion, plus hub's commands where a command word is expected.
  __hub_main() {
    __git_main
    if [[ ${words[0]##*/} != hub && $(alias "${words[0]}" 2>/dev/null) != *=\'hub* ]]; then
      return 0 # plain git
    fi
    local i=1
    while ((i < cword)); do
      case ${words[i]} in
        -C | -c | --git-dir | --work-tree | --namespace) ((i++)) ;;
        -*) ;;
        *) return 0 ;; # the command word is already there
      esac
      ((i++))
    done
    case $cur in -*) return 0 ;; esac
    case $prev in -C | -c | --git-dir | --work-tree | --namespace) return 0 ;; esac
    local cmd have=" ${COMPREPLY[*]-} "
    for cmd in $__hub_commands; do
      [[ $cmd == "$cur"* && $have != *" $cmd "* ]] && COMPREPLY+=("$cmd ")
    done
    return 0
  }
  __git_complete hub __hub_main
  __git_complete git __hub_main

  # __hub_complete CMD : the arguments of hub's command CMD (git's completion calls _git_CMD).
  __hub_complete() {
    local cmd=$1 subcommands='' options='' word i n=0
    case $cmd in
      gist) subcommands='list view show create edit delete clone rename' ;;
      issue) subcommands='list status view show create update labels close reopen comment edit transfer delete develop lock unlock pin unpin' ;;
      pr) subcommands='list status view show create checkout diff checks comment review merge edit close reopen ready lock unlock revert update-branch' ;;
      release) subcommands='list view show create edit download upload delete delete-asset verify verify-asset' ;;
    esac
    case $cmd in
      alias) options='-s' ;;
      api) options='--method --field --raw-field --header --include --input --jq --template --paginate --slurp --cache --hostname --silent --verbose --preview' ;;
      browse) options='--url --copy' ;;
      ci-status) options='--verbose' ;;
      compare) options='--url --copy --base' ;;
      create) options='--public --private --internal --description --homepage --remote-name --browse --push' ;;
      delete) options='--yes' ;;
      fork) options='--no-remote --remote-name --org --fork-name --default-branch-only' ;;
      pull-request) options='--message --file --edit --no-edit --base --head --draft --reviewer --assign --milestone --labels --no-maintainer-edits --push --force --browse --copy --issue --fill --dry-run' ;;
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

  for __hub_cmd in $__hub_commands; do
    eval "_git_${__hub_cmd//-/_}() { __hub_complete $__hub_cmd; }"
  done
  unset __hub_cmd
else
  # No git completion: hub's own commands, then file names.
  __hub_fallback() {
    COMPREPLY=()
    if ((COMP_CWORD == 1)); then
      local cmd
      for cmd in $__hub_commands; do
        [[ $cmd == "${COMP_WORDS[1]}"* ]] && COMPREPLY+=("$cmd")
      done
    fi
    return 0
  }
  complete -o bashdefault -o default -F __hub_fallback hub
fi
