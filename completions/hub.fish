# fish completion for hub, and for git when it is an alias for hub (the alias
# wraps hub): fish's git completion plus hub's commands. Install it into a
# vendor_completions.d directory (make install does) or ~/.config/fish/completions.

complete -c hub --wraps git

# __hub_needs_command : the command word is being completed, found as bin/hub finds
# it: after git's global options, skipping the value of the ones that take one.
function __hub_needs_command
    set -l tokens (commandline -opc)
    set -e tokens[1]
    while set -q tokens[1]
        switch $tokens[1]
            case -C -c --config-env --git-dir --work-tree --namespace --attr-source --super-prefix --shallow-file
                set -e tokens[1]
                set -q tokens[1]; or return 1 # its value is being completed
            case --version -v --help -h --exec-path --html-path --man-path --info-path '--list-cmds=*'
                return 1 # git's own command word, or an option git answers by itself
            case '-*'
            case '*'
                return 1 # the command word is already there
        end
        set -e tokens[1]
    end
    return 0
end

complete -c hub -f -n __hub_needs_command -a alias -d 'Show how to make `git` run hub'
complete -c hub -f -n __hub_needs_command -a api -d 'Make an authenticated GitHub API request (gh api)'
complete -c hub -f -n __hub_needs_command -a browse -d 'Open a GitHub repository page in the browser'
complete -c hub -f -n __hub_needs_command -a ci-status -d 'Show the CI status of a commit'
complete -c hub -f -n __hub_needs_command -a compare -d 'Open a GitHub compare page for a branch or a range'
complete -c hub -f -n __hub_needs_command -a create -d 'Create a GitHub repository for the current project and add it as a remote'
complete -c hub -f -n __hub_needs_command -a delete -d 'Delete a repository on GitHub'
complete -c hub -f -n __hub_needs_command -a fork -d 'Fork the current repository on GitHub and add the fork as a remote'
complete -c hub -f -n __hub_needs_command -a gist -d 'Create and view gists (gh gist)'
complete -c hub -f -n __hub_needs_command -a issue -d 'List, view, create and edit issues (gh issue)'
complete -c hub -f -n __hub_needs_command -a pr -d 'List, view, check out and merge pull requests (gh pr)'
complete -c hub -f -n __hub_needs_command -a pull-request -d "Open a pull request (gh pr create, with hub's options)"
complete -c hub -f -n __hub_needs_command -a release -d 'List, view, create, edit and download releases (gh release)'
complete -c hub -f -n __hub_needs_command -a sync -d 'Fetch a remote and fast-forward or delete local branches to match it'

set -l __hub_gist list view show create edit delete clone rename
set -l __hub_issue list status view show create close reopen comment edit transfer delete develop lock unlock pin unpin
set -l __hub_pr list status view show create checkout diff checks comment review merge edit close reopen ready lock unlock revert update-branch
set -l __hub_release list view show create edit download upload delete delete-asset verify verify-asset
complete -c hub -f -n "__fish_seen_subcommand_from gist; and not __fish_seen_subcommand_from $__hub_gist" -a "$__hub_gist"
complete -c hub -f -n "__fish_seen_subcommand_from issue; and not __fish_seen_subcommand_from $__hub_issue" -a "$__hub_issue"
complete -c hub -f -n "__fish_seen_subcommand_from pr; and not __fish_seen_subcommand_from $__hub_pr" -a "$__hub_pr"
complete -c hub -f -n "__fish_seen_subcommand_from release; and not __fish_seen_subcommand_from $__hub_release" -a "$__hub_release"

complete -c hub -f -n '__fish_seen_subcommand_from alias' -s s -d 'Print only the code to evaluate'
complete -c hub -f -n '__fish_seen_subcommand_from alias' -a 'bash zsh sh ksh dash fish csh tcsh'
complete -c hub -f -n '__fish_seen_subcommand_from sync' -l color -d 'Color the output (always, never or auto)'
