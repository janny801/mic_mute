#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

VERSION="1.0.0"
APP_NAME="MicMute"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
ZIP_PATH="$BUILD_DIR/$APP_NAME-v$VERSION-macOS.zip"

echo "==> 1. Building $APP_NAME release app bundle..."
./scripts/build_app.sh release

echo "==> 2. Creating DMG package..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo "==> 3. Creating ZIP package..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Release packaging complete:"
echo "    - DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
echo "    - ZIP: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"
