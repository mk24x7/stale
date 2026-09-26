# Security Policy

## Supported versions

Only the latest release of Stale (app and CLI) receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub private vulnerability reporting:
open the repository's Security tab and choose "Report a vulnerability"
(https://github.com/mk24x7/stale/security/advisories/new).

Do not open a public issue for security problems.

Include the Stale version, macOS version, whether you used the app or the CLI, and the smallest directory layout or steps that reproduce the problem.

You should receive an acknowledgement within 7 days. Once a fix is released the advisory will be published and you will be credited unless you ask otherwise.

## Scope

Stale promises to be read-only: it never modifies a repository, its index, its refs or its working tree, and it never contacts a remote. The most serious class of bug is breaking that promise. In scope:

- Any way a scan could write to a repository, for example by refreshing the index, taking a lock, creating refs or running `git fetch`.
- Any way a scan could run code from a scanned repository: git hooks, `core.fsmonitor`, filters, pagers or other configuration-driven commands.
- Shell or argument injection through crafted directory, branch or remote names.
- Following symbolic links out of the folder being scanned.

Out of scope: findings that are wrong but cause no modification (please open a regular bug report), and repositories git itself refuses to read, such as those owned by another user.
