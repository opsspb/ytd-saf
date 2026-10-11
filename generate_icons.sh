#!/bin/bash
# Script to generate app icons from icon.svg
# Run this on macOS with librsvg or ImageMagick installed
# Example: brew install librsvg

set -e

ICON_SVG="icon.svg"
APP_ICON_DIR="YTDownloader/Resources/Assets.xcassets/AppIcon.appiconset"
EXT_ICON_DIR="YTDownloader/Resources/Assets.xcassets/ExtensionIcon.imageset"

if ! command -v rsvg-convert &> /dev/null; then
    echo "Error: rsvg-convert not found. Install with: brew install librsvg"
    exit 1
fi

echo "Generating app icons..."

# App icons
rsvg-convert -w 16 -h 16 "$ICON_SVG" > "$APP_ICON_DIR/icon_16x16.png"
rsvg-convert -w 32 -h 32 "$ICON_SVG" > "$APP_ICON_DIR/icon_16x16@2x.png"
rsvg-convert -w 32 -h 32 "$ICON_SVG" > "$APP_ICON_DIR/icon_32x32.png"
rsvg-convert -w 64 -h 64 "$ICON_SVG" > "$APP_ICON_DIR/icon_32x32@2x.png"
rsvg-convert -w 128 -h 128 "$ICON_SVG" > "$APP_ICON_DIR/icon_128x128.png"
rsvg-convert -w 256 -h 256 "$ICON_SVG" > "$APP_ICON_DIR/icon_128x128@2x.png"
rsvg-convert -w 256 -h 256 "$ICON_SVG" > "$APP_ICON_DIR/icon_256x256.png"
rsvg-convert -w 512 -h 512 "$ICON_SVG" > "$APP_ICON_DIR/icon_256x256@2x.png"
rsvg-convert -w 512 -h 512 "$ICON_SVG" > "$APP_ICON_DIR/icon_512x512.png"
rsvg-convert -w 1024 -h 1024 "$ICON_SVG" > "$APP_ICON_DIR/icon_512x512@2x.png"

# Extension icons for manifest
mkdir -p YTDownloader/YTDownloaderExtension/Resources
rsvg-convert -w 48 -h 48 "$ICON_SVG" > "YTDownloader/YTDownloaderExtension/Resources/icon-48.png"
rsvg-convert -w 96 -h 96 "$ICON_SVG" > "YTDownloader/YTDownloaderExtension/Resources/icon-96.png"
rsvg-convert -w 128 -h 128 "$ICON_SVG" > "YTDownloader/YTDownloaderExtension/Resources/icon-128.png"

echo "Icons generated successfully!"
