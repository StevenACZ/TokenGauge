#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
mode="${1:-stage}"
case "$mode" in stage|run|install|verify) ;; *) echo "Usage: $0 [stage|run|install|verify]" >&2; exit 64 ;; esac
distribution="${TOKENGAUGE_DISTRIBUTION:-0}"
[[ "$distribution" == 0 || "$mode" == stage ]] || exit 64
[[ "$distribution" == 0 || "$distribution" == 1 ]] || exit 64
output_dir="${TOKENGAUGE_OUTPUT_DIR:-$PWD/dist}"
if [[ "$distribution" == 1 && -z "${TOKENGAUGE_OUTPUT_DIR:-}" ]]; then
    output_dir="$PWD/dist/distribution"
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"
output="$output_dir/TokenGauge.app"
ensure_build_closed() {
    for tokengauge_pid in $(pgrep -x TokenGauge || true); do
        if [[ "$(ps -p "$tokengauge_pid" -o comm=)" == "$output/Contents/MacOS/TokenGauge" ]]; then
            echo 'Quit the build copy of TokenGauge before rebuilding it.' >&2
            exit 75
        fi
    done
}
ensure_build_closed
swift build -c "${CONFIG:-release}" --arch arm64 \
    -Xswiftc -file-prefix-map -Xswiftc "$PWD=." \
    -Xswiftc -gnone
bundle_stage="$(mktemp -d "$output_dir/.tokengauge-bundle.XXXXXX")"
trap 'rm -rf "$bundle_stage"' EXIT
bundle="$bundle_stage/TokenGauge.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
bin_dir="$(swift build -c "${CONFIG:-release}" --arch arm64 --show-bin-path)"
cp "$bin_dir/TokenGaugeApp" "$bundle/Contents/MacOS/TokenGauge"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
mkdir -p "$bundle/Contents/Resources/Licenses"
cp LICENSE "$bundle/Contents/Resources/Licenses/TokenGauge.txt"
cp docs/licenses/Sparkle.txt "$bundle/Contents/Resources/Licenses/"
cp "$bin_dir/TokenGaugeCapture" "$bundle/Contents/MacOS/TokenGaugeCapture"
ditto "$bin_dir/TokenGauge_TokenGaugeApp.bundle" "$bundle/Contents/Resources/TokenGauge_TokenGaugeApp.bundle"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' "$bundle/Contents/Info.plist"
plist="$bundle/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    [[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 64
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$plist"
fi
if [[ -n "${APP_BUILD:-}" ]]; then
    [[ "$APP_BUILD" =~ ^[1-9][0-9]*$ ]] || exit 64
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$plist"
fi
/usr/libexec/PlistBuddy -c 'Delete :TokenGaugeDevelopmentBuild' "$plist" 2>/dev/null || true
if [[ "$distribution" == 1 ]]; then development=false; else development=true; fi
/usr/libexec/PlistBuddy -c "Add :TokenGaugeDevelopmentBuild bool $development" "$plist"
frameworks=(.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework)
[[ ${#frameworks[@]} == 1 && -d "${frameworks[0]}" ]] || {
    echo 'Expected exactly one Sparkle macOS framework.' >&2; exit 66;
}
mkdir -p "$bundle/Contents/Frameworks"
ditto "${frameworks[0]}" "$bundle/Contents/Frameworks/Sparkle.framework"
binary="$bundle/Contents/MacOS/TokenGauge"
while IFS= read -r rpath; do
    if [[ "$rpath" == /* ]]; then install_name_tool -delete_rpath "$rpath" "$binary"; fi
done < <(otool -l "$binary" | awk '/cmd LC_RPATH/ {getline; getline; sub(/^ *path /, ""); sub(/ \(offset.*$/, ""); print}')
strip -S "$binary"
if [[ "$distribution" == 1 ]]; then authority='Developer ID Application'; else authority='Apple Development'; fi
identity="${TOKENGAUGE_SIGN_IDENTITY:-${SIGN_IDENTITY:-}}"
if [[ -z "$identity" ]]; then
    identities=()
    while IFS= read -r candidate; do identities+=("$candidate"); done < <(
        security find-identity -v -p codesigning | awk -F '"' -v kind="$authority" 'index($2, kind ":") == 1 {print $2}'
    )
    [[ ${#identities[@]} == 1 ]] || {
        echo "Expected one $authority identity; set TOKENGAUGE_SIGN_IDENTITY explicitly." >&2; exit 65;
    }
    identity="${identities[0]}"
fi
flags=(--force --options runtime --sign "$identity")
if [[ "$distribution" == 1 ]]; then flags+=(--timestamp); else flags+=(--timestamp=none); fi
framework="$bundle/Contents/Frameworks/Sparkle.framework"
for nested in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app Autoupdate; do
    codesign "${flags[@]}" --preserve-metadata=entitlements "$framework/Versions/B/$nested"
done
codesign "${flags[@]}" "$framework"
codesign "${flags[@]}" "$bundle/Contents/MacOS/TokenGaugeCapture"
codesign "${flags[@]}" "$bundle"
codesign --verify --deep --strict "$bundle"
codesign -dvv "$bundle" 2>&1 | awk -v kind="$authority" 'index($0, "Authority=" kind ":") == 1 {found=1} END {exit !found}'

ensure_build_closed
if [[ -e "$output" ]]; then mv "$output" "$bundle_stage/previous.app"; fi
if ! mv "$bundle" "$output"; then
    if [[ -e "$bundle_stage/previous.app" ]]; then mv "$bundle_stage/previous.app" "$output"; fi
    exit 74
fi
echo "Built and verified: $output"

if [[ "$mode" == install ]]; then
    installed="$HOME/Applications/TokenGauge.app"
    pkill -x TokenGauge >/dev/null 2>&1 || true
    mkdir -p "$HOME/Applications"
    backup="$(mktemp -d "$HOME/Applications/.tokengauge-install.XXXXXX")"
    if [[ -e "$installed" ]]; then mv "$installed" "$backup/TokenGauge.app"; fi
    if ! ditto "$output" "$installed" || ! codesign --verify --deep --strict "$installed"; then
        rm -rf "$installed"
        if [[ -e "$backup/TokenGauge.app" ]]; then mv "$backup/TokenGauge.app" "$installed"; fi
        rm -rf "$backup"
        exit 74
    fi
    rm -rf "$backup"
    open -n "$installed"
elif [[ "$mode" == run || "$mode" == verify ]]; then
    open -n "$output"
    if [[ "$mode" == verify ]]; then sleep 2; pgrep -x TokenGauge >/dev/null; fi
fi
