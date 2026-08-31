#!/usr/bin/env bash
set -euo pipefail

STATUS_SCRIPT="${CLAUDE_STATUSLINE_SCRIPT:-$HOME/.claude/statusline-command.sh}"

if [[ ! -f "$STATUS_SCRIPT" ]]; then
    printf "claude-statusline: script not found at %s\n" "$STATUS_SCRIPT" >&2
    exit 66
fi
if grep -qF 'TokenGauge.app/Contents/MacOS/TokenGaugeCapture' "$STATUS_SCRIPT"; then
    printf "claude-statusline: TokenGauge capture is already installed\n"
    exit 0
fi
if ! grep -qxF 'input=$(cat)' "$STATUS_SCRIPT"; then
    printf "claude-statusline: expected input capture line was not found\n" >&2
    exit 65
fi

temporary_file="$(mktemp "${STATUS_SCRIPT}.tokengauge.XXXXXX")"
cleanup() {
    rm -f "$temporary_file"
}
trap cleanup EXIT

awk '
{ print }
$0 == "input=$(cat)" {
    print "capture_binary=\"$HOME/Applications/TokenGauge.app/Contents/MacOS/TokenGaugeCapture\""
    print "if [ -x \"$capture_binary\" ]; then"
    print "  printf '\''%s'\'' \"$input\" | \"$capture_binary\" >/dev/null 2>&1 &"
    print "fi"
}
' "$STATUS_SCRIPT" >"$temporary_file"

bash -n "$temporary_file"
file_mode="$(stat -f '%Lp' "$STATUS_SCRIPT")"
chmod "$file_mode" "$temporary_file"
backup_file="${STATUS_SCRIPT}.bak-tokengauge-$(date +%Y%m%d%H%M%S)"
cp -p "$STATUS_SCRIPT" "$backup_file"
mv "$temporary_file" "$STATUS_SCRIPT"
trap - EXIT
printf "claude-statusline: installed capture; backup at %s\n" "$backup_file"
