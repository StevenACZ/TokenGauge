# TokenGauge Agent Guide

## Product

- Native macOS 14+ menu bar app for Claude Code and Codex plan usage.
- The panel has Codex, Claude Code and Unified views. The persisted display mode scopes both quota cards and chart, and controls one or two menu-bar indicators. Existing primary-provider preferences migrate without changing the user's choice.
- SwiftPM app, Apple Silicon only for local packaging.
- Bundle ID: `com.stevenacz.TokenGauge`.
- The app reads the Claude Code OAuth access token from the Keychain to call one read-only usage endpoint (Steven authorized this on 2026-08-25; before that the app read no credential at all). It never reads API keys and never extracts or persists prompt or response content.

## Data Contracts

- Codex data comes from the local `codex app-server` stable account methods.
- Keep app-server stdin open through responses 2, 3 and 4, read ready pipe bytes with `poll` + `Darwin.read`, then close stdin and prove the child exits.
- Claude quota data comes from `GET https://api.anthropic.com/api/oauth/usage`, the endpoint `/usage` itself calls, with `Authorization: Bearer` and `anthropic-beta: oauth-2025-04-20`. Parse the `limits` array (`session`, `weekly_all`, `weekly_scoped` with `scope.model.display_name`), not the legacy top-level buckets: the model-scoped weekly limit exists only there.
- **Never refresh, rotate, or write the OAuth credential.** Read the Keychain item (`Claude Code-credentials` / the login name) through `/usr/bin/security find-generic-password -w` as a subprocess, never `SecItemCopyMatching` from the app: Claude Code recreates the item on every token refresh, which drops the ACL grant Steven gave TokenGauge, so the direct read re-prompted him after every refresh (2026-08-26/27) even with "Always Allow"; `security` is the item creator and reads silently. Keep the token only in process memory (`ClaudeOAuthTokenReader` cache), read once per launch and re-read only after it expires. Claude Code owns that credential and refreshes it; a refresh from here would rotate the refresh token and sign Steven out. An expired token is a distinct recoverable state. With persisted opt-in, TokenGauge may briefly start the official Claude CLI in safe mode without a prompt, then re-read the credential and usage endpoint; Claude Code alone renews it. Bound the owned process group, discard terminal output, and persist retry backoff. Missing credentials, 401 revocation, and 403 must never trigger that startup.
- Call the usage endpoint through an ephemeral `URLSession` with no URL cache: `URLSession.shared` cached a 401 and replayed it (`cache_hit=true`) on every refresh while the token was valid, so the Fable row vanished (2026-08-26). On a real 401, invalidate the token cache and re-read the Keychain once — Claude Code rotates the token.
- Persist only percentages and reset timestamps from that response. The token, the account fields, and the spend figures never reach disk.
- The status-line `rate_limits` payload stays as the credential-free fallback through `TokenGaugeCapture`. It carries only the session and all-models windows, so the Fable row is absent while the fallback is in use — leave it absent rather than estimating it.
- Claude activity reads only timestamps, message IDs, model identifiers, and numeric usage fields from local JSONL transcripts, aggregated into hourly per-model buckets.
- The official status line exposes only the `five_hour` and `seven_day` buckets. There is no per-model quota bucket, so per-model figures always come from local transcripts and are labelled as token totals, never as quota.
- Codex Spark buckets are hidden through `WindowVisibility`; Luna reserve visibility is separately user-controlled, enabled by default, and never changes the general menu-bar balance. The cache keeps every bucket the app-server returns.
- Claude windows are classified by `ClaudeWindowKind` (session, weekly, model weekly). Hidden kinds only leave the panel and the store always keeps at least one visible; `claudeMenuBarSource` picks the menu-bar window explicitly, `automatic` keeps the tightest-weekly rule. Both persist in UserDefaults.
- Claude history scans run only in the short-lived `TokenGaugeCapture --history` helper; scanning JSONL in the resident app retained hundreds of megabytes after completion.
- Persist normalized metrics only under `~/Library/Application Support/TokenGauge` with user-only permissions.
- Missing or stale provider data must remain visible and honest. A failed live read never becomes ready because the fallback is recent; hide historical balances from the current menu-bar percentage. The Claude panel may retain unexpired historical rows only with an explicit last-reading label; mixed capture/account fallback must use its oldest observation time. Never substitute the general weekly limit when a selected model limit is absent. HTTP 401 means authentication required, 402/403 means no access, and neither proves subscription cancellation. Manual cancellation is independent per provider and preserves history and primary selection. Reactivation requires a successful live quota read plus newly increased daily activity after a persisted post-cancellation baseline; the first live read only establishes that baseline. Claude may also resume from its existing newer status-line activity proof. Cached or failed reads never initialize or trigger reactivation. Require `activityReadSucceeded` independently of quota validity and a capture timestamp after cancellation; timestamp Codex reads at request start so in-flight older observations cannot establish a baseline.
- Every successful refresh archives into the local SQLite history at `~/Library/Application Support/TokenGauge/usage-history.sqlite` (mode 0600) through `UsageHistoryStore`, off the main actor and best-effort: an archive failure must never block or alter the panel. `quota_samples` keeps percentages and reset instants collapsed into 15-minute buckets and pruned after `quotaRetentionDays`; `daily_tokens` keeps one row per (day, provider, model) and only ever grows (`MAX`), so trimmed transcripts cannot erase recorded history. Codex account totals use the model key `all`; local effort events can supply separate model detail. Never store tokens, account fields, prompts, or responses there.
- Archive quota only from successful original provider results with a capture timestamp, never from mixed UI fallbacks. Archive tokens independently after a successful activity read. Preserve explicit zero days; missing days remain unknown. Never fill missing Claude days from an empty scan.
- Effort scans run in the bounded `TokenGaugeCapture --record-effort-history` subprocess, never the resident UI. Decode only allowlisted metadata; hash response IDs before storage. Deduplicate events using MAX counters and preserve known model/effort values. The daily total is MAX(provider aggregate, summed model rows, summed effort events), never a sum of overlapping sources. Effort events and daily totals have no expiry.
- Weekly pace requires at least three verified, same-reset observations spanning 30 minutes within the last hour, with a latest reading no older than 20 minutes. Reset, decrease, invalid reading, or a gap over 30 minutes breaks continuity. Legacy quota rows remain unverified. Never attribute quota pace to a reasoning effort from token counts.
- History queries run off the main actor and load only the selected date range; hover and selection never query SQLite or scan logs. Calendar weeks begin Monday. Unknown days must not become zero-use days. Preview/test stores must never read or write the real user history.
- History selection changes only on click or explicit navigation; layout/scroll/refresh must not select the date beneath a stationary cursor. The annual view centers today on entry and on Today, preserves the viewport during refresh, and highlights today independently of selection. Verify real opening, past-date selection, Today and refresh; use `.scrollIndicators(.never)` for the panel/calendar to suppress legacy scroller gutters.
- Query the history with `scripts/usage_history.sh {status|daily|models|weekly|monthly|quota|export|sql}`; the `daily_totals`, `weekly_totals` (ISO week Monday) and `monthly_totals` views exist so both Steven and an agent read the same aggregation.

## Architecture

- Keep parsing and history aggregation in `TokenGaugeCore`.
- Keep process execution, AppKit lifecycle, and UI in `TokenGaugeApp`.
- Keep the status-line helper minimal and dependent only on `TokenGaugeCore`.
- Use `NSStatusItem` + lazy `NSPopover`; release the hosting controller when the popover closes.
- Never leave `popover.animates = false` in steady state: AppKit closes a `.transient` popover on the mouse-down of the status item click, before `togglePopover` runs, so a parked `false` makes that close instant. Disable animation only around the silent re-anchor `show()` and restore it in the same turn.
- No continuous menu bar or hidden-popover animations. The seven-day chart uses one or two native bars per day according to display mode and per-day hover/click targets; hidden providers never affect its legend, summary or scale; never rebuild its data for every cursor pixel. Skip status-item image/title assignment when unchanged.
- Panel style and menu-bar style persist independently; existing installs default to classic panels and numeric indicators. Compact/ring styles retain exact quota and reset data, historical provenance, and provider/window selection. Graphics never show stale values as live; exact menu values remain in tooltip/accessibility. Animations are brief, event-driven, optional, and honor Reduce Motion.
- Ring grids must cap columns at the number of visible windows and distribute the occupied row across the card. Two quotas must never leave a reserved third slot; cover this with a wide two-cell render check. Unified ring width follows visible quotas within its bounds.
- Centralize visual constants in `Theme.swift`; individual panels are 340 pt wide and Unified is 560 pt wide; all stay under 500 pt tall. Individual views show only their own provider; Unified shows two titled cards side by side. Scroll only when real provider content exceeds its bounded height.
- The popover closes on any click outside it: `.transient` alone does not dismiss an accessory app's popover when the click lands in another application (Steven, 2026-08-27). `StatusItemController` arms a global mouse-down monitor plus `didResignActiveNotification` while the popover is shown and tears both down in `popoverDidClose`. Keep the monitor to MOUSE events only — a global key monitor would demand Accessibility, which this app must never request.
- Reset lines scale with distance: under an hour shows minutes plus the clock time, under a day shows hours plus the clock time, the next calendar day shows `mañana` plus the clock time, and anything further shows whole days only. Far distances count the real remaining duration, never midnight crossings — 3.4 days away reads `3 d`, not `4 d`.
- The all-models weekly row never repeats a family that already owns its own scoped weekly row: `ProviderCard` passes those families to `ModelActivity.chips(excludingFamilies:)`, so `Semanal` and `Fable semanal` report disjoint token totals.
- The header refresh button is the ONLY refresh affordance. Never put a circular-arrow glyph on a quota row, a reset time, or a credit pill: the store refreshes every five minutes and the panel must not look like it needs clicking (Steven, 2026-08-25).
- The menu bar uses one provider brand and percentage in individual views, or both independent segments in Unified. Codex uses only the general `codex.*` bucket, never the `base_model_inference` / `gpt-reserve` counter; the reserve must not be added to general quota or assigned undocumented model coverage. Claude uses the tightest model-scoped weekly window, falling back to all-models weekly. Keep `NSStatusItem.variableLength` and let AppKit size it. **Never assign `NSStatusItem.length` from a measurement taken in the same runloop turn as the content change** — it clips the content it was measured from (lesson `tokengauge-statusitem-length-clips-title`).
- Resolve the title colour against `button.effectiveAppearance` and redraw on `NSApp.effectiveAppearance` changes; the image is not a template, so nothing adapts on its own.
- `cacheDisplay` does not capture an `NSButton` title. To prove the percentage renders, compare `button.frame.width` with the title set against the width with an empty title.
- Localize all visible strings in English and Spanish.
- Manually sized Settings/About windows use `NSHostingView.sizingOptions = []` and a bounded scroll surface. Never combine manual window sizing with content-driven hosting constraints; macOS 26 can crash during update UI transitions. Verify the installed app, since XCTest does not reproduce the display-cycle assertion.
- Resolve resources from packaged or executable-adjacent bundles; never reference `Bundle.module` in shipped code because its generated fallback embeds the builder's private path. Verify both executables with `strings` before release.
- Settings owns language, login, provider setup and automatic update checks. About owns manual update checks and release notes; available updates also appear inline in the panel.
- Public updates use Sparkle signatures and notarized Developer ID artifacts. Development builds stay off the public feed except explicit loopback QA. Never export signing keys.

## Safety

- Preparing a public release does not authorize publishing it. Repository visibility changes, release publication, release tags and assets require explicit publication authorization; preparation or signing approval alone is insufficient.
- UI iteration is M4-only for Steven to review. Broader QA, documentation screenshots, and public release publication require his explicit scope approval.

- Do not log or persist raw JSONL lines, prompts, responses, account identifiers, emails, tokens, or credentials.
- Do not invoke a model request to refresh usage.
- Do not scrape provider web pages.
- Do not request Accessibility, Automation or Full Disk Access. Claude uses its existing read-only Keychain credential; explain the system access prompt if its ACL requires one.
- Launch at login is opt-in through `SMAppService.mainApp`.
- Keep local installs signed with Apple Development.
- All implementation uses a topic branch and PR. Never push directly to `main` or bypass its protection: GitHub Actions `check` must pass on an up-to-date branch, conversations must be resolved, and the rules apply to admins. Steven approves the final local UI before merge/release; no force-push or branch deletion without authorization.

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
- Exercise the history database against the live file with `scripts/usage_history.sh status` after UI or store work.
- Verify the installed signature contains `Authority=Apple Development` and a TeamIdentifier.
- After UI work, inspect a real popover screenshot and sample idle CPU.
