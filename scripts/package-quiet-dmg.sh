#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Quiet.app"
DMG_PATH="${DMG_PATH:-$DIST_DIR/Quiet-latest.dmg}"
SIGN_ID="${SIGN_ID:-Developer ID Application: hongxia sun (9UXM7M6CX5)}"
NOTARIZE="${NOTARIZE:-1}"

export SIGN_ID
"$ROOT_DIR/scripts/package-quiet-app.sh"

STAGING_DIR="$(mktemp -d /tmp/quiet-dmg.XXXXXX)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

rm -f "$DMG_PATH"
cp -R "$APP_DIR" "$STAGING_DIR/Quiet.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "Quiet" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
  : "${APPLE_ID:?APPLE_ID is required when NOTARIZE=1}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required when NOTARIZE=1}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required when NOTARIZE=1}"

  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
