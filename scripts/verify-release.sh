#!/bin/bash
set -euo pipefail
input="${1:?Usage: verify-release.sh APP|DMG|ZIP}"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/tokengauge-verify.XXXXXX")"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        if ! hdiutil detach "$workspace/mount" >/dev/null; then
            echo "Could not detach verification volume: $workspace/mount" >&2
            return
        fi
    fi
    rm -rf "$workspace"
}
trap cleanup EXIT
verify_app() {
    local app="$1" details plist version build
    plist="$app/Contents/Info.plist"
    for license in TokenGauge Sparkle; do
        [[ -s "$app/Contents/Resources/Licenses/$license.txt" ]]
    done
    codesign --verify --deep --strict "$app"
    details="$(codesign -dvv "$app" 2>&1)"
    grep -q '^Authority=Developer ID Application:' <<< "$details"
    grep -q '^Timestamp=' <<< "$details"
    grep -q 'flags=.*runtime' <<< "$details"
    codesign -d --entitlements :- "$app" > "$workspace/entitlements.plist" 2>/dev/null
    python3 - "$workspace/entitlements.plist" "$plist" <<'PYVERIFY'
import pathlib
import plistlib
import sys
entitlements = pathlib.Path(sys.argv[1]).read_bytes()
if entitlements and plistlib.loads(entitlements).get('com.apple.security.get-task-allow', False):
    raise SystemExit('Release app allows debugging')
with open(sys.argv[2], 'rb') as stream:
    info = plistlib.load(stream)
if not info.get('SUPublicEDKey') or not info.get('SUFeedURL', '').startswith('https://'):
    raise SystemExit('Release update configuration is missing')
PYVERIFY
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :TokenGaugeDevelopmentBuild' "$plist")" == false ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == com.stevenacz.TokenGauge ]]
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]]
    [[ -z "${APP_VERSION:-}" || "$version" == "$APP_VERSION" ]]
    [[ -z "${APP_BUILD:-}" || "$build" == "$APP_BUILD" ]]
    for executable in TokenGauge TokenGaugeCapture; do
        local binary="$app/Contents/MacOS/$executable"
        [[ "$(lipo -archs "$binary")" == arm64 ]]
        otool -l "$binary" > "$workspace/load-commands"
        if [[ "$executable" == TokenGauge ]]; then
            grep -Fq 'path @executable_path/../Frameworks (offset' "$workspace/load-commands"
        fi
        if awk '/cmd LC_RPATH/ {getline; getline; if ($2 ~ /^\//) found=1} END {exit !found}' "$workspace/load-commands"; then
            echo 'Absolute runtime search path in release executable.' >&2; exit 65
        fi
        strings "$binary" > "$workspace/strings"
        if LC_ALL=C grep -Eq '/Users/|/home/' "$workspace/strings"; then
            echo 'Private compilation path in release executable.' >&2; exit 65
        fi
    done
    find "$app" -name '._*' -print > "$workspace/sidecars"
    [[ ! -s "$workspace/sidecars" ]]
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
}
case "$input" in
    *.app) verify_app "$input" ;;
    *.dmg)
        codesign --verify --strict "$input"
        hdiutil verify "$input"
        xcrun stapler validate "$input"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$input"
        mkdir "$workspace/mount"
        hdiutil attach "$input" -readonly -nobrowse -mountpoint "$workspace/mount" >/dev/null
        mounted=true
        [[ -L "$workspace/mount/Applications" ]]
        verify_app "$workspace/mount/TokenGauge.app"
        ;;
    *.zip)
        unzip -Z1 "$input" > "$workspace/entries"
        if LC_ALL=C grep -Eq '(^|/)\._|(^|/)\.\.(/|$)|^/' "$workspace/entries"; then
            echo 'Invalid archive entries.' >&2; exit 65
        fi
        ditto -x -k "$input" "$workspace/extracted"
        verify_app "$workspace/extracted/TokenGauge.app"
        ;;
    *) echo 'Expected an app, DMG or ZIP.' >&2; exit 64 ;;
esac
