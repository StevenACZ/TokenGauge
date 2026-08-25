#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-stage}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TokenGauge"
APP_PRODUCT="TokenGaugeApp"
CAPTURE_PRODUCT="TokenGaugeCapture"
CONFIG="${CONFIG:-release}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT_DIR"
swift build -c "$CONFIG" --arch arm64 --product "$APP_PRODUCT"
swift build -c "$CONFIG" --arch arm64 --product "$CAPTURE_PRODUCT"
BUILD_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_DIR/$APP_PRODUCT" "$APP_BINARY"
cp "$BUILD_DIR/$CAPTURE_PRODUCT" "$APP_MACOS/$CAPTURE_PRODUCT"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
ditto "$BUILD_DIR/TokenGauge_TokenGaugeApp.bundle" "$APP_RESOURCES/TokenGauge_TokenGaugeApp.bundle"
chmod +x "$APP_BINARY" "$APP_MACOS/$CAPTURE_PRODUCT"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_CONTENTS/Info.plist"
fi

codesign --force --sign "$SIGN_IDENTITY" "$APP_MACOS/$CAPTURE_PRODUCT"
codesign --force --sign "$SIGN_IDENTITY" "$APP_BINARY"
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

case "$MODE" in
    stage)
        printf "%s staged at %s\n" "$APP_NAME" "$APP_BUNDLE"
        ;;
    run)
        pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        /usr/bin/open -n "$APP_BUNDLE"
        ;;
    install)
        pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        mkdir -p "$HOME/Applications"
        rm -rf "$INSTALLED_APP"
        ditto "$APP_BUNDLE" "$INSTALLED_APP"
        /usr/bin/open -n "$INSTALLED_APP"
        printf "%s installed at %s\n" "$APP_NAME" "$INSTALLED_APP"
        ;;
    verify)
        pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        /usr/bin/open -n "$APP_BUNDLE"
        sleep 2
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        printf "usage: %s [stage|run|install|verify]\n" "$0" >&2
        exit 2
        ;;
esac
