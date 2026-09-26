#!/bin/bash
# Regenerate the README screenshots from a throwaway fixture of demo
# repositories, so no real repository, path or name ends up in the image.
#
# Builds <tmp>/Code with eight git repositories in mixed states (unpushed
# commits, a branch with no upstream, uncommitted changes, untracked files, a
# stash, no remote, clean) whose remotes are bare repositories in
# <tmp>/remotes, then runs the app in snapshot mode against <tmp>/Code, which
# writes results.png and landing.png to SNAPSHOT_DIR. Review them before
# copying results.png to assets/results.png.
#
# Environment:
#   APP_BIN       app executable (default: dist/Stale.app/Contents/MacOS/Stale,
#                 built with ./build.sh when missing)
#   SNAPSHOT_DIR  where the PNGs are written (default: /tmp/stale-shots)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_BIN="${APP_BIN:-dist/Stale.app/Contents/MacOS/Stale}"
if [ ! -x "$APP_BIN" ]; then
    ./build.sh
fi

# Resolved (/var -> /private/var) because the scanner reports real paths.
FIXTURE="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stale-snapshot.XXXXXX")" && pwd -P)"
trap 'rm -rf "$FIXTURE"' EXIT
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/tmp/stale-shots}"
CODE="$FIXTURE/Code"
REMOTES="$FIXTURE/remotes"
mkdir -p "$CODE" "$REMOTES"

# Isolated from the user's git configuration, with a generic identity.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Demo User"
export GIT_AUTHOR_EMAIL="demo@example.com"
export GIT_COMMITTER_NAME="Demo User"
export GIT_COMMITTER_EMAIL="demo@example.com"

NOW="$(date +%s)"

# commit <repo> <days ago> <file> <message>
commit() {
    local repo="$1" days="$2" file="$3" message="$4"
    local stamp="$((NOW - days * 86400)) +0000"
    mkdir -p "$(dirname "$CODE/$repo/$file")"
    echo "$message" >> "$CODE/$repo/$file"
    git -C "$CODE/$repo" add -- "$file"
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" \
        git -C "$CODE/$repo" commit -q -m "$message"
}

# repo <name> <days ago of the first commit>: a repository with one commit
# pushed to a bare origin, main tracking origin/main.
repo() {
    local name="$1" days="$2"
    git init -q -b main "$CODE/$name"
    commit "$name" "$days" README.md "Initial commit"
    git init -q --bare -b main "$REMOTES/$name.git"
    git -C "$CODE/$name" remote add origin "$REMOTES/$name.git"
    git -C "$CODE/$name" push -q -u origin main
}

# High: three unpushed commits on main and a local branch no remote has.
repo billing-api 40
commit billing-api 3 src/invoice.go "Add proration to invoice totals"
commit billing-api 2 src/invoice_test.go "Cover proration edge cases"
commit billing-api 1 src/webhooks.go "Retry failed webhook deliveries"
git -C "$CODE/billing-api" checkout -q -b feature/tax-rates
commit billing-api 1 src/tax.go "Draft regional tax rates"
git -C "$CODE/billing-api" checkout -q main

# High: commits but no remote at all.
git init -q -b main "$CODE/data-pipeline"
commit data-pipeline 20 README.md "Initial commit"
commit data-pipeline 9 jobs/ingest.py "Add nightly ingest job"
commit data-pipeline 5 jobs/dedupe.py "Deduplicate events by id"

# High: one unpushed commit.
repo mobile-app 30
commit mobile-app 6 app/Onboarding.swift "Rework onboarding flow"

# Medium: modified and staged files plus untracked files.
repo storefront 25
commit storefront 12 src/cart.ts "Persist cart between sessions"
git -C "$CODE/storefront" push -q
echo "// apply coupon before tax" >> "$CODE/storefront/src/cart.ts"
mkdir -p "$CODE/storefront/src/checkout"
echo "export const steps = 3" > "$CODE/storefront/src/checkout/steps.ts"
git -C "$CODE/storefront" add -- src/checkout/steps.ts
echo "draft" > "$CODE/storefront/NOTES.md"

# Medium: a stash entry.
repo infra 60
commit infra 15 terraform/main.tf "Pin provider versions"
git -C "$CODE/infra" push -q
echo "# scale workers to 4" >> "$CODE/infra/terraform/main.tf"
git -C "$CODE/infra" stash push -q -m "WIP worker autoscaling"

# Low: untracked files only.
repo experiments 45
mkdir -p "$CODE/experiments/notebooks"
echo "{}" > "$CODE/experiments/notebooks/embedding-search.ipynb"
echo "{}" > "$CODE/experiments/notebooks/rate-limits.ipynb"

# Clean: committed and pushed.
repo docs-site 18
commit docs-site 4 content/getting-started.md "Expand getting started guide"
git -C "$CODE/docs-site" push -q
repo dotfiles 90

mkdir -p "$SNAPSHOT_DIR"
rm -f "$SNAPSHOT_DIR/results.png" "$SNAPSHOT_DIR/landing.png"
STALE_SNAPSHOT_DIR="$SNAPSHOT_DIR" STALE_SNAPSHOT_ROOT="$CODE" "$APP_BIN"

for name in results landing; do
    if [ ! -f "$SNAPSHOT_DIR/$name.png" ]; then
        echo "error: $SNAPSHOT_DIR/$name.png was not written" >&2
        exit 1
    fi
    echo "Wrote $SNAPSHOT_DIR/$name.png"
done
