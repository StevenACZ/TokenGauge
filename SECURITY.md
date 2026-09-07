# Security and privacy

## Reporting

Do not post credentials, transcripts, account identifiers, or raw provider payloads in issues. Report vulnerabilities through GitHub’s private vulnerability reporting when available, or contact the maintainer before sharing sensitive details. Include the TokenGauge version, macOS version, and redacted reproduction steps.

## Data boundaries

TokenGauge reads local provider usage and stores only normalized metrics. It does not decode prompt/response fields, send model requests, scrape provider websites, collect analytics, or transmit usage to its own backend.

Claude’s existing OAuth access token is read from the local Keychain into process memory for a read-only provider request. It is never saved, renewed, rotated, or included in diagnostic output. A timeout or failed authentication leaves the provider unavailable; it never bypasses the Keychain or signs in on the user’s behalf.

Metrics live in the user’s Application Support directory, with directory mode 0700 and file mode 0600. The local history database is not a credential store. Removing the app does not automatically erase that history.

## Update channel

Public release updates use Sparkle 2, a bundled EdDSA public key, Developer ID signing, and notarized artifacts. The appcast and ZIP are hosted on GitHub Releases. A package without a valid update signature must be rejected. No update is installed until the user chooses the install action. Scheduled failures remain quiet; manual checks expose retry feedback.

Development builds disable the public updater. A development-only, explicitly opted-in loopback feed exists for local update QA. Never ship a development artifact as a public release.
