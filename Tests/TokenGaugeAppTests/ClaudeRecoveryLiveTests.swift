import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeRecoveryLiveTests: XCTestCase {
    func testOptInRealCLIStartupAndUsageRetry() throws {
        guard ProcessInfo.processInfo.environment["TOKENGAUGE_LIVE_RECOVERY_QA"] == "1" else {
            throw XCTSkip("Requires explicit local Claude recovery QA authorization")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let executable = try XCTUnwrap(ClaudeSessionRecovery.executable(homeDirectory: home))
        let started = ProcessInfo.processInfo.systemUptime
        var reads = 0
        let result = ClaudeUsageClient.readAccount(
            fetch: {
                reads += 1
                if reads == 1 { throw ClaudeAccountUsageError.credentialExpired }
                return try ClaudeAccountUsageClient(homeDirectory: home).fetch()
            },
            recover: {
                ClaudeRecoveryProcess.run(executable: executable, homeDirectory: home) {
                    guard ProcessInfo.processInfo.systemUptime - started >= 6 else { return false }
                    ClaudeOAuthTokenReader.invalidate()
                    return ClaudeOAuthTokenReader.read().map { !$0.isExpired } ?? false
                }
            })
        let snapshot = try result.get()
        XCTAssertFalse(snapshot.windows.isEmpty)
        XCTAssertTrue(snapshot.windows.contains { $0.durationMinutes == 300 })
        XCTAssertTrue(snapshot.windows.contains { $0.durationMinutes == 10_080 })
        XCTAssertTrue(snapshot.windows.contains { $0.displayName != nil })
        XCTAssertEqual(reads, 2)
    }
}
