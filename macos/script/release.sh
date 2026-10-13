#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-archive}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$PROJECT_DIR/dist/MyShell.xcarchive}"
APP_PATH="$ARCHIVE_PATH/Products/Applications/MyShell.app"
ZIP_PATH="${ZIP_PATH:-$PROJECT_DIR/dist/MyShell-macOS-arm64.zip}"
PERSONAL_DERIVED_DATA="${PERSONAL_DERIVED_DATA:-$PROJECT_DIR/dist/DerivedData}"
PERSONAL_APP_PATH="$PERSONAL_DERIVED_DATA/Build/Products/Release/MyShell.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"

require_value() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: $name is required" >&2
    exit 2
  fi
}

verify_app() {
  local app="$1"
  local binary="$app/Contents/MacOS/MyShell"
  test -d "$app"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  /usr/bin/codesign -d --verbose=4 "$app"
  /usr/bin/lipo -archs "$binary" | /usr/bin/grep -qx "arm64"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app"
}

archive_app() {
  require_value DEVELOPMENT_TEAM
  /bin/mkdir -p "$(dirname "$ARCHIVE_PATH")"
  cd "$PROJECT_DIR"
  /usr/bin/xcodebuild \
    -project MyShell.xcodeproj \
    -scheme MyShell \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    archive
  verify_app "$APP_PATH"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  echo "Created $ZIP_PATH"
}

notarize_app() {
  require_value NOTARY_KEYCHAIN_PROFILE
  verify_app "$APP_PATH"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  /usr/bin/xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$APP_PATH"
  /usr/bin/xcrun stapler validate "$APP_PATH"
  verify_app "$APP_PATH"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  echo "Notarized $ZIP_PATH"
}

personal_build() {
  /bin/mkdir -p "$PROJECT_DIR/dist"
  cd "$PROJECT_DIR"
  /usr/bin/xcodebuild \
    -project MyShell.xcodeproj \
    -scheme MyShell \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$PERSONAL_DERIVED_DATA" \
    -disableAutomaticPackageResolution \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build
  test -d "$PERSONAL_APP_PATH"
  /usr/bin/lipo -archs "$PERSONAL_APP_PATH/Contents/MacOS/MyShell" \
    | /usr/bin/grep -qx "arm64"
  test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$PERSONAL_APP_PATH/Contents/Info.plist")" = "14.0"
  /usr/bin/ditto -c -k --keepParent "$PERSONAL_APP_PATH" "$ZIP_PATH"
  /usr/bin/shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
  echo "Created unsigned personal build: $ZIP_PATH"
  echo "Checksum: $ZIP_PATH.sha256"
}

case "$MODE" in
  personal)
    personal_build
    ;;
  archive)
    archive_app
    ;;
  notarize)
    notarize_app
    ;;
  verify)
    verify_app "$APP_PATH"
    ;;
  *)
    echo "usage: $0 [personal|archive|notarize|verify]" >&2
    exit 2
    ;;
esac
