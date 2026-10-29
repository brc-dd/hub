# Changelog

All notable changes to hub are recorded here, in the style of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). For each release,
`script/bump` moves the notes under Unreleased to a `## vX.Y.Z — YYYY-MM-DD`
heading.

## Unreleased

### Fixed

- `pull-request -p` applies one rule before any push: the push remote's
  push URLs must name a single GitHub repository on the base's host that is
  the base itself or a fork of it (checked with one API lookup), the head
  owner must not be an organisation, and `-R`/`--repo` must be a well-formed
  repository; `-p -h OWNER:BRANCH` resolves OWNER's fork of the actual base.
- Hosts gh is logged in to are recognised as GitHub hosts without `hub.host`;
  ports in `GH_HOST` no longer break host recognition, and SSH URLs for such
  hosts use the `ssh://` form on the default port.
- `-c` and `--config-env` also reach the git commands gh runs itself.
- `fork` retries the first fetch while GitHub is still creating the fork.
- `fetch` recognises `--multiple` anywhere among the leading options.
- `compare` builds the head from the remote whose tracking ref proved the
  branch exists.
- `issue update` reads `-R=org/repo` and other `-X=VALUE` forms like gh does.
- The release workflow publishes each tag in its own job so an overlapping
  release cannot cancel another; only the formula update is serialised.
- `pull-request` always passes the repository hub resolved to gh (`--repo`),
  unless `-R` is given; the head owner comes from the push remote's push URL,
  not its fetch URL, and all push URLs must agree; gh's `-H` inside an option
  cluster counts as hub's `-h`.
- `am`, `apply` and `cherry-pick` always name the URL's host when asking the
  API, so a single Enterprise login cannot divert a github.com lookup.
- `fork` takes the fork's real name from the API response, so an existing,
  renamed fork gets the right remote; `issue update -s closed --duplicate-of`
  rejects closing an issue as a duplicate of itself.
- `fetch --multiple` handles options before, between and after the names.
- `-c` and `--config-env` are forwarded to git verbatim (valueless `-c` and
  any environment name work), apply to hub's own git queries, and show up in
  `--noop` output; only a token that applies to the host overrides gh's cached
  login.
- `browse` and `compare` understand `OWNER/REPO.wiki` projects; `compare`
  refuses an unpushed branch and a base equal to the head.
- Release publishing recovers when the other publisher created the release
  first; the formula downgrade guard compares SemVer precedence properly
  (`script/update-formula --self-test` runs its fixtures, also in `make check`).
- `pull-request --dry-run` pins the head so gh cannot push or fork during its
  own dry run; issue conversion and `-b OWNER:BRANCH` always hand gh the
  repository and host hub resolved; `-p -h OWNER:BRANCH` refuses a remote
  whose push URL points elsewhere.
- `sync` confirms with `git ls-remote` that a gone branch was really deleted
  on the remote before deleting it locally (negative fetch refspecs no longer
  cause deletions).
- `fork` forks the repository hub resolved and adds the remote itself, so gh's
  default-repository setting cannot divert it; an existing remote of that
  name is checked before anything is forked.
- `issue update -s closed` validates `--reason` and `--duplicate-of` before
  running anything.
- `am`/`apply` pass `--allow-escape-sequences` when gh supports it, so patches
  containing escape bytes apply.
- `fetch --multiple USER USER2` adds the missing remotes like the comma form.
- `-c` and `--config-env` keep git's left-to-right precedence.
- The login is looked up through the API when a token variable overrides gh's
  stored credentials; the default-branch lookup always names the host.
- `script/release` and the release workflow recover from each other publishing
  first instead of failing on a duplicate release or push.
- `push` to several remotes forwards the arguments exactly as given and appends
  the current branch only when nothing follows the remotes; `--delete`,
  `--tags`, `--all` and option values no longer gain an invented ref.
- `pull-request -p` with `-h OWNER:BRANCH` or `-h BRANCH` pushes to the remote
  and branch the head names; `-b OWNER[/REPO]:BRANCH` becomes `--repo` plus
  `--base`; gh option values are never read as hub flags; `--dry-run` never
  pushes; converting an issue from another repository uses that repository.
- `issue update` takes hub's `-m`/`-F` as title and body again and closes or
  reopens every number given; state-specific options are validated first.
- `release edit -a` uploads without `--clobber` unless asked; asset files are
  checked before anything runs.
- `api -t`/`--flat` is an error instead of silently printing JSON.
- `create` applies its remote check to `-r`/`--remote` too, refuses options
  gh rejects with `--source`, and `-c` copies the URL as in hub 2.x.
- `remote add origin` alone means your own fork again.
- `am`/`apply` no longer treat option values such as `--exclude URL` as patches.
- `sync` exits non-zero when a branch could not be updated or deleted.
- `ci-status` resolves the repository itself and tolerates 403/404/422 from
  the check-runs API, as hub 2.x did.
- `browse -- commits` and `browse -- tree` follow the current branch.
- `GITHUB_HOST` is passed to gh as `GH_HOST`; the default host follows gh's
  rule (the only logged-in host, else github.com); `HUB_PROTOCOL` is honoured;
  `*.ghe.com` SSH URLs use the tenant user; `GH_BROWSER` is preferred.
- `hub -C ''` is a no-op like `git -C ''`; the fast path quotes `--noop` output.
- `make install` fails when a link cannot be created; `script/update-formula`
  refuses to downgrade the formula unless `--force` is given.

## v0.1.0 — 2026-10-29

A bash 5 rewrite of hub that hands all GitHub work to the official GitHub CLI
(`gh`): a git wrapper with GitHub-aware `clone`, `remote`, `fetch`, `push`,
`checkout`, `merge`, `am`, `apply`, `cherry-pick` and `sync`, plus the
`pull-request`, `pr`, `issue`, `release`, `browse`, `compare`, `create`, `fork`,
`delete`, `ci-status`, `api`, `gist` and `alias` commands.
