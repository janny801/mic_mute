#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

CONFIGURATION="${1:-release}"
APP_NAME="MicMute"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Building $APP_NAME ($CONFIGURATION)..."
export GIT_CEILING_DIRECTORIES="/Users/janredsalubayba"

if [ "$CONFIGURATION" = "release" ]; then
    swift build -c release
    BIN_PATH="$DIR/.build/arm64-apple-macosx/release/$APP_NAME"
else
    swift build -c debug
    BIN_PATH="$DIR/.build/arm64-apple-macosx/debug/$APP_NAME"
fi

echo "==> Creating macOS App Bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Generate App Icon if not present
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
if [ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
    echo "==> Generating App Icon..."
    mkdir -p "$ICONSET_DIR"
    
    # Generate base icon with swift/CoreGraphics
    swift -e '
    import Cocoa

    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()

    let context = NSGraphicsContext.current!.cgContext

    // Background squircle
    let rect = NSRect(x: 16, y: 16, width: 480, height: 480)
    let path = NSBezierPath(roundedRect: rect, xRadius: 108, yRadius: 108)
    
    let gradient = NSGradient(starting: NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0),
                              ending: NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0))!
    gradient.draw(in: path, angle: -45)

    // Inner border
    NSColor(white: 1.0, alpha: 0.15).setStroke()
    path.lineWidth = 4
    path.stroke()

    // Microphone symbol
    let config = NSImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
    if let micSymbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolRect = NSRect(x: 146, y: 146, width: 220, height: 220)
        micSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()

    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: "build/icon_512.png"))
    }
    ' 2>/dev/null || true

    if [ -f "build/icon_512.png" ]; then
        sips -z 16 16     build/icon_512.png --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
        sips -z 32 32     build/icon_512.png --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
        sips -z 32 32     build/icon_512.png --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
        sips -z 64 64     build/icon_512.png --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
        sips -z 128 128   build/icon_512.png --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
        sips -z 256 256   build/icon_512.png --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
        sips -z 256 256   build/icon_512.png --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
        sips -z 512 512   build/icon_512.png --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
        sips -z 512 512   build/icon_512.png --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
        iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
        rm -rf "$ICONSET_DIR" "build/icon_512.png"
    fi
fi

# Ad-hoc code sign for local execution and macOS security permissions
echo "==> Code signing application bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Build succeeded: $APP_BUNDLE"
