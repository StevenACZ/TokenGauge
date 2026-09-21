# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.0] - 2026-09-20

### Added

- Weekly reset dates in the activity calendar, with provider colors, local times, and expected dates for later weeks. Cancelling tracking removes that provider's forecast.

### Changed

- Coincident weekly quotas share a compact reset card without repeated labels or empty activity details.
- The unified ring panel fits one Codex ring alongside three Claude quota rings.
- Current and best streaks appear above the calendar, keeping the daily summary focused on usage.

### Fixed

- Automatic reconnection aligns with the other provider settings switches.

## [1.4.0] - 2026-09-18

### Added

- Quota ring cards that switch between one large ring, a grid, or compact rows according to the visible windows and the available width, keeping three Claude windows with model chips and pace lines fully readable.
- A calendar day card, shown by holding the pointer over a day or pinned with a click, with per-provider icons, tokens, percentages, model detail, and current and best streaks.
- Five calendar intensity levels derived from usage quantiles, so more color means more usage.
- An in-panel update banner with real download and extraction progress, followed by Install now or Later.
- A persistent Install button in the panel and in About after choosing Later, preserved across relaunches.

### Changed

- The yearly calendar now shows combined activity in the Codex, Claude, and Unified views.
- Calendar selection follows the pointer and returns to today when the pointer leaves the calendar; Esc, a click outside, scrolling, or changing view dismisses a pinned day card.
- The standard panel moves Settings, About, and Quit into a header gear menu instead of footer rows.
- Manual update checks are available in About whenever no update is in progress.
- Faster refreshes: transcripts are scanned incrementally with a resume file, a single capture pass replaces two, Claude activity and account data are read concurrently within a 12-second network limit, and each provider's card appears as soon as its own data is ready.
- Update feed overrides are accepted only over HTTPS.

### Fixed

- Claude readings, history, and pace continuity are scoped to the signed-in account, and Claude helper commands run in a private working directory.
- A refresh stays marked as busy until local archiving finishes.
- Local history read handles are closed when the database reports a schema error.
- Daily totals use the Gregorian calendar regardless of the system calendar setting.

## [1.3.0] - 2026-09-13

### Added

- Navigable weekly history and a yearly activity calendar, with local model and reasoning effort token details.
- Provider-colored calendar days, distinct month blocks, and highlighted Saturday/Sunday rows.
- Optional weekly quota pace estimates with a clickable explanation, dated recent and previous readings, and local persistence across idle periods and app restarts.
- Optional compact and ring quota panels that adapt to visible limits, plus independent mini-bar and mini-ring menu indicators with integrated provider logos.
- Appearance settings and a panel view picker, with brief optional transitions that respect Reduce Motion.
- Optional automatic Claude reconnection after session expiry, with one-time consent, bounded retries, and no model requests.

### Changed

- Consistent spacing between quota titles, rings, and reading details in individual and Unified cards.

### Fixed

- Show the history Today badge only on the current date, with a stable, animated summary when changing selection.
- Keep local quota history tied to verified readings and preserve explicitly reported zero-token days without inventing missing observations.
- Preserve clearly marked last-known Claude limits during temporary connection failures, including model weekly usage.
- Keep Codex readings responsive while Claude reconnects, and never substitute a different quota for a selected model limit.

## [1.2.0] - 2026-09-10

### Added

- Claude settings to show or hide the 5h session, weekly and model weekly windows in the panel, and to choose which of them the menu bar shows.

### Fixed

- Close the panel with its fade animation when the menu bar icon is clicked again.

## [1.1.0] - 2026-09-07

### Added

- Large, Medium, and Small menu-bar sizes, remembered between launches.
- Provider icons in the Settings view selector.

### Changed

- Roomier individual panels, clearer provider branding, and more space between Unified menu-bar balances.
- Move Luna reserve visibility into the Codex settings card and align provider switches.
- Explain the difference between confirmed access and manually marked subscription cancellation.
- Refresh documentation images to match the updated interface.

### Fixed

- Keep today's chart label highlighted while inspecting other days.
- Center a day's single active provider bar in Unified view.
- Keep the popover anchored after size and provider changes without redundant repositioning animations.
- Keep long quota lists within the compact panel height, including update states.
- Show a sign-in state when Codex explicitly reports that authentication is required, preserving history.

## [1.0.0] - 2026-09-07

### Added

- Separate Codex and Claude Code views, plus a Unified view with both menu-bar balances and scoped seven-day token charts.
- Independent cancellation tracking for either provider, preserving history and resuming only after confirmed access and new activity.
- A setting to hide the separate Luna weekly reserve.
- Native About and Settings windows with provider setup links and privacy guidance.
- Signed Sparkle updates with daily checks, inline installation, and manual checks in About.
- Public distribution packaging, dependency notices, and contributor documentation.

### Changed

- Larger provider icon and percentage in the menu bar.
- Portable bundled resources and first-launch system language selection.
- Development installation leaves Claude Code configuration untouched unless explicitly requested.

### Fixed

- Bounded credential and provider subprocess reads so a stalled child cannot hang a refresh indefinitely.
