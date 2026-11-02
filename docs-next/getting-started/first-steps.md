---
title: First steps with hub
description: A guided tour from cloning a repository to a merged pull request, one command at a time.
---

# First steps with hub

This tour is for a new user who has [installed hub](install.md) and followed
the steps to [make git run hub](alias.md). It follows one change to
rails/rails from the clone to the merged pull request, and shows the commands
hub runs with git and the GitHub CLI (gh) at each step. With the alias, `git`
and `hub` are the same command, so the examples write `git`. In the examples,
`LOGIN` stands for your GitHub login, a `# =>` line is a command that hub
runs, and a `text` block is output.

## Clone a repository by its name

Give [hub clone](../commands/clone.md) an `OWNER/REPO` shorthand. hub turns
it into the clone URL on GitHub and runs git clone. A name without an owner is
one of your own repositories. git's clone options go to git untouched. `-p`
clones over ssh for this one clone.

```sh
git clone rails/rails
# => git clone https://github.com/rails/rails.git
git clone -p dotfiles --depth 1
# => git clone git@github.com:LOGIN/dotfiles.git --depth 1
cd rails
```

hub writes https URLs, in a clone and in the remotes it adds. To get ssh URLs
every time, set gh's `git_protocol`:

```sh
gh config set git_protocol ssh
```

## Fork the project and add your fork as a remote

[hub fork](../commands/fork.md) forks the project (the GitHub repository
that `origin` points to) under your account through GitHub's fork API, and
adds the fork as a remote named after your login.

```sh
git fork
# => gh api --hostname github.com --method POST repos/rails/rails/forks --jq .full_name
# => git remote add -- LOGIN https://github.com/LOGIN/rails.git
git fetch LOGIN
```

hub fetches nothing, because GitHub can take a moment to make the fork. Fetch
the new remote yourself, as above. `origin` still points to the project,
rails/rails. hub refuses a remote name that is already taken.

## Make a branch, push it and open a pull request

Make the branch and the commit with plain git, which goes to git untouched.
Then [hub pull-request](../commands/pull-request.md) opens a pull request for
the current branch with gh. `-p` pushes the branch first, and `-m` gives the
title. A new branch pushes to your fork, because the fork is the one remote of
your login (see
[Find where a branch pushes](../guide/project-and-remotes.md#find-where-a-branch-pushes)).

```sh
git switch -c fix-typo
git commit -a -m 'Fix a typo in the guides'
git pull-request -p -m 'Fix a typo in the guides'
# => git push --set-upstream -- LOGIN HEAD:refs/heads/fix-typo
# => gh pr create --repo github.com/rails/rails --head LOGIN:fix-typo --title Fix\ a\ typo\ in\ the\ guides --body ''
```

gh prints the URL of the new pull request. Without `-p`, the branch must be
on your fork already, and hub stops if it is not. Instead of the
`git pull-request` line above, give a body paragraph with a second `-m`, open
the new pull request in the browser with `-o`, or copy its URL with `-c`:

```sh
git pull-request -m 'Fix a typo in the guides' -m 'The routing guide spelled "resource" twice.'
git pull-request -p -o -m 'Fix a typo in the guides'
git pull-request -c -m 'Fix a typo in the guides'
```

For `-o` and `-c`, hub looks up the new pull request by its branch after gh
creates it. `-c` uses the first of `pbcopy`, `wl-copy` and `xclip` that is
installed, and [Browser and clipboard](../guide/browser-and-clipboard.md)
says which browser `-o` opens.

## Watch the checks

[hub ci-status](../commands/ci-status.md) prints GitHub's combined verdict
on the checks and commit statuses of the current commit in the project. `-v`
prints one line per check instead: the state, the name and the URL, failures
first. A commit or branch name asks about that commit instead of `HEAD`.

```sh
git ci-status
```

```text
success
```

```sh
git ci-status -v main
```

```text
failure	lint	https://github.com/rails/rails/actions/runs/1/job/2
success	build	https://github.com/rails/rails/actions/runs/1/job/3
```

The exit status follows the verdict: 0 for success, 1 for failure or error, 2
for pending and 3 for no status. For a colored view, use `gh pr checks`.

## Check out someone else's pull request

Give [hub checkout](../commands/checkout.md) the URL of any page of a pull
request. hub hands it to `gh pr checkout`, which fetches the pull request and
checks it out in a local branch, here named `review`.

```sh
git checkout https://github.com/rails/rails/pull/42 review
# => gh pr checkout https://github.com/rails/rails/pull/42 -b review
```

Every other checkout is plain git, so `git checkout main` still switches
branches.

## Fetch a contributor's copy

[hub fetch](../commands/fetch.md) with a GitHub login that is not a remote
adds that user's copy of the project as a remote, then fetches it. hub checks
with gh that the copy exists first. A comma-separated list adds every missing
user and fetches them all at once.

```sh
git fetch USER1
# => git remote add USER1 https://github.com/USER1/rails.git
# => git fetch USER1
git fetch USER1,USER2
# => git remote add USER1 https://github.com/USER1/rails.git
# => git remote add USER2 https://github.com/USER2/rails.git
# => git fetch --multiple USER1 USER2
```

## Open the repository and the compare page

Switch back to your branch first. [hub browse](../commands/browse.md) opens
the project on GitHub. On a pushed branch other than the default branch, it
opens that branch in the repository the branch pushes to, here your fork. A
subpage after `--` opens that page of the project.

```sh
git switch fix-typo
git browse
# => open https://github.com/LOGIN/rails/tree/fix-typo
git browse -- pulls
# => open https://github.com/rails/rails/pulls
```

[hub compare](../commands/compare.md) opens the compare page for the current
branch. `-u` prints the URL instead, and `-b` sets the base. A two-dot range
becomes GitHub's three-dot form.

```sh
git compare -u
```

```text
https://github.com/rails/rails/compare/LOGIN:fix-typo
```

```sh
git compare -u -b 7-2-stable
```

```text
https://github.com/rails/rails/compare/7-2-stable...LOGIN:fix-typo
```

```sh
git compare v7.1.0..v7.2.0
# => open https://github.com/rails/rails/compare/v7.1.0...v7.2.0
```

## Keep branches in step after merges

When a maintainer merges your pull request and deletes the branch, run
[hub sync](../commands/sync.md). It fetches the project's remote (`upstream`
before `github` and `origin`) and every remote a local branch tracks. Then it
fast-forwards branches that are behind. It deletes a branch when its upstream
branch is gone and the project's default branch contains it.

```sh
git sync
```

```text
Updated branch main (was 1a2b3c4).
Deleted branch fix-typo (was 5d6e7f8).
```

hub switches you to the default branch before it deletes the current branch.
A branch with unpushed commits stays, with a warning. sync treats a
squash-merged branch as not merged and leaves it in place. Delete it with git:

```sh
git branch -D BRANCH
```

## See what hub would run

Put `--noop` before the command. hub prints the git and gh commands that
change something instead of running them. Read-only lookups still run, except
one that needs what a printed command would create. Run these on `fix-typo`,
before the sync above:

```sh
git --noop sync
# => git fetch --prune --quiet -- origin
# => git fetch --prune --quiet -- LOGIN
git --noop pull-request -c -m 'Fix a typo in the guides'
# => gh pr create --repo github.com/rails/rails --head LOGIN:fix-typo --title Fix\ a\ typo\ in\ the\ guides --body ''
# => gh api --hostname github.com repos/rails/rails/pulls\?head=LOGIN:fix-typo\&state=open --jq .\[0\].html_url
# => copy URL
```

The new pull request does not exist under `--noop`. So hub prints the lookup
of its URL instead of running it. `copy URL` stands for the copy that `-c`
would make, and `open URL` for the browser that `-o` would open. hub quotes
the printed lines so that you can paste them back into the shell.

## See also

- [How hub works](../guide/how-hub-works.md): which commands hub handles and
  which go to git or gh.
- [Repositories and URLs](../guide/repositories-and-urls.md): every shorthand
  hub accepts.
- [hub commands](../commands/README.md): the manual of every command.
- [Coming from the original hub](../compatibility/README.md): what changed
  since the original hub (mislav/hub 2.x).
- [hub manuals](https://brc-dd.github.io/hub/): this hub's manual pages.
- [The original hub's manuals](https://hub.github.com/): the manual pages of
  the original hub.
