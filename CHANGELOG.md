# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Native About and Settings windows with provider setup links and privacy guidance.
- Signed Sparkle updates with daily checks, inline installation, and manual checks in About.
- Public distribution packaging, dependency notices, and contributor documentation.

### Changed

- Larger provider icon and percentage in the menu bar.
- Portable bundled resources and first-launch system language selection.
- Development installation leaves Claude Code configuration untouched unless explicitly requested.

### Fixed

- Bounded credential and provider subprocess reads so a stalled child cannot hang a refresh indefinitely.
