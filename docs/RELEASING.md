# Releasing TokenGauge

## Distribution contract

Public artifacts target Apple Silicon on macOS 14+. Local installations remain Apple Development-signed and do not use the public update feed. Distribute only Developer ID-signed, notarized release artifacts.

The release version is `CFBundleShortVersionString` in `Resources/Info.plist`. Increment `CFBundleVersion` for every update; Sparkle compares the build number. `APP_VERSION` and `APP_BUILD` override these values for staging and local QA.

## Before publication

1. Run `make ci-check` and review the complete Git diff.
2. Scan both Git history and the intended public tree for secrets and private data. Exclude generated build output from the public source tree; inspect both distributed executables for personal build paths.
3. Exercise a clean Mac without provider CLIs: no crash, no invented quota, clear setup links, working Settings/About, language switching, and relaunch. Then check a signed-in Mac without changing its provider credentials.
4. Verify a real Sparkle update with two development builds, including a tampered ZIP rejection, retry, installation/relaunch, and preserved preferences.
5. Update CHANGELOG.md, screenshots, and release notes. Use synthetic data for public screenshots.

## Build artifacts

Prerequisites: an Apple Developer membership, an installed Developer ID Application certificate, `create-dmg`, and an existing `notarytool` Keychain profile. Signing/private-key access and public publication follow the owner’s authorization; never export credentials into the repository or logs.

```sh
TOKENGAUGE_NOTARY_PROFILE=your-profile make package-release
```

Set `TOKENGAUGE_SIGN_IDENTITY` explicitly if multiple matching identities are installed. The pipeline re-signs Sparkle’s nested executables with the application’s distribution identity, notarizes and staples the app before creating its update ZIP, then notarizes and staples the DMG. It checks the embedded EdDSA public key against the existing Sparkle signing key before signing updates.

Artifacts go to `dist/release-artifacts/`:

- `TokenGauge-<version>.dmg`
- `TokenGauge-<version>.zip`
- `appcast.xml`

`make verify-release ARTIFACT=...` checks an app, DMG, or ZIP. The pipeline fails on existing output artifacts instead of silently replacing a previously reviewed release.

Publish all three files on the same GitHub release, tagged `v<version>`. The feed is `https://github.com/StevenACZ/TokenGauge/releases/latest/download/appcast.xml`. Verify the downloaded artifacts’ SHA-256 hashes, signing, notarization, and appcast URLs after publication. A release without the ZIP and appcast cannot update existing installations.

## Local update QA

Build a development baseline and a higher build into separate `TOKENGAUGE_OUTPUT_DIR` directories. Sign a ZIP of the higher development build with Sparkle’s existing `sign_update`; construct an appcast containing its exact byte length and signature. Serve it from a loopback HTTP server on the test Mac.

Launch the baseline with both:

```sh
TOKENGAUGE_QA_UPDATES=1
TOKENGAUGE_UPDATE_FEED_URL=http://127.0.0.1:8000/appcast.xml
```

Only a loopback HTTP feed is accepted for this explicit QA override. Normal development launches disable updates. Test through About using real input, verify the higher build relaunches with the same Apple Development signing identity, then restore the real version and remove task-owned QA artifacts/server. Do not copy production credentials or user usage history to a test Mac.

## Repository visibility

Review the entire history before changing a private repository to public. Permission to prepare a release does not by itself prove that publication has occurred. Record the live visibility and release URL after the owner-authorized publication step. Keep generated artifacts and signing material out of Git.
