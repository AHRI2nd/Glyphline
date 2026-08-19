#!/usr/bin/env bash
# Builds a release .app bundle, codesigns it with Hardened Runtime, and
# (optionally) notarizes + staples it — plus a notarized+stapled .dmg, the
# actual artifact to hand to a beta tester (see the --notarize block below
# for why a zip isn't safe for that). Run from anywhere; paths are resolved
# relative to this script.
#
# Usage:
#   scripts/release.sh                       # build + sign only
#   scripts/release.sh --notarize            # build + sign + notarize + staple + .dmg
#   scripts/release.sh --version=0.2.0       # also stamp CFBundleShortVersionString/
#                                             # CFBundleVersion in the built .app
#                                             # (Sparkle compares exactly these two
#                                             # values to detect updates — without
#                                             # this every release ships whatever's
#                                             # hardcoded in scripts/Info.plist, and
#                                             # Sparkle never sees a new version)
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
VERSION=""

for arg in "$@"; do
    case "$arg" in
        --notarize) DO_NOTARIZE=true ;;
        --version=*) VERSION="${arg#--version=}" ;;
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
if [ -n "$VERSION" ]; then
    echo "==> Stamping version $VERSION"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [ -f "$SCRIPT_DIR/Glyphline.icns" ]; then
    cp "$SCRIPT_DIR/Glyphline.icns" "$APP_DIR/Contents/Resources/Glyphline.icns"
else
    echo "warning: Glyphline.icns not found — run scripts/build-icon.sh first" >&2
fi
# Standard, codesign-safe location — a bundle-root sibling of Contents/ (what
# SwiftPM's generated Bundle.module accessor looks for first) fails codesign's
# "unsealed contents present in the bundle root" check. L10n.swift's
# resolveResourceBundle() checks Contents/Resources/ first for exactly this
# reason, falling back to Bundle.module only for unsigned dev builds.
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/Glyphline_Glyphline.bundle"

# The built executable's only LC_RPATH entry is @loader_path (verified with
# `otool -l`, not the conventional @executable_path/../Frameworks — swift
# build doesn't add that for us) — meaning @rpath/Sparkle.framework/... only
# resolves in the SAME directory as the Glyphline binary itself, i.e.
# Contents/MacOS/, not Contents/Frameworks/. `swift run`/.build/debug work
# by accident (Sparkle.framework already sits right next to the binary
# there); this assembled .app never carried the framework at all, so it
# launched fine unsigned/undistributed but crashed at launch (dyld: Library
# not loaded) the moment it left .build/ — the crash a beta tester actually
# hit. Copying it into Frameworks/ (the "proper" location) would NOT fix
# this without also re-linking with a real rpath, so this matches the
# rpath that already exists instead.
SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "error: Sparkle.framework not found at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/MacOS/Sparkle.framework"

# swift build's Sparkle.framework ships ad-hoc signed (TeamIdentifier=not
# set) — invalid for a notarized, distributed app. Every piece of nested
# executable code inside it (the XPC services, the Autoupdate tool, the
# nested Updater.app) must be signed with our real identity, and signed
# INNERMOST FIRST: codesign reseals a bundle's Resources (including nested
# bundles) when it signs, so signing the outer Sparkle.framework before its
# XPC services/Autoupdate/Updater.app would seal in their now-stale ad-hoc
# signatures. The final `codesign --deep` on the whole .app below then
# leaves all of this alone (it only signs code that ISN'T already validly
# signed), same as it does for any other pre-signed vendored framework.
echo "==> Codesigning embedded Sparkle.framework (innermost first)"
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$APP_DIR/Contents/MacOS/Sparkle.framework/Versions/B/Autoupdate"
find "$APP_DIR/Contents/MacOS/Sparkle.framework/Versions/B/XPCServices" -maxdepth 1 -name "*.xpc" -print0 \
    | xargs -0 -I{} codesign --force --options runtime --sign "$SIGN_IDENTITY" {}
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$APP_DIR/Contents/MacOS/Sparkle.framework/Versions/B/Updater.app"
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$APP_DIR/Contents/MacOS/Sparkle.framework"

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

    # A zip handed to a beta tester is fragile in a way nothing above warns
    # about: `unzip` (as opposed to Finder/Archive Utility, or `ditto -x -k`)
    # extracts macOS's AppleDouble resource-fork sidecar files (._Autoupdate,
    # ._Downloader, …) as literal files INSIDE the embedded framework, which
    # codesign then rejects as "unsealed contents present in the root
    # directory of an embedded framework" — reproduced locally with plain
    # `unzip` after a real tester hit exactly this ("손상되었기 때문에 열
    # 수 없습니다"). A DMG sidesteps the whole class of bug: it's
    # mounted as a real filesystem, so there's no lossy archive-format
    # round-trip for resource forks/symlinks to survive in the first place.
    DMG_PATH="$ROOT_DIR/.build/Glyphline-release.dmg"
    echo "==> Building disk image"
    rm -f "$DMG_PATH"
    DMG_STAGING="$ROOT_DIR/.build/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_DIR" "$DMG_STAGING/Glyphline.app"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname "Glyphline" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
    rm -rf "$DMG_STAGING"

    # hdiutil's own output is unsigned — notarization accepts that fine (it
    # only cares that the .app inside is properly signed, already true), but
    # an unsigned dmg fails spctl's OWN check of the container when Finder
    # mounts it (`spctl -t open` looks for the dmg's own signature, separate
    # from the stapled ticket) — codesign works directly on a dmg file same
    # as any other Mach-O/bundle target.
    echo "==> Codesigning disk image"
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"

    echo "==> Submitting disk image to Apple notary service"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling notarization ticket to disk image"
    xcrun stapler staple "$DMG_PATH"

    echo "==> Disk image Gatekeeper assessment"
    spctl -a -t open --context context:primary-signature --verbose "$DMG_PATH"

    echo "==> Disk image ready: $DMG_PATH"
fi

echo "==> Done: $APP_DIR"
