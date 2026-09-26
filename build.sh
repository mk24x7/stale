#!/bin/bash
# Build Stale.app and the stale command-line tool from source and ad-hoc sign
# both.
#
# Environment:
#   VERSION        marketing version written to the bundle
#                  (default: exact git tag on HEAD without the v, else the VERSION file)
#   BUILD_NUMBER   CFBundleVersion (default: git commit count, then 1)
#   ARCHS          space-separated architectures, e.g. "arm64 x86_64"
#                  (default: the current machine)
#   OUT_DIR        output directory; produces $OUT_DIR/Stale.app and $OUT_DIR/stale
#                  (default: dist)
#   SWIFT_FLAGS    extra flags for swift build, e.g. --disable-sandbox
#   SIGN_IDENTITY  codesign identity (default: "-" for ad-hoc)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Stale"
# SwiftPM product names; see Package.swift for why the app target is StaleApp.
APP_PRODUCT="StaleApp"
CLI_PRODUCT="stale"

# Prefer an exact tag on HEAD (release builds), otherwise the VERSION file.
if [ -z "${VERSION:-}" ]; then
    VERSION="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true)"
fi
if [ -z "${VERSION:-}" ] && [ -f VERSION ]; then
    VERSION="$(tr -d '[:space:]' < VERSION)"
fi
if [ -z "${VERSION:-}" ]; then
    echo "error: VERSION could not be determined" >&2
    exit 1
fi
# CFBundleShortVersionString must be numeric: drop any -prerelease suffix.
APP_VERSION="${VERSION%%-*}"
if [ -z "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi
ARCHS="${ARCHS:-$(uname -m)}"
OUT_DIR="${OUT_DIR:-dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
CLI_PATH="$OUT_DIR/$CLI_PRODUCT"

# shellcheck disable=SC2206
SWIFT_EXTRA=(${SWIFT_FLAGS:-})

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) for: $ARCHS"

APP_BINARIES=()
CLI_BINARIES=()
for arch in $ARCHS; do
    triple="$arch-apple-macosx"
    echo "swift build -c release --triple $triple ${SWIFT_EXTRA[*]:-}"
    swift build -c release --triple "$triple" ${SWIFT_EXTRA[@]+"${SWIFT_EXTRA[@]}"}
    bin_dir="$(swift build -c release --triple "$triple" ${SWIFT_EXTRA[@]+"${SWIFT_EXTRA[@]}"} --show-bin-path)"
    for product in "$APP_PRODUCT" "$CLI_PRODUCT"; do
        if [ ! -x "$bin_dir/$product" ]; then
            echo "error: $bin_dir/$product was not produced by swift build" >&2
            exit 1
        fi
    done
    APP_BINARIES+=("$bin_dir/$APP_PRODUCT")
    CLI_BINARIES+=("$bin_dir/$CLI_PRODUCT")
done

mkdir -p "$OUT_DIR"

# Joins one binary per architecture into $2, or copies a single one.
combine() {
    local output="$1"
    shift
    if [ "$#" -gt 1 ]; then
        lipo -create "$@" -output "$output"
    else
        cp "$1" "$output"
    fi
}

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
combine "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "${APP_BINARIES[@]}"

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "Assembling $CLI_PATH..."
rm -f "$CLI_PATH"
combine "$CLI_PATH" "${CLI_BINARIES[@]}"
chmod 755 "$CLI_PATH"

echo "Signing with identity: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none --identifier "com.mk24x7.stale.cli" "$CLI_PATH"
codesign --verify --strict --verbose=2 "$CLI_PATH"

echo ""
echo "Built: $APP_BUNDLE"
echo "Architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
echo "Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo "Built: $CLI_PATH ($("$CLI_PATH" --version))"
echo "Architectures: $(lipo -archs "$CLI_PATH")"
echo ""
echo "Next: ./package.sh (zip, dmg, CLI tarball, checksums) or APP_DIR=$OUT_DIR ./dmg.sh"
