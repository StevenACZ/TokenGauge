#!/bin/bash
set -euo pipefail
cd -P "$(dirname "$0")/.."
plist="${1:?Usage: verify-update-key.sh Info.plist}"
generator="${TOKENGAUGE_SPARKLE_BIN:-$PWD/.build/artifacts/sparkle/Sparkle/bin}/generate_keys"
embedded="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")"
signing="$("$generator" -p)"
[[ -n "$embedded" && "$embedded" == "$signing" ]] || {
    echo 'The update signing key does not match the public key embedded in the app.' >&2
    exit 65
}
echo 'Embedded update key matches the signing key.'
