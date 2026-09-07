#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
command -v create-dmg >/dev/null
output_dir="${TOKENGAUGE_ARTIFACTS_DIR:-$PWD/dist/release-artifacts}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"
workspace="$(mktemp -d "$output_dir/.package.XXXXXX")"
trap 'rm -rf "$workspace"' EXIT
profile="${TOKENGAUGE_NOTARY_PROFILE:?Set TOKENGAUGE_NOTARY_PROFILE to your configured notarytool profile}"
TOKENGAUGE_DISTRIBUTION=1 TOKENGAUGE_OUTPUT_DIR="$workspace/staged" scripts/build_and_run.sh stage
app="$workspace/staged/TokenGauge.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 65
for artifact in "TokenGauge-$version.dmg" "TokenGauge-$version.zip" appcast.xml; do
    [[ ! -e "$output_dir/$artifact" ]] || { echo "Artifact already exists: $artifact" >&2; exit 73; }
done
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$app" "$workspace/notarize.zip"
xcrun notarytool submit "$workspace/notarize.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
scripts/verify-release.sh "$app"
dmg="$workspace/TokenGauge-$version.dmg"
create-dmg --volname TokenGauge --volicon Resources/AppIcon.icns \
    --window-pos 200 120 --window-size 600 400 --icon-size 112 \
    --text-size 14 --icon TokenGauge.app 160 185 --hide-extension TokenGauge.app \
    --app-drop-link 440 185 --no-internet-enable "$dmg" "$workspace/staged"
identity="$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p')"
[[ -n "$identity" ]] || exit 65
codesign --force --sign "$identity" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
scripts/verify-release.sh "$dmg"
TOKENGAUGE_APP_PATH="$app" TOKENGAUGE_ARTIFACTS_DIR="$workspace" scripts/generate-appcast.sh
for artifact in "TokenGauge-$version.dmg" "TokenGauge-$version.zip" appcast.xml; do
    mv "$workspace/$artifact" "$output_dir/$artifact"
done
shasum -a 256 "$output_dir/TokenGauge-$version.dmg" "$output_dir/TokenGauge-$version.zip"
