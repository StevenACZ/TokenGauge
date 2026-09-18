import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeAccountScopeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testSnapshotOfAnotherAccountIsNotPresentedAsLiveData() throws {
        let home = try makeHome(accountUuid: "uuid-a")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeSnapshot(home: home, fingerprint: ClaudeAccountIdentity(accountUuid: "uuid-b").fingerprint)
        let client = ClaudeAccountUsageClient(homeDirectory: home)
        let identity = ClaudeAccountIdentityReader.current(homeDirectory: home)

        XCTAssertNil(client.cached(identity: identity))
        let result = ClaudeUsageClient.resolve(
            account: .failure(ClaudeAccountUsageError.unavailable), cached: client.cached(identity: identity),
            capture: nil, modelBuckets: [], now: now)
        XCTAssertEqual(result.access, .unavailable)
        XCTAssertTrue(result.snapshot.windows.isEmpty)
    }

    func testSameAccountAndLegacySnapshotsStayValid() throws {
        let home = try makeHome(accountUuid: "uuid-a")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = ClaudeAccountUsageClient(homeDirectory: home)
        let identity = ClaudeAccountIdentityReader.current(homeDirectory: home)

        try writeSnapshot(home: home, fingerprint: ClaudeAccountIdentity(accountUuid: "uuid-a").fingerprint)
        XCTAssertEqual(client.cached(identity: identity)?.capturedAt, now.addingTimeInterval(-1))

        try writeSnapshot(home: home, fingerprint: nil)
        XCTAssertEqual(client.cached(identity: identity)?.capturedAt, now.addingTimeInterval(-1))
        XCTAssertNil(client.cached(identity: identity)?.accountFingerprint)
        XCTAssertNotNil(client.cached(identity: nil))
    }

    func testStatusLineCaptureOfAnotherAccountIsNeverUsedAsFallback() throws {
        let home = try makeHome(accountUuid: "uuid-a")
        defer { try? FileManager.default.removeItem(at: home) }
        let url = UsagePaths.claudeCapture(homeDirectory: home)
        let current = ClaudeAccountIdentity(accountUuid: "uuid-a").fingerprint

        try writeCapture(at: url, fingerprint: ClaudeAccountIdentity(accountUuid: "uuid-b").fingerprint)
        XCTAssertNil(ClaudeUsageClient.capture(at: url, accountFingerprint: current))
        let result = ClaudeUsageClient.resolve(
            account: .failure(ClaudeAccountUsageError.unavailable), cached: nil,
            capture: ClaudeUsageClient.capture(at: url, accountFingerprint: current), modelBuckets: [], now: now)
        XCTAssertEqual(result.access, .unavailable)
        XCTAssertTrue(result.snapshot.windows.isEmpty)

        try writeCapture(at: url, fingerprint: current)
        XCTAssertNotNil(ClaudeUsageClient.capture(at: url, accountFingerprint: current))
        try writeCapture(at: url, fingerprint: nil)
        XCTAssertNotNil(ClaudeUsageClient.capture(at: url, accountFingerprint: current))
    }

    private func makeHome(accountUuid: String) throws -> URL {
        ClaudeAccountIdentityReader.invalidate()
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(#"{"oauthAccount":{"accountUuid":"\#(accountUuid)"}}"#.utf8)
            .write(to: UsagePaths.claudeConfig(homeDirectory: home))
        return home
    }

    private func writeSnapshot(home: URL, fingerprint: String?) throws {
        let snapshot = ClaudeAccountSnapshot(
            capturedAt: now.addingTimeInterval(-1),
            windows: [
                QuotaWindow(
                    id: "seven_day", usedPercentage: 40, resetsAt: now.addingTimeInterval(86_400),
                    durationMinutes: 10_080, displayName: nil)
            ],
            accountFingerprint: fingerprint
        )
        try SecureMetricStore.write(snapshot, to: UsagePaths.claudeAccountCache(homeDirectory: home))
    }

    private func writeCapture(at url: URL, fingerprint: String?) throws {
        let capture = ClaudeCapturedSnapshot(
            capturedAt: now.addingTimeInterval(-1),
            windows: [
                "five_hour": ClaudeCapturedWindow(usedPercentage: 30, resetsAt: now.addingTimeInterval(3_600))
            ],
            accountFingerprint: fingerprint
        )
        try SecureMetricStore.write(capture, to: url)
    }
}
