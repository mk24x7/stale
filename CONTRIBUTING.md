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
