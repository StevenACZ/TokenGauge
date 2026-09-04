# TokenGauge

TokenGauge is a native macOS menu bar app for Claude Code and Codex plan usage.

It reads Codex metrics through the local official app-server protocol. Claude Code quota comes from its read-only OAuth usage endpoint, with normalized status-line data as a fallback. The existing Claude OAuth credential is read in memory and never renewed or persisted by TokenGauge. Local activity totals decode only timestamps, message IDs, model identifiers, and numeric token counters; prompt and response content is never extracted, logged, or persisted.

The panel shows the Claude five-hour window, the all-models weekly window and every model-scoped weekly window the plan defines, the Codex general weekly window and additional server-reported counters, per-model token totals for each Claude window, and a seven-day activity chart.

The provider selector controls card order and the menu bar, defaults to Codex, and persists across launches. The Codex menu bar uses only its general quota. The separate `gpt-reserve` counter (`base_model_inference`) is shown without assuming model coverage or adding percentages.

The settings menu can mark Claude's subscription as cancelled locally. This preserves the SQLite usage history and does not change billing. Automatic reactivation requires a successful quota read and status-line activity newer than the cancellation; unchecking the setting also resumes tracking. Authentication failures, denied access, temporary failures, and cancellation have separate states, and historical balances are not presented as current quota.

## Local development

```bash
make ci-check
make install-dev
```

The development installer requires an Apple Development signing identity and installs the app to `~/Applications/TokenGauge.app`.

`make install-dev` also adds an idempotent, allowlisted capture call to the existing Claude Code status-line script. The helper persists only quota percentages and reset timestamps. It never stores the rest of the status-line payload.
