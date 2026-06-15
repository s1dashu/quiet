#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Neat.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/neat" "$MACOS_DIR/Neat"
chmod +x "$MACOS_DIR/Neat"

# SwiftPM's generated Bundle.module accessor looks for this bundle next to
# Bundle.main.bundleURL, so keep it at the app root instead of Contents/Resources.
RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -type d -name 'Neat_*.bundle' | head -1)"
if [[ -z "$RESOURCE_BUNDLE" ]]; then
  echo "Could not find SwiftPM resource bundle in $BUILD_DIR" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/$(basename "$RESOURCE_BUNDLE")"

NODE_BIN="$(node -p 'process.execPath' 2>/dev/null || true)"
if [[ -z "$NODE_BIN" ]]; then
  echo "Could not find node to bundle" >&2
  exit 1
fi
cp "$NODE_BIN" "$APP_DIR/$(basename "$RESOURCE_BUNDLE")/Resources/node"
chmod +x "$APP_DIR/$(basename "$RESOURCE_BUNDLE")/Resources/node"

rm -rf "$APP_DIR/$(basename "$RESOURCE_BUNDLE")/Resources/node_modules"
cp -R "$ROOT_DIR/node_modules" "$APP_DIR/$(basename "$RESOURCE_BUNDLE")/Resources/node_modules"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Neat</string>
  <key>CFBundleExecutable</key>
  <string>Neat</string>
  <key>CFBundleIdentifier</key>
  <string>com.sida.neat</string>
  <key>CFBundleName</key>
  <string>Neat</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
