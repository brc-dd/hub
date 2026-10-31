#compdef hub
# zsh completion for hub, and for git when it is an alias for hub: zsh's _git
# plus hub's commands. Install it as _hub in a directory on $fpath (make install
# does), or source it after compinit. With `setopt complete_aliases`, git is
# completed as git even when it is an alias: source this file after compinit
# then, and it wraps the completion registered for git.
#
# Plain git keeps its completion untouched, the user-commands style, git aliases
# and _git-CMD functions of the user's included: hub's commands, and their
# arguments, are offered only when the command is hub or a shell alias whose
# command is hub, and never in place of a _git-CMD function that already exists.

typeset -ga _hub_commands
_hub_commands=(
  'alias:show how to make `git` run hub'
  'api:make an authenticated GitHub API request (gh api)'
  'browse:open a GitHub repository page in the browser'
  'ci-status:show the CI status of a commit'
  'compare:open a GitHub compare page for a branch or a range'
  'create:create a GitHub repository for the current project and add it as a remote'
  'delete:delete a repository on GitHub'
  'fork:fork the current repository on GitHub and add the fork as a remote'
  'gist:create and view gists (gh gist)'
  'issue:list, view, create and edit issues (gh issue)'
  'pr:list, view, check out and merge pull requests (gh pr)'
  "pull-request:open a pull request (gh pr create, with hub's options)"
  'release:list, view, create, edit and download releases (gh release)'
  'sync:fetch a remote and fast-forward or delete local branches to match it'
)

# The arguments of hub's commands: _git completes `git CMD ...` with _git-CMD.
typeset -gA _hub_subcommands _hub_options
_hub_subcommands=(
  gist    'list view show create edit delete clone rename'
  issue   'list status view show create close reopen comment edit transfer delete develop lock unlock pin unpin'
  pr      'list status view show create checkout diff checks comment review merge edit close reopen ready lock unlock revert update-branch'
  release 'list view show create edit download upload delete delete-asset verify verify-asset'
)
_hub_options=(
  alias        '-s'
  api          '-X --method -F --field -f --raw-field -H --header -i --include --input -q --jq --template --paginate --slurp --cache --hostname --silent --verbose -p --preview'
  browse       '-u --url -c --copy'
  ci-status    '-v --verbose'
  compare      '-u --url -c --copy -b --base'
  create       '--public -p --private --internal -d --description -h --homepage --remote-name -o --browse -c --copy --push'
  delete       '-y --yes'
  fork         '--no-remote --remote-name --org --fork-name --default-branch-only'
  pull-request '-m --message -F --file -e --edit --no-edit -b --base -h --head -d --draft -r --reviewer -a --assign -M --milestone -l --labels --no-maintainer-edits -p --push -f --force -o --browse -c --copy -i --issue'
  sync         '--color'
)

_hub_arguments() {
  local cmd=$words[1] expl
  if [[ -n $_hub_subcommands[$cmd] && $PREFIX != -* ]] && (( CURRENT == 2 )); then
    _wanted subcommands expl subcommand compadd -- ${=_hub_subcommands[$cmd]}
    return
  fi
  if [[ $PREFIX == -* && -n $_hub_options[$cmd] ]]; then
    _wanted options expl option compadd -- ${=_hub_options[$cmd]}
    return
  fi
  case $cmd:$words[CURRENT-1] in
    (compare:(-b|--base)|pull-request:(-b|--base|-h|--head))
      __git_branch_names
      return ;;
  esac
  case $cmd in
    (alias)
      _wanted shells expl shell compadd -- bash zsh sh ksh dash fish csh tcsh ;;
    (browse)
      # A SUBPAGE comes after the repository (or `--`).
      local -a args
      args=(${words[2,CURRENT-1]:#(-u|-c|--url|--copy)})
      if (( $#args == 1 )); then
        _wanted subpages expl subpage compadd -- issues pulls wiki commits branches tags releases actions projects security pulse settings
      fi ;;
    (ci-status) __git_revisions ;;
    (compare)   __git_commit_ranges ;;
    (sync)      __git_remotes ;;
    (*)         _default ;;
  esac
}

# _hub_invoked : words[1] is hub, or a shell alias whose command is hub (alias git=hub).
_hub_invoked() {
  local -a alias_words
  local w=$words[1]
  [[ ${w:t} == hub ]] && return 0
  alias_words=(${(z)aliases[$w]})
  [[ ${alias_words[1]:t} == hub ]]
}

# _hub_at_command : the word being completed is the command word, found as bin/hub
# finds it: after git's global options, skipping the value of the ones that take one.
_hub_at_command() {
  local i=2
  while (( i < CURRENT )); do
    case $words[i] in
      (-C|-c|--config-env|--git-dir|--work-tree|--namespace|--attr-source|--super-prefix|--shallow-file)
        (( i += 2 )) ;;
      (--version|-v|--help|-h|--exec-path|--html-path|--man-path|--info-path|--list-cmds=*)
        return 1 ;; # git's own command word, or an option git answers by itself
      (-*) (( i++ )) ;;
      (*)  return 1 ;; # the command word is already there
    esac
  done
  (( i == CURRENT )) && [[ $words[CURRENT] != -* ]]
}

# _hub : the completion registered for git, plus, when the command is hub, hub's
# commands where the command word goes and their arguments after it.
_hub() {
  local -a hub_words=("${words[@]}") defined w=($words[1])
  local hub_current=$CURRENT service=git cmd ret=1 i=2
  if _hub_invoked; then
    # _git does not know --noop (hub's own option), nor that --attr-source and --shallow-file
    # take a value: those go, with their values, so that it finds the command word bin/hub does.
    while (( i < CURRENT )); do
      case $words[i] in
        (--noop) (( i++ )); continue ;;
        (--attr-source|--shallow-file)
          (( i + 1 < CURRENT )) || break # its value is being completed
          (( i += 2 )); continue ;;
        (-C|-c|--config-env|--git-dir|--work-tree|--namespace|--super-prefix)
          w+=("${(@)words[i,i+1]}"); (( i += 2 )); continue ;; # the value may be the word being completed
        (-*) ;;
        (*) break ;; # the command word
      esac
      w+=("$words[i]"); (( i++ ))
    done
    w+=("${(@)words[i,-1]}") # quoted: the word being completed may be empty
    words=("${w[@]}") CURRENT=$(( CURRENT - $#hub_words + $#w ))
    # _git completes the arguments of CMD with _git-CMD. hub's are defined for this one
    # completion only, so that plain git, and a _git-CMD of the user's, never see them.
    for cmd in ${(k)_hub_subcommands} ${(k)_hub_options} sync; do
      (( $+functions[_git-$cmd] )) && continue
      functions[_git-$cmd]='_hub_arguments "$@"'
      defined+=(_git-$cmd)
    done
    $_hub_git "$@" && ret=0
    (( $#defined )) && unfunction $defined
    words=("${hub_words[@]}") CURRENT=$hub_current
    if _hub_at_command; then
      _describe -t hub-commands 'hub command' _hub_commands && ret=0
    fi
  else
    $_hub_git "$@" && ret=0
  fi
  return ret
}

# The completion git had before this file wrapped it (normally _git): what _hub calls.
typeset -g _hub_git
[[ -n $_hub_git && $_hub_git != _hub ]] || _hub_git=${_comps[git]:-_git}
[[ $_hub_git != _hub ]] || _hub_git=_git

# `hub <TAB>` is completed in the hub context, as is `git <TAB>` when git is an alias for
# hub: the user commands registered for git apply there too.
if [[ -z "$(zstyle -L ':completion:\*:\*:hub:\*' user-commands)" ]]; then
  zstyle -e ':completion:*:*:hub:*' user-commands \
    'zstyle -a ":completion:${curcontext/:hub:/:git:}:" user-commands reply'
fi

if (( $+functions[compdef] )); then
  compdef _hub hub
  [[ -o complete_aliases ]] && compdef _hub git
fi

# Autoloaded from $fpath as _hub: finish this first completion.
if [[ ${funcstack[1]} == _hub && ${zsh_eval_context[-1]} != file ]]; then
  _hub "$@"
fi
