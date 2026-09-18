import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeUsageClientConcurrencyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testHistoryAndAccountFetchOverlap() async throws {
        let snapshot = ClaudeAccountSnapshot(
            capturedAt: now,
            windows: [
                QuotaWindow(
                    id: "seven_day", usedPercentage: 40, resetsAt: now.addingTimeInterval(86_400),
                    durationMinutes: 10_080, displayName: nil)
            ]
        )
        let buckets = [ModelTokenBucket(day: "2026-09-18", hourStart: now, model: "fable", tokens: 120)]
        let started = ProcessInfo.processInfo.systemUptime

        let result = await ClaudeUsageClient.fetch(
            history: {
                try? await Task.sleep(for: .milliseconds(200))
                return buckets
            },
            account: {
                try? await Task.sleep(for: .milliseconds(200))
                return .success(snapshot)
            },
            cached: { nil },
            capture: { nil },
            now: now
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertLessThan(elapsed, 0.35)
        XCTAssertEqual(result.access, .live)
        XCTAssertEqual(result.snapshot.windows.map(\.id), ["seven_day"])
        XCTAssertEqual(result.snapshot.modelBuckets, buckets)
        XCTAssertTrue(result.snapshot.activityReadSucceeded)
    }
}
