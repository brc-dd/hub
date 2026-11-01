# Summary: fish completion for hub, and for git when git is an alias for hub.
# Usage: install as hub.fish in a vendor_completions.d directory
#
# git's completion, plus hub's commands where the command word goes and the options of hub's own
# commands. fish's alias git=hub makes git a function that wraps hub, so git gets them too. make
# install links this file into a vendor_completions.d directory.

complete -c hub --wraps git

# __hub_command : the command word before the cursor, empty at the command position, or failure.
function __hub_command
    set -l tokens (commandline -opc)
    set -e tokens[1]
    while set -q tokens[1]
        switch $tokens[1]
            case -C -c --config-env --git-dir --work-tree --namespace --attr-source \
                --super-prefix --shallow-file
                # The cursor is on the option's value.
                set -q tokens[2]; or return 1
                set -e tokens[1]
            case --version -v --help -h --exec-path --html-path --man-path --info-path \
                '--list-cmds=*'
                # git answers these by itself: no command follows.
                return 1
            case '-*'
            case '*'
                echo $tokens[1]
                return 0
        end
        set -e tokens[1]
    end
    return 0
end

# __hub_needs_command : succeeds at the command position.
function __hub_needs_command
    set -l cmd (__hub_command); or return
    test -z "$cmd"
end

# __hub_using CMD : succeeds when the command word is CMD.
function __hub_using
    set -l cmd (__hub_command); and test "$cmd" = $argv[1]
end

complete -c hub -n __hub_needs_command -a alias -d 'Show how to make git run hub'
complete -c hub -n __hub_needs_command -a am \
    -d 'Apply the commits of a GitHub pull request, commit or comparison'
complete -c hub -n __hub_needs_command -a api \
    -d 'Make an authenticated GitHub API request (gh api)'
complete -c hub -n __hub_needs_command -a apply \
    -d 'Apply the changes of a GitHub pull request, commit or comparison'
complete -c hub -n __hub_needs_command -a browse -d 'Open a GitHub repository in the web browser'
complete -c hub -n __hub_needs_command -a checkout \
    -d 'Check out a pull request, or run git checkout'
complete -c hub -n __hub_needs_command -a cherry-pick -d 'Cherry-pick a commit from its GitHub URL'
complete -c hub -n __hub_needs_command -a ci-status -d 'Show the CI status of a commit'
complete -c hub -n __hub_needs_command -a clone \
    -d 'Clone a GitHub repository by its [OWNER/]REPO name'
complete -c hub -n __hub_needs_command -a compare \
    -d 'Open a GitHub compare page for a branch or a range'
complete -c hub -n __hub_needs_command -a create \
    -d 'Create a GitHub repository for this repository and add it as a remote'
complete -c hub -n __hub_needs_command -a delete -d 'Delete a repository on GitHub'
complete -c hub -n __hub_needs_command -a fetch \
    -d "Fetch from GitHub users' copies of the project, adding their remotes"
complete -c hub -n __hub_needs_command -a fork \
    -d 'Fork the project on GitHub and add the fork as a remote'
complete -c hub -n __hub_needs_command -a gist -d 'List, view, create and edit gists (gh gist)'
complete -c hub -n __hub_needs_command -a help -d "Show git's help and hub's commands"
complete -c hub -n __hub_needs_command -a issue -d 'List, view, create and edit issues (gh issue)'
complete -c hub -n __hub_needs_command -a merge \
    -d "Merge a pull request locally, with the message GitHub's merge button uses"
complete -c hub -n __hub_needs_command -a pr -d 'List, view and check out pull requests (gh pr)'
complete -c hub -n __hub_needs_command -a pull-request \
    -d 'Open a pull request for the current branch'
complete -c hub -n __hub_needs_command -a push -d 'Push to several remotes at once'
complete -c hub -n __hub_needs_command -a release \
    -d 'List, view, create, edit, upload and download releases (gh release)'
complete -c hub -n __hub_needs_command -a remote \
    -d 'Add or change a remote by its GitHub OWNER[/REPO] name'
complete -c hub -n __hub_needs_command -a sync \
    -d 'Fetch and fast-forward or delete local branches to match the remotes'
complete -c hub -n __hub_needs_command -a version -d 'Show the versions of hub, git and gh'

complete -c hub -n '__hub_using alias' -s s -d 'Print only the alias, for eval'

complete -c hub -n '__hub_using browse' -s u -l url -d 'Print the URL instead of opening it'
complete -c hub -n '__hub_using browse' -s c -l copy -d 'Copy the URL to the clipboard'

complete -c hub -n '__hub_using ci-status' -s v -l verbose -d 'Print every check'

complete -c hub -n '__hub_using compare' -s b -l base -r -d 'Compare with BASE'
complete -c hub -n '__hub_using compare' -s u -l url -d 'Print the URL instead of opening it'
complete -c hub -n '__hub_using compare' -s c -l copy -d 'Copy the URL to the clipboard'

complete -c hub -n '__hub_using create' -s p -l private -d 'Make the repository private'
complete -c hub -n '__hub_using create' -l public -d 'Make it public'
complete -c hub -n '__hub_using create' -l internal -d 'Make it visible to its organization only'
complete -c hub -n '__hub_using create' -s d -l description -r -d 'The description'
complete -c hub -n '__hub_using create' -s h -l homepage -r -d 'The home page URL'
complete -c hub -n '__hub_using create' -l remote-name -r -d 'Name the remote instead of origin'
complete -c hub -n '__hub_using create' -l push -d 'Push the current branch and track it'
complete -c hub -n '__hub_using create' -s o -l browse -d 'Open the repository in the browser'
complete -c hub -n '__hub_using create' -s c -l copy -d 'Copy its URL'

complete -c hub -n '__hub_using delete' -s y -l yes -d 'Delete without asking'

complete -c hub -n '__hub_using fork' -l no-remote -d 'Fork without adding a remote'
complete -c hub -n '__hub_using fork' -l remote-name -r -d 'Name the new remote'
complete -c hub -n '__hub_using fork' -l org -r -d 'Fork into an organization'
complete -c hub -n '__hub_using fork' -l fork-name -r -d 'Name the fork on GitHub'
complete -c hub -n '__hub_using fork' -l default-branch-only -d 'Copy only the default branch'

complete -c hub -n '__hub_using pull-request' -s m -l message -r -d 'A paragraph of the message'
complete -c hub -n '__hub_using pull-request' -s F -l file -r -d 'Read the message from a file'
complete -c hub -n '__hub_using pull-request' -s e -l edit -d 'Write the message in an editor'
complete -c hub -n '__hub_using pull-request' -l no-edit \
    -d 'Take the message from the first commit'
complete -c hub -n '__hub_using pull-request' -s b -l base -r -d 'The branch to merge into'
complete -c hub -n '__hub_using pull-request' -s h -l head -r -d 'The branch with the changes'
complete -c hub -n '__hub_using pull-request' -s p -l push -d 'Push the current branch first'
complete -c hub -n '__hub_using pull-request' -s f -l force \
    -d 'Skip the check that the branch is pushed'
complete -c hub -n '__hub_using pull-request' -s d -l draft -d 'Open it as a draft'
complete -c hub -n '__hub_using pull-request' -s r -l reviewer -r -d 'Request reviews'
complete -c hub -n '__hub_using pull-request' -s a -l assign -r -d 'Assign users'
complete -c hub -n '__hub_using pull-request' -s M -l milestone -r -d 'Add it to a milestone'
complete -c hub -n '__hub_using pull-request' -s l -l labels -r -d 'Add labels'
complete -c hub -n '__hub_using pull-request' -l no-maintainer-edits \
    -d 'Do not let maintainers push to the head branch'
complete -c hub -n '__hub_using pull-request' -s o -l browse -d 'Open it in the browser'
complete -c hub -n '__hub_using pull-request' -s c -l copy -d 'Copy its URL'

complete -c hub -n '__hub_using version' -l build-options -d "Also print git's build options"
