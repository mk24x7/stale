# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-26

### Added

- `StaleCore` engine: an iterative walk that finds git repositories (working trees, linked worktrees and bare repositories) under a folder, skipping dependency and build folders, symlinks and app bundles, with a depth limit, task cancellation and a count of folders that could not be read.
- Per-repository inspection with read-only git commands (`status --porcelain=v2`, `for-each-ref`, `stash list`, `remote`, `rev-list`), run with `GIT_OPTIONAL_LOCKS=0`, a 20 second timeout per command and at most eight repositories at a time.
- Findings: repositories with no remote, unpushed commits, branches with no upstream (or a gone upstream) holding commits no remote has, commits on a detached HEAD, uncommitted changes, untracked files, stashes, and repositories git cannot read.
- Risk levels (high, medium, low) and a risk order for sorting.
- `stale` command-line tool with `--json`, `--only`, `--min-risk`, `--nested`, `--max-depth`, `--no-color`, `--version` and `--help`, and exit code 3 when at-risk work is found.
- Stale macOS app: folder picker, nested repositories toggle, progress with cancel, results grouped by risk with a badge per finding, Reveal in Finder, Open in Terminal, Copy Report and Rescan.
- Build, packaging and release tooling: universal app and CLI, zip, DMG and CLI tarball with checksums, CI and tagged releases, Homebrew formula and cask.
- Hidden snapshot mode (`STALE_SNAPSHOT_DIR`, `STALE_SNAPSHOT_ROOT`) and `scripts/snapshot.sh`, which render the README screenshot from a fixture of demo repositories.

[Unreleased]: https://github.com/mk24x7/stale/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/mk24x7/stale/releases/tag/v1.0.0
