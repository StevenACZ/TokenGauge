import Foundation
import XCTest

@testable import TokenGaugeCore

final class HistoryAnalyticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    func testPaceUsesActualElapsedTimeAndDistinctSamples() throws {
        let rows = [row(-50, 10), row(-30, 11), row(-5, 13)]
        let result = try XCTUnwrap(pace(rows + [rows[1]]))
        XCTAssertEqual(result.pointsPerHour, 4, accuracy: 0.0001)
        XCTAssertEqual(result.observedMinutes, 45)
        XCTAssertEqual(result.sampledAt, now.addingTimeInterval(-300))
    }

    func testZeroUsageIsMeasuredNotMissing() throws {
        XCTAssertEqual(try XCTUnwrap(pace([row(-30, 10), row(-15, 10), row(0, 10)])).pointsPerHour, 0)
        XCTAssertNil(pace([]))
        XCTAssertNil(pace([row(-30, 10), row(0, 10)]))
        XCTAssertNil(pace([row(-20, 10), row(-10, 11), row(0, 12)]))
    }

    func testStaleFutureAndOutsideHourObservationsCannotProvideEstimate() {
        XCTAssertNil(pace([row(-60, 10), row(-45, 11), row(-21, 12)]))
        XCTAssertNil(pace([row(-70, 10), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 10), row(-15, 11), row(1, 12)]))
    }

    func testUnverifiedNonweeklyAndOtherStreamsAreExcluded() {
        XCTAssertNil(pace([row(-30, 10, verified: false), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 10, duration: 300), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 10, duration: nil), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 10, provider: .codex), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 10, window: "other"), row(-15, 11), row(0, 12)]))
    }

    func testResetsDropsAndGapsBreakTheObservedWindow() {
        XCTAssertNil(pace([row(-30, 10, reset: now.addingTimeInterval(200)), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 10, reset: now), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 10, reset: nil), row(-15, 11), row(0, 12)]))
        XCTAssertNil(pace([row(-30, 90), row(-15, 10), row(0, 12)]))
        XCTAssertNil(pace([row(-60, 10), row(-15, 11), row(0, 12)]))
    }

    func testLatestContiguousSuffixRecoversAfterBoundary() throws {
        let rows = [row(-60, 90), row(-45, 10), row(-30, 11), row(0, 13)]
        XCTAssertEqual(try XCTUnwrap(pace(rows)).pointsPerHour, 4, accuracy: 0.0001)
    }

    func testInvalidLatestObservationDoesNotFallBackToEarlierPace() {
        let valid = [row(-45, 10), row(-30, 11), row(-15, 12)]
        XCTAssertNil(pace(valid + [row(0, 13, verified: false)]))
        XCTAssertNil(pace(valid + [row(0, .nan)]))
        XCTAssertNil(pace(valid + [row(0, -1)]))
        XCTAssertNil(pace(valid + [row(0, 101)]))
        XCTAssertNil(pace(valid + [row(-15, 13)]))
    }

    private func pace(_ rows: [HistoryQuotaRow]) -> QuotaPace? {
        HistoryAnalytics.pace(rows: rows, provider: .claude, windowID: "weekly", now: now)
    }

    private func row(
        _ minutes: Double, _ used: Double, verified: Bool = true, duration: Int? = 10_080,
        provider: UsageProvider = .claude, window: String = "weekly", reset: Date? = Date.distantFuture
    ) -> HistoryQuotaRow {
        HistoryQuotaRow(
            sampledAt: now.addingTimeInterval(minutes * 60), provider: provider, windowID: window,
            displayName: nil, usedPercentage: used, resetsAt: reset, durationMinutes: duration, isVerified: verified)
    }
}
