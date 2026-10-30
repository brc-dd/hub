#compdef hub
# zsh completion for hub, and for git when it is an alias for hub: zsh's _git
# plus hub's commands. Install it as _hub in a directory on $fpath (make install
# does), or, with `setopt complete_aliases`, source it after compinit.

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
  'issue:list, view, create and update issues (gh issue)'
  'pr:list, view, check out and merge pull requests (gh pr)'
  "pull-request:open a pull request (gh pr create, with hub's options)"
  'release:list, view, create, edit and download releases (gh release)'
  'sync:fetch a remote and fast-forward or delete local branches to match it'
)
zstyle ':completion:*:*:hub:*' user-commands $_hub_commands
# With complete_aliases, the alias git=hub completes as git: list hub's commands there too.
zstyle -e ':completion:*:*:git:*' user-commands \
  'if [[ $aliases[git] == hub(| *) ]]; then reply=($_hub_commands); else reply=(); fi'

# The arguments of hub's commands: _git completes `git CMD ...` with _git-CMD.
typeset -gA _hub_subcommands _hub_options
_hub_subcommands=(
  gist    'list view show create edit delete clone rename'
  issue   'list status view show create update labels close reopen comment edit transfer delete develop lock unlock pin unpin'
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
  pull-request '-m --message -F --file -e --edit --no-edit -b --base -h --head -d --draft -r --reviewer -a --assign -M --milestone -l --labels --no-maintainer-edits -p --push -f --force -o --browse -c --copy -i --issue --fill --dry-run'
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

() {
  local cmd
  for cmd in ${(k)_hub_subcommands} ${(k)_hub_options} sync; do
    functions[_git-$cmd]='_hub_arguments "$@"'
  done
}

if (( $+functions[compdef] )); then
  compdef hub=git
fi

# Autoloaded from $fpath as _hub: finish this first completion like git does.
if [[ ${funcstack[1]} == _hub && ${zsh_eval_context[-1]} != file ]]; then
  local service=git
  _git "$@"
fi
