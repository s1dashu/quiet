#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Blackhole.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CONFIGURATION="${CONFIGURATION:-release}"
ICON_COMPOSER_DIR="$ROOT_DIR/assets/app-icon/quiet-icon.icon"
ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
ICON_SOURCE="$ROOT_DIR/assets/app-icon/quiet-icon-1024.png"

cd "$ROOT_DIR"
BUILD_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
swift build --configuration "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/quiet" "$MACOS_DIR/Blackhole"
chmod +x "$MACOS_DIR/Blackhole"

if [[ -d "$ICON_COMPOSER_DIR" || -f "$ICON_SOURCE" ]]; then
  ICON_SOURCE_1024="$DIST_DIR/BlackholeIconSource-1024.png"
  ICONSET_DIR="$DIST_DIR/Blackhole.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  if [[ -d "$ICON_COMPOSER_DIR" && -x "$ICTOOL" ]]; then
    "$ICTOOL" "$ICON_COMPOSER_DIR" \
      --export-image \
      --output-file "$ICON_SOURCE_1024" \
      --platform macOS \
      --rendition Default \
      --width 1024 \
      --height 1024 \
      --scale 1 >/dev/null
  elif [[ -f "$ICON_SOURCE" ]]; then
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICON_SOURCE_1024" >/dev/null
  else
    echo "Could not export icon: $ICTOOL is unavailable and $ICON_SOURCE is missing" >&2
    exit 1
  fi
  sips -z 16 16 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE_1024" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_SOURCE_1024" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/Blackhole.icns"
  rm -rf "$ICONSET_DIR" "$ICON_SOURCE_1024"
fi

RESOURCE_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -type d -name 'Quiet_*.bundle' | head -1)"
if [[ -z "$RESOURCE_BUNDLE" ]]; then
  echo "Could not find SwiftPM resource bundle in $BUILD_DIR" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE")"
APP_RESOURCE_BUNDLE="$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE")"

NODE_BIN="$(node -p 'process.execPath' 2>/dev/null || true)"
if [[ -z "$NODE_BIN" ]]; then
  echo "Could not find node to bundle" >&2
  exit 1
fi
cp "$NODE_BIN" "$APP_RESOURCE_BUNDLE/Resources/node"
chmod +x "$APP_RESOURCE_BUNDLE/Resources/node"

rm -rf "$APP_RESOURCE_BUNDLE/Resources/node_modules"
cp -R "$ROOT_DIR/node_modules" "$APP_RESOURCE_BUNDLE/Resources/node_modules"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Blackhole</string>
  <key>CFBundleExecutable</key>
  <string>Blackhole</string>
  <key>CFBundleIdentifier</key>
  <string>com.sida.blackhole</string>
  <key>CFBundleIconFile</key>
  <string>Blackhole</string>
  <key>CFBundleName</key>
  <string>Blackhole</string>
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
