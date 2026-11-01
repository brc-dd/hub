#compdef hub git
# Summary: zsh completion for hub, and for git when git is an alias for hub.
# Usage: install as _hub in a directory on $fpath, or source it after compinit
#
# The completion registered for git (normally _git), plus hub's commands where the command word
# goes and the options of hub's own commands, when the command is hub or a shell alias for it.
# Plain git completes as before. It completes git too, for setopt complete_aliases, where zsh
# completes git aliased to hub as git. make install links it as _hub into a site-functions
# directory.

typeset -ga _hub_commands
_hub_commands=(
  'alias:Show how to make git run hub'
  'am:Apply the commits of a GitHub pull request, commit or comparison URL'
  'api:Make an authenticated GitHub API request (gh api)'
  'apply:Apply the changes of a GitHub pull request, commit or comparison'
  'browse:Open a GitHub repository in the web browser'
  'checkout:Check out a pull request, or run git checkout'
  'cherry-pick:Cherry-pick a commit from its GitHub URL'
  'ci-status:Show the CI status of a commit'
  'clone:Clone a GitHub repository by its [OWNER/]REPO name'
  'compare:Open a GitHub compare page for a branch or a range'
  'create:Create a GitHub repository for this repository and add it as a remote'
  'delete:Delete a repository on GitHub'
  "fetch:Fetch from GitHub users' copies of the project, adding their remotes"
  'fork:Fork the project on GitHub and add the fork as a remote'
  'gist:List, view, create and edit gists (gh gist)'
  "help:Show git's help and hub's commands"
  'issue:List, view, create and edit issues (gh issue)'
  "merge:Merge a pull request locally, with the message GitHub's merge button uses"
  'pr:List, view and check out pull requests (gh pr)'
  'pull-request:Open a pull request for the current branch'
  'push:Push to several remotes at once'
  'release:List, view, create, edit, upload and download releases (gh release)'
  'remote:Add or change a remote by its GitHub OWNER[/REPO] name'
  'sync:Fetch and fast-forward or delete local branches to match the remotes'
  'version:Show the versions of hub, git and gh'
)
# The commands git has too: _git offers them, and completes them with its own _git-CMD, which
# _git defines on its first run only when no _git-CMD exists yet.
typeset -ga _hub_git_commands
_hub_git_commands=(am apply checkout cherry-pick clone fetch help merge push remote version)

# _hub_options CMD : sets reply to the options of hub's own command CMD, as OPTION:DESCRIPTION.
_hub_options() {
  case $1 in
    (alias) reply=('-s:Print only the alias, for eval') ;;
    (browse)
      reply=({-u,--url}':Print the URL instead of opening it'
        {-c,--copy}':Copy the URL to the clipboard') ;;
    (ci-status) reply=({-v,--verbose}':Print every check') ;;
    (compare)
      reply=({-b,--base}':Compare with BASE' {-u,--url}':Print the URL instead of opening it'
        {-c,--copy}':Copy the URL to the clipboard') ;;
    (create)
      reply=({-p,--private}':Make the repository private' '--public:Make it public'
        '--internal:Make it visible to its organization only'
        {-d,--description}':The description' {-h,--homepage}':The home page URL'
        '--remote-name:Name the remote instead of origin'
        '--push:Push the current branch and track it'
        {-o,--browse}':Open the repository in the browser' {-c,--copy}':Copy its URL') ;;
    (delete) reply=({-y,--yes}':Delete without asking') ;;
    (fork)
      reply=('--no-remote:Fork without adding a remote' '--remote-name:Name the new remote'
        '--org:Fork into an organization' '--fork-name:Name the fork on GitHub'
        '--default-branch-only:Copy only the default branch') ;;
    (pull-request)
      reply=({-m,--message}':A paragraph of the message'
        {-F,--file}':Read the message from a file' {-e,--edit}':Write the message in an editor'
        '--no-edit:Take the message from the first commit'
        {-b,--base}':The branch to merge into' {-h,--head}':The branch with the changes'
        {-p,--push}':Push the current branch first'
        {-f,--force}':Skip the check that the branch is pushed'
        {-d,--draft}':Open it as a draft' {-r,--reviewer}':Request reviews'
        {-a,--assign}':Assign users' {-M,--milestone}':Add it to a milestone'
        {-l,--labels}':Add labels'
        '--no-maintainer-edits:Do not let maintainers push to the head branch'
        {-o,--browse}':Open it in the browser' {-c,--copy}':Copy its URL') ;;
    (*) return 1 ;;
  esac
}

# _hub_invoked : words[1] is hub, or a shell alias whose command is hub.
_hub_invoked() {
  local -a alias_words
  [[ ${words[1]:t} == hub ]] && return 0
  alias_words=(${(z)aliases[$words[1]]})
  [[ ${alias_words[1]:t} == hub ]]
}

# _hub_complete_options CMD : the options of hub's command CMD, or what _default completes.
_hub_complete_options() {
  local -a reply
  if [[ $PREFIX == -* ]] && _hub_options $1; then
    _describe -t options option reply
  else
    _default
  fi
}

# _hub : the completion of hub, and of git through the completer git had.
_hub() {
  local -a saved_words kept defined reply hub_only
  local saved_current=$CURRENT service=git cmd i=2 at_command=1 ret=1
  if ! _hub_invoked; then
    $_hub_git "$@"
    return
  fi
  saved_words=("${words[@]}") kept=("$words[1]")
  while (( i < CURRENT )); do
    case $words[i] in
      # hub's own --noop, and options _git does not know take a value, go with their value.
      (--noop) (( i++ )); continue ;;
      (--attr-source|--shallow-file)
        (( i + 1 < CURRENT )) || return 1
        (( i += 2 )); continue ;;
      (-C|-c|--config-env|--git-dir|--work-tree|--namespace|--super-prefix)
        kept+=("${(@)words[i,i+1]}"); (( i += 2 )); continue ;;
      (-*) ;;
      (*) at_command=0; break ;;
    esac
    case $words[i] in
      (--version|-v|--help|-h|--exec-path|--html-path|--man-path|--info-path|--list-cmds=*)
        at_command=0 ;;
    esac
    kept+=("$words[i]"); (( i++ ))
  done
  (( i <= CURRENT )) || at_command=0
  kept+=("${(@)words[i,-1]}")
  words=("${kept[@]}") CURRENT=$(( CURRENT - $#saved_words + $#kept ))
  # _git completes the arguments of CMD with _git-CMD: hub's are defined for this completion
  # only, so plain git and a _git-CMD of yours never see them.
  hub_only=(${_hub_commands:#(${(~j:|:)_hub_git_commands}):*})
  for cmd in ${hub_only%%:*}; do
    (( ! $+functions[_git-$cmd] )) && _hub_options $cmd || continue
    functions[_git-$cmd]="_hub_complete_options $cmd"
    defined+=(_git-$cmd)
  done
  $_hub_git "$@" && ret=0
  (( $#defined )) && unfunction $defined
  words=("${saved_words[@]}") CURRENT=$saved_current
  if (( at_command )) && [[ $PREFIX != -* ]]; then
    _describe -t hub-commands 'hub command' hub_only && ret=0
  fi
  return ret
}

# The completer git had before this file was loaded, never _hub itself.
typeset -g _hub_git
[[ -n $_hub_git && $_hub_git != _hub ]] || _hub_git=${_comps[git]:-_git}
[[ $_hub_git != _hub ]] || _hub_git=_git

(( ! $+functions[compdef] )) || compdef _hub hub git

# Autoloaded from $fpath as _hub, this file's body runs at the first completion: finish it.
if [[ ${funcstack[1]} == _hub && ${zsh_eval_context[-1]} != file ]]; then
  _hub "$@"
fi
