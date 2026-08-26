# TokenGauge Agent Guide

## Product

- Native macOS 14+ menu bar app for Claude Code and Codex plan usage.
- The panel shows the Claude five-hour and weekly windows, the Codex mainline weekly window, and a seven-day activity chart.
- SwiftPM app, Apple Silicon only for local packaging.
- Bundle ID: `com.stevenacz.TokenGauge`.
- The app reads the Claude Code OAuth access token from the Keychain to call one read-only usage endpoint (Steven authorized this on 2026-08-25; before that the app read no credential at all). It never reads API keys and never extracts or persists prompt or response content.

## Data Contracts

- Codex data comes from the local `codex app-server` stable account methods.
- Keep app-server stdin open through responses 3 and 4, read ready pipe bytes with `poll` + `Darwin.read`, then close stdin and prove the child exits.
- Claude quota data comes from `GET https://api.anthropic.com/api/oauth/usage`, the endpoint `/usage` itself calls, with `Authorization: Bearer` and `anthropic-beta: oauth-2025-04-20`. Parse the `limits` array (`session`, `weekly_all`, `weekly_scoped` with `scope.model.display_name`), not the legacy top-level buckets: the model-scoped weekly limit exists only there.
- **Never refresh, rotate, or write the OAuth credential.** Read the Keychain item (`Claude Code-credentials` / the login name) once per launch, keep the token only in process memory (`ClaudeOAuthTokenReader` cache) and re-read only after it expires: every keychain read of an item owned by another app shows the macOS consent dialog, so per-refresh reads prompted Steven every five minutes (2026-08-26). Claude Code owns that credential and refreshes it; a refresh from here would rotate the refresh token and sign Steven out. An expired token is a skip, not a reason to renew.
- Call the usage endpoint through an ephemeral `URLSession` with no URL cache: `URLSession.shared` cached a 401 and replayed it (`cache_hit=true`) on every refresh while the token was valid, so the Fable row vanished (2026-08-26). On a real 401, invalidate the token cache and re-read the Keychain once — Claude Code rotates the token.
- Persist only percentages and reset timestamps from that response. The token, the account fields, and the spend figures never reach disk.
- The status-line `rate_limits` payload stays as the credential-free fallback through `TokenGaugeCapture`. It carries only the session and all-models windows, so the Fable row is absent while the fallback is in use — leave it absent rather than estimating it.
- Claude activity reads only timestamps, message IDs, model identifiers, and numeric usage fields from local JSONL transcripts, aggregated into hourly per-model buckets.
- The official status line exposes only the `five_hour` and `seven_day` buckets. There is no per-model quota bucket, so per-model figures always come from local transcripts and are labelled as token totals, never as quota.
- Codex Spark buckets are hidden in the panel through `WindowVisibility`; the cache keeps every bucket the app-server returns.
- Claude history scans run only in the short-lived `TokenGaugeCapture --history` helper; scanning JSONL in the resident app retained hundreds of megabytes after completion.
- Persist normalized metrics only under `~/Library/Application Support/TokenGauge` with user-only permissions.
- Missing or stale provider data must remain visible and honest. Never fabricate usage.

## Architecture

- Keep parsing and history aggregation in `TokenGaugeCore`.
- Keep process execution, AppKit lifecycle, and UI in `TokenGaugeApp`.
- Keep the status-line helper minimal and dependent only on `TokenGaugeCore`.
- Use `NSStatusItem` + lazy `NSPopover`; release the hosting controller when the popover closes.
- No continuous menu bar or hidden-popover animations.
- Centralize visual constants in `Theme.swift`; the panel is 300 pt wide and must stay under 500 pt tall.
- The header refresh button is the ONLY refresh affordance. Never put a circular-arrow glyph on a quota row, a reset time, or a credit pill: the store refreshes every five minutes and the panel must not look like it needs clicking (Steven, 2026-08-25).
- The menu bar item is the Claude brand mark plus one percentage: the tightest model-scoped weekly window, falling back to the all-models weekly one. Keep `NSStatusItem.variableLength` and let AppKit size it. **Never assign `NSStatusItem.length` from a measurement taken in the same runloop turn as the content change** — it clips the content it was measured from (lesson `tokengauge-statusitem-length-clips-title`).
- Resolve the title colour against `button.effectiveAppearance` and redraw on `NSApp.effectiveAppearance` changes; the image is not a template, so nothing adapts on its own.
- `cacheDisplay` does not capture an `NSButton` title. To prove the percentage renders, compare `button.frame.width` with the title set against the width with an empty title.
- Localize all visible strings in English and Spanish.

## Safety

- Do not log or persist raw JSONL lines, prompts, responses, account identifiers, emails, tokens, or credentials.
- Do not invoke a model request to refresh usage.
- Do not scrape provider web pages.
- Do not request Accessibility, Automation, Full Disk Access, or Keychain access.
- Launch at login is opt-in through `SMAppService.mainApp`.
- Keep local installs signed with Apple Development.
- Ask before Git staging, commits, pushes, PRs, merges, rebases, resets, or branch deletion.

## Verification

```bash
make format
make lint
make test
make build
make ci-check
make install-dev
```

- Run `git diff --check` when the directory becomes a Git repository.
- Verify the installed signature contains `Authority=Apple Development` and a TeamIdentifier.
- After UI work, inspect a real popover screenshot and sample idle CPU.
