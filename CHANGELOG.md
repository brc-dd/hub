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
  `apply`, `cherry-pick`) know git's value-taking options only to find their
  one shorthand operand; everything else goes to git as written, and nothing
  after `--` is interpreted.
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
  checks every member before the first push, and never splits an existing
  remote, a path or a URL.
- `merge` fetches the pull request into a private ref and merges that commit,
  takes the last of `--squash`/`--no-squash`, adds `--no-ff` only when no
  fast-forward option was given, and refuses a second revision. `cherry-pick`
  resolves every URL or `USER@SHA` operand, prefers a local revision of that
  name, and finds a pull request's commit by id in its history. `am` and
  `apply` download pull-request, commit and compare URLs (also `.patch` and
  `.diff`) through `gh api`.
- `pull-request` has hub's grammar only (`-R`, `--dry-run`, `--fill` and gh
  passthrough are gone): the head is named from where `git push` sends the
  branch and from that remote's push URL; without `-p` the branch must be
  pushed, which `-f` skips; `-p` checks everything, including what gh would
  refuse without a terminal, before pushing `HEAD:refs/heads/BRANCH`;
  `--no-edit` takes the first commit's message; `-i` converts an issue through
  the API with string fields; `-o` and `-c` leave gh's prompts alone and look
  the URL up afterwards.
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
- Remote identity: a remote's URL is read as git uses it; SSH hosts are
  resolved through the ssh git would run (`GIT_SSH_COMMAND`, `core.sshCommand`,
  `GIT_SSH`, then `ssh`), with the user and port, so `Match` blocks and
  port-443 aliases work and HTTPS hosts are taken literally; `GH_REPO` must be
  `OWNER/REPO`, `HOST/OWNER/REPO` or a URL. Push destinations follow git's own
  rules (`remote.*.push`, `branch.*.pushRemote`, `remote.pushDefault`,
  `push.default`). Branches are handled as full refs, so a tag of the same
  name cannot confuse them.
- Prerequisites: bash 5.3, git 2.41 and gh 2.40 or newer, with the reason for
  each in the README. `make install PREFIX="$HOME/.local"` is the documented
  local install; `make install` refuses to overwrite anything it did not
  create. Completions no longer replace a user's own git completion
  customizations and find hub's command word after any global option.
  `script/release` names the canonical repository, pushes exact refspecs,
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

## v0.1.0 — 2026-10-29

A bash 5 rewrite of hub that hands all GitHub work to the official GitHub CLI
(`gh`): a git wrapper with GitHub-aware `clone`, `remote`, `fetch`, `push`,
`checkout`, `merge`, `am`, `apply`, `cherry-pick` and `sync`, plus the
`pull-request`, `pr`, `issue`, `release`, `browse`, `compare`, `create`, `fork`,
`delete`, `ci-status`, `api`, `gist` and `alias` commands.
