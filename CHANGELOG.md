# Changelog

All notable changes to hub are recorded here, in the style of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). For each release,
`script/bump` moves the notes under Unreleased to a `## vX.Y.Z — YYYY-MM-DD`
heading.

## Unreleased

### Fixed

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
