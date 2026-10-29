# fish completion for hub: hub completes like git, plus hub's own commands.
# It covers `hub`, and `git` too when git is an alias for hub
# (hub alias -s fish | source): fish's alias turns git into a function that
# wraps hub, so git picks up these completions as well.
#
# Install: link or copy this file to ~/.config/fish/completions/hub.fish, or
# into a vendor_completions.d directory (make install does that).
#
# The commands below are hub's commands that git does not have, as listed by
# the "# Summary:" lines of lib/hub/{cmd,ext}/*.sh. The git commands hub
# extends (clone, push, checkout, ...) are completed by fish's git completion.

complete -c hub --wraps git

complete -c hub -f -n __fish_use_subcommand -a alias -d 'Show how to make `git` run hub'
complete -c hub -f -n __fish_use_subcommand -a api -d 'Make an authenticated GitHub API request (gh api)'
complete -c hub -f -n __fish_use_subcommand -a browse -d 'Open a GitHub repository page in the browser'
complete -c hub -f -n __fish_use_subcommand -a ci-status -d 'Show the CI status of a commit'
complete -c hub -f -n __fish_use_subcommand -a compare -d 'Open a GitHub compare page for a branch or a range'
complete -c hub -f -n __fish_use_subcommand -a create -d 'Create a GitHub repository for the current project and add it as a remote'
complete -c hub -f -n __fish_use_subcommand -a delete -d 'Delete a repository on GitHub'
complete -c hub -f -n __fish_use_subcommand -a fork -d 'Fork the current repository on GitHub and add the fork as a remote'
complete -c hub -f -n __fish_use_subcommand -a gist -d 'Create and view gists (gh gist)'
complete -c hub -f -n __fish_use_subcommand -a issue -d 'List, view, create and update issues (gh issue)'
complete -c hub -f -n __fish_use_subcommand -a pr -d 'List, view, check out and merge pull requests (gh pr)'
complete -c hub -f -n __fish_use_subcommand -a pull-request -d "Open a pull request (gh pr create, with hub's options)"
complete -c hub -f -n __fish_use_subcommand -a release -d 'List, view, create, edit and download releases (gh release)'
complete -c hub -f -n __fish_use_subcommand -a sync -d 'Fetch a remote and fast-forward or delete local branches to match it'

# Subcommands of the commands that have them.
set -l __hub_gist list view show create edit delete clone rename
set -l __hub_issue list status view show create update labels close reopen comment edit transfer delete develop lock unlock pin unpin
set -l __hub_pr list status view show create checkout diff checks comment review merge edit close reopen ready lock unlock revert update-branch
set -l __hub_release list view show create edit download upload delete delete-asset verify verify-asset
complete -c hub -f -n "__fish_seen_subcommand_from gist; and not __fish_seen_subcommand_from $__hub_gist" -a "$__hub_gist"
complete -c hub -f -n "__fish_seen_subcommand_from issue; and not __fish_seen_subcommand_from $__hub_issue" -a "$__hub_issue"
complete -c hub -f -n "__fish_seen_subcommand_from pr; and not __fish_seen_subcommand_from $__hub_pr" -a "$__hub_pr"
complete -c hub -f -n "__fish_seen_subcommand_from release; and not __fish_seen_subcommand_from $__hub_release" -a "$__hub_release"

# hub alias [-s] [SHELL]
complete -c hub -f -n '__fish_seen_subcommand_from alias' -s s -d 'Print only the code to evaluate'
complete -c hub -f -n '__fish_seen_subcommand_from alias' -a 'bash zsh sh ksh dash fish csh tcsh'
