# TokenGauge Agent Guide

## Product

- Native macOS 14+ menu bar app for Claude Code and Codex plan usage.
- SwiftPM app, Apple Silicon only for local packaging.
- Bundle ID: `com.stevenacz.TokenGauge`.
- The app never reads OAuth tokens or API keys, and never extracts or persists prompt or response content.

## Data Contracts

- Codex data comes from the local `codex app-server` stable account methods.
- Keep app-server stdin open through responses 3 and 4, read ready pipe bytes with `poll` + `Darwin.read`, then close stdin and prove the child exits.
- Claude quota data comes from the official status-line `rate_limits` payload and is reduced to percentages and reset timestamps by `TokenGaugeCapture`.
- Claude activity reads only timestamps, message IDs, and numeric usage fields from local JSONL transcripts.
- Claude history scans run only in the short-lived `TokenGaugeCapture --history` helper; scanning JSONL in the resident app retained hundreds of megabytes after completion.
- Persist normalized metrics only under `~/Library/Application Support/TokenGauge` with user-only permissions.
- Missing or stale provider data must remain visible and honest. Never fabricate usage.

## Architecture

- Keep parsing and history aggregation in `TokenGaugeCore`.
- Keep process execution, AppKit lifecycle, and UI in `TokenGaugeApp`.
- Keep the status-line helper minimal and dependent only on `TokenGaugeCore`.
- Use `NSStatusItem` + lazy `NSPopover`; release the hosting controller when the popover closes.
- No continuous menu bar or hidden-popover animations.
- Centralize visual constants in `Theme.swift`.
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
