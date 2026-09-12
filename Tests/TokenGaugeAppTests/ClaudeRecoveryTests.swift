import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeRecoveryTests: XCTestCase {
    func testExpiredCredentialRecoversThenReadsEveryRealWindowAgain() throws {
        var reads = 0
        var recoveries = 0
        let expected = ClaudeAccountSnapshot(
            capturedAt: Date(),
            windows: ["five_hour", "seven_day", "seven_day_fable"].map {
                QuotaWindow(id: $0, usedPercentage: 88, resetsAt: nil, durationMinutes: nil, displayName: nil)
            })
        let result = ClaudeUsageClient.readAccount(
            fetch: {
                reads += 1
                if reads == 1 { throw ClaudeAccountUsageError.credentialExpired }
                return expected
            },
            recover: {
                recoveries += 1; return true
            })
        XCTAssertEqual(try result.get().windows, expected.windows)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(recoveries, 1)
    }

    func testMissingRevokedDeniedAndNetworkFailuresDoNotStartClaude() {
        for error in [
            ClaudeAccountUsageError.authenticationRequired, .accessDenied, .unavailable,
        ] {
            var recoveries = 0
            let result = ClaudeUsageClient.readAccount(
                fetch: { throw error },
                recover: {
                    recoveries += 1; return true
                })
            XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? ClaudeAccountUsageError, error) }
            XCTAssertEqual(recoveries, 0)
        }
    }

    func testDeclinedOrFailedRecoveryDoesNotRetryAndRetainsExpiryState() {
        var reads = 0
        let result = ClaudeUsageClient.readAccount(
            fetch: {
                reads += 1; throw ClaudeAccountUsageError.credentialExpired
            }, recover: { false })
        XCTAssertThrowsError(try result.get()) {
            XCTAssertEqual($0 as? ClaudeAccountUsageError, .credentialExpired)
        }
        XCTAssertEqual(reads, 1)
    }

    func testStartupSuccessCannotMaskARejectedUsageRequestOrLoop() {
        var reads = 0
        var recoveries = 0
        let result = ClaudeUsageClient.readAccount(
            fetch: {
                reads += 1
                throw reads == 1 ? ClaudeAccountUsageError.credentialExpired : .authenticationRequired
            },
            recover: {
                recoveries += 1; return true
            })
        XCTAssertThrowsError(try result.get()) {
            XCTAssertEqual($0 as? ClaudeAccountUsageError, .authenticationRequired)
        }
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(recoveries, 1)
    }

    func testBackoffSurvivesRelaunchAndPreventsOverlappingAttempts() {
        withDefaults { defaults in
            let recovery = ClaudeSessionRecovery(defaults: defaults)
            let now = Date()
            XCTAssertFalse(
                recovery.attempt(now: now) {
                    XCTAssertFalse(
                        recovery.attempt(now: now.addingTimeInterval(5000)) {
                            XCTFail(); return true
                        })
                    return false
                })
            let relaunched = ClaudeSessionRecovery(defaults: defaults)
            XCTAssertFalse(
                relaunched.attempt(now: now.addingTimeInterval(299)) {
                    XCTFail(); return true
                })
            XCTAssertFalse(relaunched.attempt(now: now.addingTimeInterval(300)) { false })
            XCTAssertFalse(
                relaunched.attempt(now: now.addingTimeInterval(1199)) {
                    XCTFail(); return true
                })
            XCTAssertTrue(relaunched.attempt(now: now.addingTimeInterval(1200)) { true })
            XCTAssertEqual(defaults.integer(forKey: "claudeRecoveryFailures"), 0)
        }
    }

    @MainActor func testAutomaticRecoveryRequiresConsentAndPersistsBothChoices() {
        withDefaults { defaults in
            let store = UsageStore(defaults: defaults)
            XCTAssertFalse(store.claudeAutomaticRecovery)
            XCTAssertNil(defaults.object(forKey: "claudeAutomaticRecovery"))
            store.claudeAutomaticRecovery = true
            XCTAssertTrue(UsageStore(defaults: defaults).claudeAutomaticRecovery)
            XCTAssertTrue(store.recoveryAuthorization.isAllowed)
            store.stop()
            XCTAssertFalse(store.recoveryAuthorization.isAllowed)
            XCTAssertTrue(defaults.bool(forKey: "claudeAutomaticRecovery"))
            store.claudeAutomaticRecovery = false
            XCTAssertFalse(UsageStore(defaults: defaults).claudeAutomaticRecovery)
            XCTAssertFalse(store.recoveryAuthorization.isAllowed)
            store.claudeAutomaticRecovery = true
            store.setClaudeCancelled(true)
            XCTAssertFalse(store.recoveryAuthorization.isAllowed)
            XCTAssertNotNil(defaults.object(forKey: "claudeAutomaticRecovery"))
        }
    }

    private func withDefaults(_ action: (UserDefaults) -> Void) {
        let suite = "TokenGauge.recovery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        action(defaults)
    }
}
