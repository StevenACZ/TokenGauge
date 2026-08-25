# TokenGauge

TokenGauge is a native macOS menu bar app for Claude Code and Codex plan usage.

It reads Codex metrics through the local official app-server protocol. Claude Code quota snapshots are captured from the official status-line payload, while local activity totals decode only transcript timestamps, message IDs, model identifiers, and numeric token counters. TokenGauge never reads provider credentials or extracts, logs, or persists prompt and response content.

The panel shows the Claude five-hour window, the all-models weekly window and every model-scoped weekly window the plan defines, the Codex mainline weekly window, per-model token totals for each Claude window, and a seven-day activity chart.

## Local development

```bash
make ci-check
make install-dev
```

The development installer requires an Apple Development signing identity and installs the app to `~/Applications/TokenGauge.app`.

`make install-dev` also adds an idempotent, allowlisted capture call to the existing Claude Code status-line script. The helper persists only quota percentages and reset timestamps. It never stores the rest of the status-line payload.
