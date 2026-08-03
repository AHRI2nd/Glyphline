#!/usr/bin/env bash
# Builds a release .app bundle, codesigns it with Hardened Runtime, and
# (optionally) notarizes + staples it. Run from anywhere; paths are resolved
# relative to this script.
#
# Usage:
#   scripts/release.sh                       # build + sign only
#   scripts/release.sh --notarize            # build + sign + notarize + staple
#
# One-time setup (not done by this script, see CLAUDE.md / M7 notes):
#   xcrun notarytool store-credentials "glyphline-notary" \
#     --apple-id "<apple id email>" --team-id "<team id>" --password "<app-specific password>"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/.build/Glyphline-release.app"
SIGN_IDENTITY="Developer ID Application: Sangmin Lee (7N6XWH2333)"
NOTARY_PROFILE="glyphline-notary"
DO_NOTARIZE=false

for arg in "$@"; do
    case "$arg" in
        --notarize) DO_NOTARIZE=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

echo "==> Building (release)"
cd "$ROOT_DIR"
swift build -c release

# Deterministic path only — a `find "*release*"` pattern here once matched the
# STALE copy inside a previously assembled Glyphline-release.app, which the
# rm -rf below then deleted before the cp, failing the build intermittently
# depending on filesystem traversal order.
RESOURCE_BUNDLE="$BUILD_DIR/Glyphline_Glyphline.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "error: resource bundle not found at $RESOURCE_BUNDLE" >&2
    exit 1
fi

echo "==> Assembling .app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/Glyphline" "$APP_DIR/Contents/MacOS/Glyphline"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
# Standard, codesign-safe location — a bundle-root sibling of Contents/ (what
# SwiftPM's generated Bundle.module accessor looks for first) fails codesign's
# "unsealed contents present in the bundle root" check. L10n.swift's
# resolveResourceBundle() checks Contents/Resources/ first for exactly this
# reason, falling back to Bundle.module only for unsigned dev builds.
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/Glyphline_Glyphline.bundle"

echo "==> Codesigning (Hardened Runtime + entitlements)"
codesign --force --deep --options runtime \
    --entitlements "$SCRIPT_DIR/entitlements.plist" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose "$APP_DIR" || echo "(spctl assessment above is expected to fail until notarized+stapled)"

if [ "$DO_NOTARIZE" = true ]; then
    ZIP_PATH="$ROOT_DIR/.build/Glyphline-release.zip"
    echo "==> Zipping for notarization submission"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

    echo "==> Submitting to Apple notary service (this can take a few minutes)"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$APP_DIR"

    echo "==> Final Gatekeeper assessment"
    spctl --assess --type execute --verbose "$APP_DIR"
fi

echo "==> Done: $APP_DIR"
