# Changelog

All notable changes to hub are recorded here, in the style of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). For each release,
`script/bump` moves the notes under Unreleased to a `## vX.Y.Z — YYYY-MM-DD`
heading.

## Unreleased

A bash 5 rewrite of hub that hands all GitHub work to the official GitHub CLI
(`gh`): a git wrapper with GitHub-aware `clone`, `remote`, `fetch`, `push`,
`checkout`, `merge`, `am`, `apply`, `cherry-pick` and `sync`, plus the
`pull-request`, `pr`, `issue`, `release`, `browse`, `compare`, `create`, `fork`,
`delete`, `ci-status`, `api`, `gist` and `alias` commands.
