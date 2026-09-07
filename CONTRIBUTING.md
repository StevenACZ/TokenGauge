# Contributing

Keep changes small and native to SwiftUI/AppKit. Read AGENTS.md for data and performance contracts, then run `make ci-check` before submitting a pull request.

Use synthetic numeric fixtures in tests. Never contribute personal usage caches, SQLite databases, raw transcripts, credentials, account identifiers, or private screenshots.

Visible text belongs in both English and Spanish localization files. UI changes should include a screenshot with synthetic data and a check for clipping at the supported window size. Keep idle menu-bar work event-driven; do not add continuous animations or polling just to redraw unchanged state.

Report bugs with app/macOS versions, the selected provider, expected behavior, and a redacted reproduction. Provider authentication and quota availability can change independently of the app.
