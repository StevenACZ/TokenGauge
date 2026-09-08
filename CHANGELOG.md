# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
