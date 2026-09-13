import Foundation
import XCTest

@testable import TokenGaugeCore

final class QuotaContinuityTests: XCTestCase {
    private var root: URL!
    private var database: URL!
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        database = root.appending(path: "history.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDropInsideOverwrittenBucketPreventsPrematurePaceAndEventuallyRecovers() throws {
        try record(0, used: 10)
        try record(15, used: 11)
        try record(30, used: 9)
        try record(35, used: 12)
        let rows = try UsageHistoryStore.quotaRows(at: database)
        XCTAssertEqual(rows.map(\.usedPercentage), [10, 11, 12])
        XCTAssertEqual(rows.last?.continuityStartedAt, instant(30))
        XCTAssertNil(try pace(at: 35))
        try record(45, used: 13)
        try record(65, used: 15)
        let result = try XCTUnwrap(pace(at: 65))
        XCTAssertEqual(result.observedMinutes, 30)
        XCTAssertEqual(result.pointsPerHour, 6)
        XCTAssertEqual(result.lastUsedPercentage, 15)
        XCTAssertEqual(result.resetsAt, base.addingTimeInterval(86_400))
    }

    func testResetChangeThenReturnWithinSameBucketStillBreaksContinuity() throws {
        try record(0, used: 10)
        try record(15, used: 11)
        try record(30, used: 12, reset: base.addingTimeInterval(172_800))
        try record(35, used: 13)
        let rows = try UsageHistoryStore.quotaRows(at: database)
        XCTAssertEqual(rows.last?.continuityStartedAt, instant(35))
        XCTAssertNil(try pace(at: 35))
    }

    func testOutOfOrderObservationCannotRewriteContinuityOrInsertOlderBucket() throws {
        try record(0, used: 10)
        try record(15, used: 11)
        try record(35, used: 12)
        let before = try UsageHistoryStore.quotaRows(at: database)
        try record(30, used: 1)
        try record(-15, used: 1)
        XCTAssertEqual(try UsageHistoryStore.quotaRows(at: database), before)
        XCTAssertNotNil(try pace(at: 35))
    }

    func testInvalidValueOverwrittenWithinBucketDoesNotRestorePreviousPace() throws {
        try record(0, used: 10)
        try record(15, used: 11)
        try record(30, used: .nan)
        XCTAssertEqual(try UsageHistoryStore.quotaRows(at: database).last?.isVerified, false)
        try record(35, used: 12)
        XCTAssertNil(try pace(at: 35))
        XCTAssertEqual(try UsageHistoryStore.quotaRows(at: database).last?.continuityStartedAt, instant(35))
    }

    func testFractionalResetKeepsContinuityAndMatchesTheLiveWindow() throws {
        let reset = base.addingTimeInterval(86_400.125)
        try record(0, used: 10, reset: reset)
        try record(15, used: 11, reset: reset)
        try record(30, used: 12, reset: reset)
        let result = try XCTUnwrap(pace(at: 30))
        XCTAssertEqual(result.resetsAt, reset)
        XCTAssertEqual(result.pointsPerHour, 4)
        XCTAssertEqual(try UsageHistoryStore.quotaRows(at: database).last?.continuityStartedAt, instant(0))
    }

    private func instant(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    private func record(_ minutes: Double, used: Double, reset: Date? = nil) throws {
        let snapshot = ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                QuotaWindow(
                    id: "weekly", usedPercentage: used, resetsAt: reset ?? base.addingTimeInterval(86_400),
                    durationMinutes: 10_080, displayName: nil)
            ],
            dailyUsage: [], summary: nil, availableResetCredits: nil, creditBalance: nil,
            capturedAt: instant(minutes), activityReadSucceeded: false)
        try UsageHistoryStore.record(snapshot, at: database, now: instant(minutes))
    }

    private func pace(at minutes: Double) throws -> QuotaPace? {
        HistoryAnalytics.pace(
            rows: try UsageHistoryStore.quotaRows(at: database), provider: .claude,
            windowID: "weekly", now: instant(minutes))
    }
}
