# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Optional automatic Claude reconnection after session expiry, with one-time consent, bounded retries, and no model requests.

### Fixed

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
