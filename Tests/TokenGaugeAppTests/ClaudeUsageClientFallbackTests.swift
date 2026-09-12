import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeUsageClientFallbackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFreshCachedAccountSnapshotWinsOverOlderCapture() {
        let cached = ClaudeAccountSnapshot(
            capturedAt: now.addingTimeInterval(-600),
            windows: [window(id: "seven_day", used: 40, reset: now.addingTimeInterval(86_400))]
        )
        let capture = capturedSnapshot(at: now.addingTimeInterval(-7_200), reset: now.addingTimeInterval(3_600))

        let result = ClaudeUsageClient.fallback(cached: cached, capture: capture, modelBuckets: [], now: now)

        XCTAssertEqual(result.windows.map(\.id), ["seven_day"])
        XCTAssertEqual(result.capturedAt, cached.capturedAt)
    }

    func testExpiredCachedWindowsArePrunedAndCaptureTakesOver() {
        let cached = ClaudeAccountSnapshot(
            capturedAt: now.addingTimeInterval(-600),
            windows: [
                window(id: "seven_day", used: 89, reset: now.addingTimeInterval(-3_600)),
                window(id: "seven_day_fable", used: 99, reset: now.addingTimeInterval(-3_600), displayName: "Fable"),
            ]
        )
        let capture = capturedSnapshot(at: now.addingTimeInterval(-7_200), reset: now.addingTimeInterval(3_600))

        let result = ClaudeUsageClient.fallback(cached: cached, capture: capture, modelBuckets: [], now: now)

        XCTAssertEqual(result.windows.map(\.id), ["five_hour"])
        XCTAssertEqual(result.capturedAt, capture.capturedAt)
    }

    func testLiveScopedWindowIsMergedIntoCaptureButExpiredOneIsNot() {
        let cached = ClaudeAccountSnapshot(
            capturedAt: now.addingTimeInterval(-7_200),
            windows: [
                window(id: "seven_day_fable", used: 56, reset: now.addingTimeInterval(86_400), displayName: "Fable"),
                window(id: "seven_day_opus", used: 12, reset: now.addingTimeInterval(-60), displayName: "Opus"),
            ]
        )
        let capture = capturedSnapshot(at: now.addingTimeInterval(-600), reset: now.addingTimeInterval(3_600))

        let result = ClaudeUsageClient.fallback(cached: cached, capture: capture, modelBuckets: [], now: now)

        XCTAssertEqual(Set(result.windows.map(\.id)), ["five_hour", "seven_day_fable"])
        XCTAssertEqual(result.capturedAt, cached.capturedAt)
    }

    func testEverythingExpiredYieldsAnEmptyReading() {
        let cached = ClaudeAccountSnapshot(
            capturedAt: now.addingTimeInterval(-90_000),
            windows: [window(id: "seven_day", used: 89, reset: now.addingTimeInterval(-3_600))]
        )
        let capture = capturedSnapshot(at: now.addingTimeInterval(-90_000), reset: now.addingTimeInterval(-7_200))

        let result = ClaudeUsageClient.fallback(cached: cached, capture: capture, modelBuckets: [], now: now)

        XCTAssertTrue(result.windows.isEmpty)
        XCTAssertNil(result.capturedAt)
    }

    func testCurrentCachedWindowsSurviveWhenCaptureIsFullyExpired() {
        let cached = ClaudeAccountSnapshot(
            capturedAt: now.addingTimeInterval(-7_200),
            windows: [window(id: "seven_day", used: 40, reset: now.addingTimeInterval(86_400))]
        )
        let capture = capturedSnapshot(at: now.addingTimeInterval(-600), reset: now.addingTimeInterval(-60))

        let result = ClaudeUsageClient.fallback(cached: cached, capture: capture, modelBuckets: [], now: now)

        XCTAssertEqual(result.windows.map(\.id), ["seven_day"])
        XCTAssertEqual(result.capturedAt, cached.capturedAt)
    }

    private func window(
        id: String,
        used: Double,
        reset: Date,
        displayName: String? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            usedPercentage: used,
            resetsAt: reset,
            durationMinutes: 10_080,
            displayName: displayName
        )
    }

    private func capturedSnapshot(at capturedAt: Date, reset: Date) -> ClaudeCapturedSnapshot {
        ClaudeCapturedSnapshot(
            capturedAt: capturedAt,
            windows: ["five_hour": ClaudeCapturedWindow(usedPercentage: 3, resetsAt: reset)]
        )
    }
}
