#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$HOME/Applications/TokenGauge.app"
SIGN_IDENTITY="${TOKENGAUGE_SIGN_IDENTITY:-${SIGN_IDENTITY:-}}"

if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -p codesigning -v | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    printf "install-dev: no Apple Development signing identity found.\n" >&2
    exit 65
fi

cd "$ROOT_DIR"
SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/build_and_run.sh install
if [[ "${TOKENGAUGE_INSTALL_CLAUDE_STATUSLINE:-0}" == 1 ]]; then
    ./scripts/install_claude_statusline.sh
fi

SIGNING_DETAILS="$(codesign -dvvv "$APP_PATH" 2>&1 || true)"
if ! grep -q "Authority=Apple Development" <<<"$SIGNING_DETAILS"; then
    printf "install-dev: app is not signed with Apple Development.\n" >&2
    exit 65
fi
if ! grep -q "^TeamIdentifier=" <<<"$SIGNING_DETAILS"; then
    printf "install-dev: app has no TeamIdentifier.\n" >&2
    exit 65
fi

CDHASH="$(sed -n 's/^CDHash=//p' <<<"$SIGNING_DETAILS" | head -1)"
printf "install-dev: installed CDHash=%s at %s\n" "${CDHASH:-unknown}" "$APP_PATH"
