#!/usr/bin/env bash
set -euo pipefail

DB="${TOKENGAUGE_HISTORY_DB:-$HOME/Library/Application Support/TokenGauge/usage-history.sqlite}"
COMMAND="${1:-status}"
shift || true

if [[ ! -f "$DB" ]]; then
    printf "usage-history: no database yet at %s (open TokenGauge once)\n" "$DB" >&2
    exit 66
fi

run() {
    sqlite3 -header -column "$DB" "$1"
}

case "$COMMAND" in
path)
    printf "%s\n" "$DB"
    ;;
status)
    run "SELECT
            (SELECT COUNT(*) FROM daily_tokens) AS token_rows,
            (SELECT COUNT(*) FROM quota_samples) AS quota_rows,
            (SELECT MIN(day) FROM daily_tokens) AS first_day,
            (SELECT MAX(day) FROM daily_tokens) AS last_day,
            (SELECT datetime(MAX(sampled_at), 'unixepoch', 'localtime') FROM quota_samples) AS last_sample;"
    ;;
daily)
    run "SELECT day, provider, tokens FROM daily_totals
         ORDER BY day DESC, provider LIMIT ${1:-30};"
    ;;
models)
    run "SELECT day, provider, model, tokens FROM daily_tokens
         ORDER BY day DESC, tokens DESC LIMIT ${1:-40};"
    ;;
weekly)
    run "SELECT week_start, provider, tokens FROM weekly_totals
         ORDER BY week_start DESC, provider LIMIT ${1:-26};"
    ;;
monthly)
    run "SELECT month, provider, tokens FROM monthly_totals
         ORDER BY month DESC, provider LIMIT ${1:-24};"
    ;;
quota)
    run "SELECT datetime(sampled_at, 'unixepoch', 'localtime') AS sampled,
                provider, window_id, COALESCE(display_name, '-') AS model,
                ROUND(used_percentage, 1) AS used_pct,
                datetime(resets_at, 'unixepoch', 'localtime') AS resets
         FROM quota_samples ORDER BY sampled_at DESC LIMIT ${1:-40};"
    ;;
export)
    OUT="${1:-usage-history.csv}"
    sqlite3 -header -csv "$DB" "SELECT day, provider, model, tokens FROM daily_tokens ORDER BY day, provider, model;" >"$OUT"
    printf "usage-history: wrote %s\n" "$OUT"
    ;;
sql)
    run "${1:?usage: usage_history.sh sql \"SELECT ...\"}"
    ;;
*)
    printf "usage: %s {status|daily|models|weekly|monthly|quota|export|sql|path} [argument]\n" "$(basename "$0")" >&2
    exit 64
    ;;
esac
