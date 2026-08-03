#!/usr/bin/env bash
# Rasterizes icon.svg into a macOS .iconset and packages it into Glyphline.icns.
# Run once (or whenever icon.svg changes); release.sh copies the resulting
# .icns into the app bundle and references it via Info.plist's CFBundleIconFile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$SCRIPT_DIR/icon.svg"
ICONSET="$SCRIPT_DIR/Glyphline.iconset"
ICNS="$SCRIPT_DIR/Glyphline.icns"

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert not found (brew install librsvg)" >&2; exit 1; }

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# macOS ships bash 3.2 (no associative arrays) — plain name:size pairs instead.
SIZES="icon_16x16.png:16 icon_16x16@2x.png:32 icon_32x32.png:32 icon_32x32@2x.png:64 \
icon_128x128.png:128 icon_128x128@2x.png:256 icon_256x256.png:256 icon_256x256@2x.png:512 \
icon_512x512.png:512 icon_512x512@2x.png:1024"

for pair in $SIZES; do
    name="${pair%%:*}"
    size="${pair##*:}"
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$ICONSET/$name"
done

iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"
echo "==> Built $ICNS"
