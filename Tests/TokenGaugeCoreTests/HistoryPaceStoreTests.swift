import Foundation
import XCTest

@testable import TokenGaugeCore

final class HistoryPaceStoreTests: XCTestCase {
    private var root: URL!
    private var database: URL!
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let key = HistoryPaceKey(provider: .claude, windowID: "weekly")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        database = root.appending(path: "history.sqlite")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testAutomaticArchiveRetainsActiveRateThroughIdleAndResume() throws {
        for (minute, used) in [(0, 10.0), (15, 12), (30, 14), (45, 14), (60, 14), (75, 14), (90, 14)] {
            try record(Double(minute), used)
        }
        let all = try UsageHistoryStore.paceRows(at: database)
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.first?.pace.pointsPerHour, 8)
        XCTAssertEqual(all.last?.pace.pointsPerHour, 0)
        XCTAssertEqual(all.filter(\.isActive).count, 1)
        let retained = try UsageHistoryStore.recentPaces(for: [key], activeOnly: true, at: database)
        XCTAssertEqual(retained.first?.pace.sampledAt, instant(30))
        try record(105, 16)
        let resumed = try UsageHistoryStore.recentPaces(for: [key], activeOnly: true, at: database)
        XCTAssertEqual(resumed.map { $0.pace.sampledAt }, [instant(105), instant(30)])
        XCTAssertEqual(resumed.first?.pace.lastUsedPercentage, 16)
    }

    func testDuplicateAndOutOfOrderSamplesCannotAlterArchivedObservations() throws {
        try record(0, 10)
        try record(15, 12)
        try record(30, 14)
        let before = try UsageHistoryStore.paceRows(at: database)
        try record(30, 99)
        try record(25, 1)
        XCTAssertEqual(try UsageHistoryStore.paceRows(at: database), before)
    }

    func testBoundedRangeAndRecentQueriesAreOrderedAndIsolated() throws {
        for minute in [0, 15, 30, 45, 60] { try record(Double(minute), Double(minute)) }
        let range = try UsageHistoryStore.paceRows(
            provider: .claude, windowID: "weekly", since: instant(30), until: instant(45), at: database)
        XCTAssertEqual(range.map { $0.pace.sampledAt }, [instant(30), instant(45)])
        let recent = try UsageHistoryStore.recentPaces(
            for: [key, key], limitPerWindow: 1, before: instant(60), at: database)
        XCTAssertEqual(recent.map { $0.pace.sampledAt }, [instant(45)])
        XCTAssertTrue(try UsageHistoryStore.paceRows(provider: .codex, at: database).isEmpty)
        XCTAssertTrue(try UsageHistoryStore.recentPaces(for: [key], limitPerWindow: 0, at: database).isEmpty)
    }

    func testResetJitterPreservesContinuityButCumulativeDriftBreaksIt() throws {
        try record(0, 10, jitter: 0)
        try record(15, 12, jitter: 0.6)
        try record(30, 14, jitter: 0.9)
        XCTAssertEqual(try UsageHistoryStore.paceRows(at: database).count, 1)
        try record(45, 16, jitter: 1.5)
        XCTAssertEqual(try UsageHistoryStore.paceRows(at: database).count, 1)
        XCTAssertEqual(try UsageHistoryStore.quotaRows(at: database).last?.continuityStartedAt, instant(45))
        XCTAssertTrue(try UsageHistoryStore.recentPaces(for: [key], matchingLatestQuota: true, at: database).isEmpty)
        XCTAssertEqual(try UsageHistoryStore.recentPaces(for: [key], activeOnly: true, at: database).count, 1)
    }

    func testPaceMathUsesFirstResetAgainstCumulativeDrift() {
        func row(_ minutes: Double, _ jitter: Double) -> HistoryQuotaRow {
            HistoryQuotaRow(
                sampledAt: instant(minutes), provider: .claude, windowID: "weekly", displayName: nil,
                usedPercentage: minutes, resetsAt: base.addingTimeInterval(86400 + jitter),
                durationMinutes: 10_080, isVerified: true)
        }
        XCTAssertNil(
            HistoryAnalytics.pace(
                rows: [row(0, 0), row(15, 0.6), row(30, 1.2)],
                provider: .claude, windowID: "weekly", now: instant(30)))
        XCTAssertTrue(HistoryAnalytics.sameReset(base, base.addingTimeInterval(1)))
        XCTAssertFalse(HistoryAnalytics.sameReset(base, base.addingTimeInterval(2)))
        XCTAssertFalse(HistoryAnalytics.sameReset(nil, nil))
    }

    func testArchiveIsUserOnlyAndSurvivesQuotaRetention() throws {
        try record(0, 10)
        try record(15, 12)
        try record(30, 14)
        let snapshot = ProviderUsageSnapshot(
            provider: .codex, windows: [], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: nil)
        try UsageHistoryStore.record(snapshot, at: database, now: base.addingTimeInterval(1000 * 86400))
        XCTAssertTrue(try UsageHistoryStore.quotaRows(at: database).isEmpty)
        XCTAssertEqual(try UsageHistoryStore.paceRows(at: database).count, 1)
        let mode = try FileManager.default.attributesOfItem(atPath: database.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testFirstPositiveEstimateSeedsActiveHistoryEvenIfCurrentSampleIsIdle() throws {
        try record(0, 10)
        try record(15, 12)
        try record(30, 12)
        let active = try UsageHistoryStore.recentPaces(for: [key], activeOnly: true, at: database)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.pace.pointsPerHour, 4)
        try record(45, 12)
        XCTAssertEqual(try UsageHistoryStore.recentPaces(for: [key], activeOnly: true, at: database), active)
    }

    func testLatestInvalidContinuityCannotRevivePreviousPaceAfterUsageRecovers() throws {
        try record(0, 10)
        try record(15, 12)
        try record(30, 14)
        XCTAssertEqual(try UsageHistoryStore.recentPaces(for: [key], matchingLatestQuota: true, at: database).count, 1)
        try record(35, 13)
        try record(40, 16)
        XCTAssertTrue(try UsageHistoryStore.recentPaces(for: [key], matchingLatestQuota: true, at: database).isEmpty)
        XCTAssertEqual(
            try UsageHistoryStore.recentPaces(for: [key], activeOnly: true, at: database).first?.pace.sampledAt,
            instant(30))
    }

    func testRecordQuotaDisabledDoesNotArchivePace() throws {
        try record(0, 10)
        try record(15, 12)
        try record(30, 14, archive: false)
        XCTAssertTrue(try UsageHistoryStore.paceRows(at: database).isEmpty)
    }

    func testPaceReadsOnlyReturnRowsOfTheCurrentAccount() throws {
        try record(0, 10)
        try record(15, 12)
        try record(30, 14)
        for (minute, used) in [(45, 20.0), (60, 24), (75, 28)] {
            try record(Double(minute), used, fingerprint: "account-a")
        }

        let legacyRows = try UsageHistoryStore.paceRows(at: database)
        let accountRows = try UsageHistoryStore.paceRows(accountFingerprint: "account-a", at: database)
        XCTAssertFalse(legacyRows.isEmpty)
        XCTAssertFalse(accountRows.isEmpty)
        XCTAssertTrue(legacyRows.allSatisfy { $0.pace.sampledAt <= instant(30) })
        XCTAssertTrue(accountRows.allSatisfy { $0.pace.sampledAt > instant(30) })
        XCTAssertTrue(try UsageHistoryStore.paceRows(accountFingerprint: "account-b", at: database).isEmpty)
        XCTAssertTrue(
            try UsageHistoryStore.recentPaces(for: [key], accountFingerprint: "account-b", at: database).isEmpty)
        XCTAssertEqual(
            try UsageHistoryStore.recentPaces(for: [key], accountFingerprint: "account-a", at: database)
                .map { $0.pace.sampledAt },
            accountRows.map { $0.pace.sampledAt }.reversed())
    }

    private func instant(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    private func record(
        _ minutes: Double, _ used: Double, jitter: Double = 0, archive: Bool = true, fingerprint: String? = nil
    ) throws {
        let snapshot = ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                QuotaWindow(
                    id: "weekly", usedPercentage: used, resetsAt: base.addingTimeInterval(86400 + jitter),
                    durationMinutes: 10_080, displayName: "Fable")
            ], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: instant(minutes), activityReadSucceeded: false)
        try UsageHistoryStore.record(
            snapshot, at: database, now: instant(minutes), recordQuota: archive, accountFingerprint: fingerprint)
    }
}
