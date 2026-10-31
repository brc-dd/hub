# Changelog

All notable changes to hub are recorded here, in the style of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). For each release,
`script/bump` moves the notes under Unreleased to a `## vX.Y.Z — YYYY-MM-DD`
heading.

## Unreleased

A redesign of the wrapper after a consolidated review of hub 0.1.0 and its
five rounds of fixes. The commands are the same; how hub reads a command line
is not.

### Changed

- **git is the only authority on global options.** hub scans a command line
  only to find the command word. When the word is one of hub's commands, hub
  re-enters itself through a git alias (`git GLOBALS -c alias.hubrun=... hubrun
  ...`), so `-C`, `-c`, `--config-env`, `--git-dir`, `--work-tree`, `--bare`,
  `--namespace`, `--no-replace-objects` and the rest mean exactly what they
  mean to git, for hub's own git commands and for the git commands gh runs.
  Anything else, including an unknown option, an empty command word, a missing
  option value and the immediate options (`--exec-path`, `--html-path`,
  `--list-cmds=`), is `exec git "$@"`. `--noop` prints the global options with
  every command.
- **Every command is one of three kinds, with one rule each.** hub-owned
  commands (`pull-request`, `browse`, `compare`, `create`, `fork`, `delete`,
  `ci-status`, `sync`, `alias`) have a closed grammar: option clusters and
  attached values work, unknown options are errors, flags never take values.
  gh-backed commands (`pr`, `issue`, `release`, `gist`, `api`) map only the
  subcommand names gh lacks (`show` to `view`, none to `list`, found as gh
  itself finds the word) and hand everything else to gh unchanged. git commands
  hub extends (`clone`, `remote`, `fetch`, `push`, `checkout`, `merge`, `am`,
  `apply`, `cherry-pick`) read git's options as the installed git does, only
  to find their one shorthand operand; everything else goes to git as
  written, and nothing after `--` is interpreted.
- **Old hub option spellings for gh-backed commands are no longer translated**:
  `issue update`, `issue labels`, `-m`/`-F` as title and body, `release -a`,
  `-t REF`, `release download -i`, `gist --public`/`-o`, `pr checkout N BRANCH`,
  `api -t`/`--cache N`. gh's own options apply; each manual names the gh
  spelling. `hub pr`, `hub issue`, `hub release` and `hub gist` alone list.
- **Shorthand precedence follows git.** An exact existing remote or group is
  git's; so is anything git could read as a local source (an existing path, a
  `NAME.git` repository, a `NAME.bundle` for clone); only then is a name a
  GitHub shorthand. Dotted names (`.github`, `mislav.github.io`) expand again;
  a one-operand `remote add NAME` always expands. `clone` no longer takes
  `HOST/OWNER/REPO`: other hosts come from `GH_HOST` or `hub.host`.
- `fetch` accepts options before the names and `--multiple` anywhere (the last
  of `--multiple`/`--no-multiple` counts); a list member that is empty or not a
  login is an error before any remote is added; a remote whose name contains a
  comma is fetched as it is. `push` accepts options before the remote list,
  checks every member before the first push, pushes the current branch as
  `refs/heads/BRANCH` (a tag of the same name cannot make git refuse it), and
  never splits an existing remote, a path or a URL.
- `merge` fetches the pull request into a private ref, with `--no-tags`, and
  merges that commit, takes the last of `--squash`/`--no-squash`, adds
  `--no-ff` only when no fast-forward option was given, and refuses a second
  revision. `cherry-pick`
  resolves every URL or `USER@SHA` operand, prefers a local revision of that
  name, and finds a pull request's commit by id in its history. `am` and
  `apply` download pull-request, commit and compare URLs (also `.patch` and
  `.diff`) through `gh api`.
- `pull-request` has hub's grammar only (`-R`, `--dry-run`, `--fill` and gh
  passthrough are gone): the head is named from where `git push` sends the
  branch (the sole remote, whatever its name, else `origin`, when none is
  configured) and from that remote's push URL; without `-p` the branch must be
  pushed, as the remote-tracking branch the remote's fetch refspecs map its
  name there to shows, which `-f` skips; `-p` checks everything, including
  what gh would refuse without a terminal, and that gh is installed, before
  pushing `HEAD:refs/heads/BRANCH`; under `push.default matching`, `-p` pushes
  only a branch the destination already has, asked with `git ls-remote` as
  `git push` asks; with `remote.*.push` configured, `-p` asks git itself what
  it would send the branch as (`git push --dry-run --porcelain` to the remote)
  and pushes nothing git refuses; the current branch's `gh-merge-base` is the
  default base whenever the pull request is for that branch (no `-h`, `-p`, or
  `-h` naming the repository and branch `git push` sends it to, however
  spelled); `--no-edit` takes the first commit of the head branch (HEAD's when
  the pull request is for the current branch, else its remote-tracking
  branch's, the one the fetch refspecs of a remote that fetches from the head
  repository map it to); `-i` converts an issue through the API with string
  fields; `-o` and `-c` leave gh's prompts alone and look the URL up
  afterwards.
- `create` runs `gh repo create HOST/OWNER/NAME --source=TOP --remote=REMOTE`
  without changing directory, takes `OWNER/NAME`, `HOST/OWNER/NAME` or a URL,
  gains `--push`, and no longer accepts gh's other options. `fork` runs
  `gh repo fork --remote --remote-name` with `GH_REPO` set to the project hub
  resolved, gives the remote the URL hub's protocol chooses, no longer fetches
  or retries, and refuses an existing remote name before gh runs.
- `sync [--color] [REMOTE]` fetches with a fixed refspec, so no fetch or prune
  configuration can touch local branches or tags; every fast-forward and
  deletion is conditional on the state sync observed; branches checked out in
  another work tree and symbolic refs are skipped; the default branch is
  entered with `git switch` and created from the remote when missing.
- `browse` and `compare` take option clusters and attached values, follow the
  repository a branch pushes to (by its push URL), and `compare` writes a
  renamed fork's head as `OWNER:REPO:BRANCH`. `ci-status` keeps a failure it
  has seen whatever a later page does and encodes unresolved refs as one URL
  segment.
- **The installed git says what its options mean.** The git commands hub
  extends ask `git CMD --git-completion-helper-all` for the long options:
  which take a value, and what an abbreviation stands for (`--dep 1`,
  `--bra main`, `--tra main`); short options with values are read in clusters
  (`-qj3`, `-3p`) and an attached optional value stops the cluster (`-Skey`).
  An option git would refuse, unknown or ambiguous, leaves the whole command
  line to git, and so does a value attached to a switch (`--detach=1`,
  `--multiple=oops`); the usage (`git CMD -h`) says which options take an
  attached value, optional (`--recurse-submodules=no`, `--log=5`) or read by
  the option itself (`--file=F`). `merge --file` and `remote add --mirror`,
  which git lists otherwise than it reads them, are the two exceptions hub
  keeps by hand.
- `checkout` runs `gh pr checkout` with `GH_HOST` set to the pull request
  URL's host, so that gh fetches from a remote of that host, and passes
  `--detach` and `--recurse-submodules` as git reads them: the last of an
  option and its negation counts, and `--recurse-submodules=VALUE` takes
  git's booleans (`=no` is `--no-recurse-submodules`). `cherry-pick`
  fetches a pull request's head into a private ref of the run
  (`refs/hub/cherry-pick/N-PID`, deleted at once, also when interrupted), as
  `merge` does, and reads the values of git's revision options (`--grep
  PATTERN`, `--author NAME`, `--since DATE`, ...) as values, never as
  commits. `sync` writes exactly the ref it examined (`git update-ref
  --no-deref`), never another branch through a symbolic ref.
- `fetch` puts `--multiple` first on the command line when it expands a
  list, so a list after `--` or before `--no-multiple` works, and leaves a
  `--multiple` operand that names an existing path to git.
- `pull-request` says why when `git push` would not push the branch as
  configured (`remote.*.push` refspecs that send other branches or exclude
  the destination, no such remote, `push.default nothing`, several upstream
  branches in `branch.*.merge`), refuses without `-p` or `-f` a remote that
  fetches from one repository and pushes to another, passes `head_repo` to
  the API when `-i` converts an issue for a head in another repository, and
  compares owner and repository names without regard to case. `compare`
  refuses the same split remote and asks for the head by name. Both read a
  branch's remote-tracking ref where the remote's fetch refspecs put it, and
  ask for the head or the message when the refspecs map the branch to none.
- `ci-status` marks every page of check runs it reads: a refusal (403, 404,
  422) leaves the statuses to decide only on the first page, and a page that
  fails after an empty one is an error.
- `--noop` prints a gh line as `(cd DIR && gh …)` when `-C` moved hub to
  another directory, as `env GH_HOST=HOST gh …` where hub sets one, and with
  an `env` prefix for what git's other global options put in the environment
  gh inherits: `-c` and `--config-env` as `GIT_CONFIG_PARAMETERS` in git's own
  quoting, after whatever gh inherited there before the command line (carried
  along by reference, unprinted), a `--config-env` value as git's quoting of
  its variable, computed when the line runs, whole, however many lines it
  has, never its value, and
  `--git-dir`, `--work-tree`, `--namespace`, `--bare` and the switches
  (`--no-optional-locks`, `--literal-pathspecs`, ...) as the variables git
  sets. gh's `hosts.yml` is read in flow style too.
- Remote identity: a remote's URL is read as git uses it; SSH hosts are
  resolved through the ssh git would run (`GIT_SSH_COMMAND`, `core.sshCommand`,
  `GIT_SSH`, then `ssh`), with the user and port, so `Match` blocks and
  port-443 aliases work and HTTPS hosts are taken literally; `GH_REPO` must be
  `OWNER/REPO`, `HOST/OWNER/REPO` or a URL. Push destinations follow git's own
  rules: `remote.*.push` as `git push` reads it (a source named in full,
  short or as `HEAD`, a pattern, a matching `:`, a negative refspec against
  the destination), `remote.*.mirror`, then `branch.*.pushRemote`,
  `remote.pushDefault`, `push.default` and the one upstream that `simple` and
  `upstream` need. Branches are handled as full refs, so a tag of the same
  name cannot confuse them.
- Prerequisites: bash 5.3, git 2.41 and gh 2.40 or newer, with the reason for
  each in the README. `make install PREFIX="$HOME/.local"` is the documented
  local install; `make install` refuses to overwrite anything it did not
  create. Completions no longer replace a user's own git completion
  customizations (in bash, a completion registered for `git` keeps completing
  plain git, with its options) and find hub's command word after any global
  option.
  `script/release` names the canonical repository, which origin's fetch URL
  and every push URL must agree on, pushes exact refspecs,
  publishes drafts and resumes after its formula commit; the formula workflow
  picks the highest version.
- The test suite asserts effects with real git: a local github.com of bare
  repositories reached through ssh and https stubs, with no URL rewriting, so
  remotes keep the URLs a user would have. Fixtures are isolated from the
  caller's `GIT_*`, `GH_*` and `HUB_*` environment.
- Docs name bash 5.3 as the tested version; `hub version` also prints gh's
  version and names this hub by its repository, https://github.com/brc-dd/hub.
- The workflows keep readable action versions in the YAML and pin them through
  `.github/workflows/actions.lock` (`gh actions-lock`), verified in CI;
  Dependabot keeps both current.
- MIT license.
- `pull-request -h OWNER/REPO:BRANCH` names a head in a repository not called
  like the base (a renamed fork); without `-p`, `-h OWNER:BRANCH` finds that
  repository through the local branch of the head's name. The base is never
  an assumed `main`: without `-b`, the default branch must come from
  `refs/remotes/REMOTE/HEAD` or gh. `sync` likewise leaves a branch deleted
  upstream alone when the default branch is unknown. The short options of the
  git commands hub extends are read from `git CMD -h`, so an unknown one
  leaves the command line to git. `script/stable-tag` picks the release the
  formula follows, and fails when gh's list may be incomplete.
  `script/release` refuses a stable release from a checkout whose origin is
  not the repository `Formula/hub.rb` names (`REPO`), since the formula
  downloads the tag from there; a pre-release from a fork is allowed and
  leaves the formula alone.

### Fixed

- `-C` could select another repository through `CDPATH`, a symlinked parent or
  `OLDPWD`; `--bare` after `-C` applied to the wrong repository; `-c` settings
  reached git in the wrong order, lost valueless settings and valid
  `GIT_CONFIG_COUNT` values, and did not reach gh's git; `--no-replace-objects`
  and the other safeguards did not reach gh's git; `--list-cmds=` could run a
  following command; an empty command word ran the next argument.
- An HTTPS push destination was approved from an SSH alias of the same name;
  SSH aliases to `ssh.github.com:443` and `Match` remaps were not understood;
  the push preflight asked a different ssh than git uses; an explicit port in
  `GH_HOST` chose the wrong tenant user; malformed `GH_REPO` values were read
  as another host; quoted keys in gh's `hosts.yml` were invisible.
- Push destinations were guessed from fetch refspecs (`remote.*.push`,
  `pushRemote`, `pushDefault` and `push.default` were ignored); ambiguous ref
  names were shortened to the wrong branch; a dangling cached remote HEAD
  supplied a deleted base branch.
- A failed read of a message file or standard input could submit an empty or
  partial message; `--noop` output left a literal tilde unquoted and omitted
  `-C`.
- `pull-request -p` pushed before gh rejected its arguments; a failed browse or
  copy hid the created pull request's URL; `-o`/`-c` captured gh's output and
  broke interactive creation; option clusters smuggled gh options past
  `create`'s checks; `create` changed directory, refused linked work trees for
  its own reasons and opened a malformed URL for a full-URL name; `create` and
  `fork` did remote work before checking the remote name.
- `browse` and `compare` dropped the push destination's repository identity and
  rejected attached values and option clusters; `compare` refused a fork branch
  named like the base's default branch; `ci-status` let a later check-runs
  page error discard a failure it had seen and put unresolved refs into the API
  URL unencoded; a failed browser or clipboard tool returned success.
- `clone` no longer expanded `.github`-style names; `fetch` split an existing
  remote whose name contains a comma, added remotes for invalid list members,
  and let a late `--no-multiple` cancel what hub had already acted on; `remote
  set-url --delete --no-delete` saved a literal shorthand; `push` could turn a
  list member into options; `checkout -b ''` was treated as omitted and a
  `--pathspec-from-file` value as the pull request; `cherry-pick` took a local
  `USER@SHA` revision for GitHub shorthand and could pick a same-prefix local
  branch; `am` and `apply` rejected `.patch` and `.diff` URLs; a `.git`
  directory suffix was doubled in fallback repository names.
- `sync` could restore a file or follow `checkout.defaultRemote` when switching
  to the default branch, prune unmerged local branches through fetch
  configuration, overwrite a branch moved after its snapshot, update branches
  through symbolic aliases, and report a fast-forward that a squash setting had
  not performed; `merge` merged a ref a concurrent fetch could move, mistook a
  clustered `-m` value for the pull request, and ignored `--no-squash` after
  `--squash`.
- gh-backed commands: every mistranslation of old hub options (release assets
  turning into options, mixed issue locators closing in different
  repositories, partial batches, clustered flags, empty option values, lost
  positionals after `--`, `-R` before the subcommand) is gone with the
  translation itself; the arguments reach gh as typed.
- Release tooling: an SSH alias was passed to gh as the API host, the formula
  phase could not resume, `--follow-tags` pushed unrelated tags, the formula
  job took the newest instead of the highest release, drafts counted as
  published, the dry-run help overstated what it checks; `make install`
  reported success when a destination was a directory and broke on prefixes
  with an apostrophe; completions replaced existing git customizations and
  lost hub's commands after separate-valued global options.
- Found by the review of the redesign: `checkout` of a pull request URL let
  gh fetch a same-named repository from another host; `script/release`
  checked the repository origin fetches from and pushed where origin pushes;
  `pull-request -p -h OWNER:BRANCH` compared remote URLs with regard to case,
  so it could push to another repository of OWNER's or refuse a mixed-case
  one; `remote.*.push` refspecs that map other branches made `pull-request
  -p` push a branch git would have left alone; `compare` and `pull-request`
  took a remote-tracking branch fetched from one repository as proof that the
  branch is in the one the remote pushes to; `-i` omitted `head_repo`, which
  the API needs for a head in another repository of the same organization;
  `sync` could move another branch through a symbolic ref created after it
  looked; `ci-status` reported success when a check-runs page failed after an
  empty one; `cherry-pick` read `FETCH_HEAD`, which another fetch could
  replace meanwhile; `fetch --multiple NAME` added a remote for an existing
  path, and a list after `--` or before `--no-multiple` put `--multiple`
  where git could not read it; the values of abbreviated options (`clone
  --bra main`, `fetch --dep 1`, `remote add --tra main`) were taken for
  shorthands; `-Skeyp` and `-Skeym` hid a following URL; a flow-style
  `hosts.yml` hid gh's hosts; `--noop` gh lines left out the directory `-C`
  selected.
- Found by the review of the seventh round: `merge` and `cherry-pick` fetched
  a pull request without `--refmap=`, so a remote's
  `+refs/pull/*/head:refs/heads/pull-*` refspec force-updated the local branch
  it maps to; `pull-request` opened a pull request against an assumed `main`
  when neither the remote nor gh could tell the default branch; `create
  --push` from a bare repository let gh mirror every ref where hub promised
  the current branch; `-h OWNER:BRANCH` without `-p` dropped the head
  repository's name even when the local branch of that name pushes to a
  renamed repository of OWNER's, and nothing could name it (`-h
  OWNER/REPO:BRANCH` now does); an unknown short option (`fetch -z alice`)
  added the remote before git refused the command; a check-runs answer
  without a `check_runs` array counted as an empty page; the formula job
  listed at most 1000 releases and could miss the highest version
  (`script/stable-tag` now fails when the list may be incomplete).
- Found by the review of the eighth round: `pull-request -p` under
  `push.default matching` pushed a branch git would not have (the destination
  had no branch of that name), and pushed before finding out that gh is not
  installed; `-h` naming the current branch skipped its `gh-merge-base`;
  `--no-edit` read HEAD's commits when `-h` named another branch; `checkout
  --recurse-submodules=no` became gh's `--recurse-submodules`, and a value on
  a switch (`checkout --detach=oops`, `fetch --multiple=oops`) was dropped
  instead of left to git, after `fetch` had added the remote; `cherry-pick
  --grep URL` took the pattern for a commit; `--noop` gh lines left out what
  `-c`, `--config-env`, `--git-dir` and the other global options put in the
  environment; `script/release` could publish to a fork and point the
  formula at `brc-dd/hub`.
- Found by the review of the ninth round: `compare` and `pull-request
  --no-edit` read `refs/remotes/REMOTE/BRANCH` by name, which under a custom
  `remote.*.fetch` mapping holds another branch or nothing, so `compare` could
  link an unpushed branch or refuse a pushed one, and `--no-edit` could take
  the wrong title or abort; the spellings of one explicit head (`-h
  bob:feature`, `-h bob/renamed:feature`) were classified differently, so
  `--no-edit` and the `gh-merge-base` rule could follow HEAD for a head the
  current branch does not push to; `merge` let git follow tags into the
  repository while fetching the pull request; `hub push one,two` pushed the
  current branch by its short name, which a tag of the same name makes
  ambiguous, so neither remote got it; `--noop` gh lines could not be replayed
  with a `--config-env` value holding an apostrophe or a variable name the
  shell cannot expand, and dropped the `GIT_CONFIG_PARAMETERS` gh had
  inherited before the command line. Found along the way: `hub::push_target`
  read the upstream from `%(upstream)`, which is empty when the fetch
  refspecs map it to no remote-tracking ref, and said `git push` would refuse
  where git pushes by the configured names (`branch.*.remote`,
  `branch.*.merge`).
- Found by the review of the tenth round: `hub::push_target` read one
  `branch.*.merge` value where git counts them, so `pull-request -p` could
  push a branch that `git push` refuses for having several upstream branches;
  it took `%(push:remoteref)` for git's reading of `remote.*.push`, which
  knows neither a matching refspec (`:`), nor a `HEAD` or short source, and
  applies a negative refspec to the source where `git push` applies it to the
  destination, so such a branch was refused as unmapped, or sent where git
  excludes it, and a mirror remote fell through to `push.default`; a `--noop`
  gh line cut the first character of every further line of a multi-line
  `--config-env` value, and lost the trailing newlines of one read through
  `printenv`; the bash completion replaced a `complete -F` registration the
  user had for `git`; `hub help sync` claimed a `main` fallback that `sync`
  does not have (a branch deleted on the remote is left alone, with a
  warning, when the default branch is unknown).
- Found by the review of the eleventh round: `pull-request -p` pushed where
  its own reading of `remote.*.push` said, so it could push a branch that `git
  push` refuses (a short source that names a branch and a tag at once, a later
  source that names nothing, one destination fed by two sources), and refused
  a branch that git sends to its second destination when a negative refspec
  excludes the first; hub now reads every destination the refspecs give the
  branch, drops the excluded ones, and, before pushing, asks git itself (`git
  push --dry-run --porcelain` to the remote) what it would send the branch as,
  refusing with git's own words what git refuses. A branch with no push remote
  configured went to `origin` where git takes the sole remote, whatever its
  name, so `pull-request -p`, `-h BRANCH`, `browse` and `compare` missed a
  repository whose one remote is called otherwise. `--no-edit` for a head that
  is another branch read the remote-tracking branch of the remote that pushes
  to the head repository, which may fetch from another one, a fork's branch
  from the upstream's refs, say; it reads a remote that fetches from the head
  repository. The pushed-branch check read `%(push)`, which knows no `HEAD` or
  short source in `remote.*.push`, so a branch pushed under
  `HEAD:refs/heads/publish` was "not yet pushed"; it reads the remote-tracking
  branch the remote's fetch refspecs map the destination to. `merge` took an
  empty extra operand (`hub merge URL ''`) for none, fetched the pull request
  and let git refuse the empty revision; it is refused before anything is
  fetched.
- The option table and the usage of a git command are read once per run, as
  documented; read through `hub::git_option`, they were asked of git again
  for every option on the command line.

## v0.1.0 — 2026-10-29

A bash 5 rewrite of hub that hands all GitHub work to the official GitHub CLI
(`gh`): a git wrapper with GitHub-aware `clone`, `remote`, `fetch`, `push`,
`checkout`, `merge`, `am`, `apply`, `cherry-pick` and `sync`, plus the
`pull-request`, `pr`, `issue`, `release`, `browse`, `compare`, `create`, `fork`,
`delete`, `ci-status`, `api`, `gist` and `alias` commands.
