# Contributing to Stale

Thanks for helping. Stale tells people whether their work is safe, so a wrong answer is worse than no answer, and its one hard rule is that it never modifies a repository. Please read this before opening a pull request.

## Requirements

- macOS 13 or later
- Xcode command line tools with Swift 5.9 or later
- git (the scanner uses `/usr/bin/git`)

## Layout

| Path | What it is |
| --- | --- |
| `Sources/StaleCore` | The engine: discovery walk, git runner, parsers, findings, reports, CLI argument parser |
| `Sources/stale` | The `stale` command-line tool (no dependencies) |
| `Sources/StaleApp` | The SwiftUI app, bundled as `Stale.app` by `build.sh` |
| `Tests/StaleCoreTests` | XCTest suite; most tests build real repositories with git |

## Build

```sh
swift build                 # debug build of the engine, CLI and app
swift run stale ~/code      # run the CLI from source
./build.sh                  # release build: dist/Stale.app and dist/stale, ad-hoc signed
```

## Test

```sh
swift test
```

Tests create repositories in temporary folders with the system git, isolated from your global git configuration. CI runs the same command plus `shellcheck` and `scripts/check-ascii.sh`.

## Screenshots

The app has a hidden snapshot mode that renders the UI offscreen and quits, so
the README screenshot can be regenerated without screen recording permission.
`scripts/snapshot.sh` builds a throwaway fixture of demo repositories and runs
it:

```sh
./build.sh
SNAPSHOT_DIR=/tmp/stale-shots scripts/snapshot.sh
# review /tmp/stale-shots/results.png, then:
cp /tmp/stale-shots/results.png assets/results.png
```

- `STALE_SNAPSHOT_DIR` turns the mode on and is where `landing.png` and
  `results.png` are written (2x, 1560x1280 px for the default 780x640 pt window).
- `STALE_SNAPSHOT_ROOT` is the folder to scan. It is required: snapshot mode
  refuses to run without it, so the real home folder is never scanned. Paths are
  shown relative to its parent folder, so `<fixture>/Code` reads as `~/Code`.

The fixture (`<tmp>/Code`) holds eight repositories with generic names in mixed
states: unpushed commits, a branch with no upstream, uncommitted and staged
changes, untracked files, a stash, a repository with no remote and two clean
ones. Their remotes are bare repositories in `<tmp>/remotes`, outside the
scanned folder, and every commit uses a demo identity with git isolated from
your global configuration. Snapshot mode forces the dark appearance, only runs
the usual read-only scan and does not change the saved nested-repositories
setting.

## Rules for the engine

- Read-only. Only git subcommands that never write are allowed (`status`, `for-each-ref`, `stash list`, `remote`, `rev-list`, `rev-parse`). No `fetch`, no `gc`, nothing that takes a lock. `GIT_OPTIONAL_LOCKS=0` stays on.
- Arguments are always passed as an argv array to `/usr/bin/git`, never through a shell.
- Every git call has a timeout and honours task cancellation.
- A new finding type needs a test that builds the situation with real git commands, plus a negative test showing when it is not reported.
- Add a line under `## [Unreleased]` in `CHANGELOG.md`.

## Commit messages

- Imperative mood, capitalised, no trailing period: "Add detached HEAD detection", not "added detached head".
- Subject line of 72 characters or fewer, blank line, then a body explaining why when it is not obvious.
- No emojis or decorative symbols anywhere: commits, code, comments or documentation. `scripts/check-ascii.sh` enforces ASCII in text files.

## Pull requests

- Keep each pull request focused on one change.
- Fill in the pull request template checklist.
- Include tests for bug fixes and new behaviour.
- Describe how you tested manually if the change affects the app UI.
