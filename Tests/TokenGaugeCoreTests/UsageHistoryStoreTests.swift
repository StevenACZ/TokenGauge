import Foundation
import SQLite3
import XCTest

@testable import TokenGaugeCore

final class UsageHistoryStoreTests: XCTestCase {
    private var root: URL!
    private var database: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        database = root.appending(path: "usage-history.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testClaudeSnapshotStoresOneRowPerModelAndDay() throws {
        let snapshot = claudeSnapshot(
            buckets: [
                bucket(day: "2026-08-26", hour: 0, model: "claude-fable-5", tokens: 400),
                bucket(day: "2026-08-26", hour: 1, model: "claude-fable-5", tokens: 600),
                bucket(day: "2026-08-26", hour: 1, model: "claude-opus-5", tokens: 250),
                bucket(day: "2026-08-27", hour: 2, model: "claude-fable-5", tokens: 100),
            ]
        )

        try UsageHistoryStore.record(snapshot, at: database)

        let rows = try UsageHistoryStore.tokenRows(at: database)
        XCTAssertEqual(
            rows.map { "\($0.day)|\($0.model)|\($0.tokens)" },
            ["2026-08-26|claude-fable-5|1000", "2026-08-26|claude-opus-5|250", "2026-08-27|claude-fable-5|100"]
        )
    }

    func testCodexSnapshotStoresDailyTotalsUnderTheAllModelKey() throws {
        let snapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [],
            dailyUsage: [
                DailyTokenUsage(day: "2026-08-26", tokens: 911_600), DailyTokenUsage(day: "2026-08-27", tokens: 0),
            ],
            summary: nil,
            availableResetCredits: nil,
            creditBalance: nil,
            capturedAt: Date(timeIntervalSince1970: 1_787_000_000)
        )

        try UsageHistoryStore.record(snapshot, at: database)

        let rows = try UsageHistoryStore.tokenRows(at: database)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.tokens, 0)
        XCTAssertEqual(rows.last?.day, "2026-08-27")
        XCTAssertEqual(rows.first?.model, "all")
        XCTAssertEqual(rows.first?.tokens, 911_600)
        XCTAssertEqual(rows.first?.provider, .codex)
    }

    func testDailyTotalsNeverRegressWhenTranscriptsAreTrimmed() throws {
        let full = claudeSnapshot(buckets: [bucket(day: "2026-08-26", hour: 0, model: "claude-fable-5", tokens: 900)])
        let trimmed = claudeSnapshot(buckets: [bucket(day: "2026-08-26", hour: 0, model: "claude-fable-5", tokens: 40)])

        try UsageHistoryStore.record(full, at: database)
        try UsageHistoryStore.record(trimmed, at: database)

        XCTAssertEqual(try UsageHistoryStore.tokenRows(at: database).first?.tokens, 900)
    }

    func testQuotaSamplesCollapseIntoFifteenMinuteBuckets() throws {
        let base = Date(timeIntervalSince1970: 1_787_000_400)
        try UsageHistoryStore.record(claudeSnapshot(used: 20, capturedAt: base), at: database)
        try UsageHistoryStore.record(claudeSnapshot(used: 24, capturedAt: base.addingTimeInterval(120)), at: database)
        try UsageHistoryStore.record(claudeSnapshot(used: 31, capturedAt: base.addingTimeInterval(1_800)), at: database)

        let rows = try UsageHistoryStore.quotaRows(at: database)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.usedPercentage), [24, 31])
        XCTAssertEqual(rows.map(\.displayName), ["Fable", "Fable"])
        XCTAssertEqual(rows.map(\.sampledAt), [base.addingTimeInterval(120), base.addingTimeInterval(1800)])
        XCTAssertTrue(rows.allSatisfy(\.isVerified))
        XCTAssertEqual(rows.map(\.durationMinutes), [10_080, 10_080])
    }

    func testQuotaSamplesOlderThanTheRetentionWindowAreDropped() throws {
        let now = Date(timeIntervalSince1970: 1_787_000_400)
        let ancient = now.addingTimeInterval(-Double(UsageHistoryStore.quotaRetentionDays + 5) * 86_400)
        try UsageHistoryStore.record(claudeSnapshot(used: 10, capturedAt: ancient), at: database, now: ancient)
        try UsageHistoryStore.record(claudeSnapshot(used: 55, capturedAt: now), at: database, now: now)

        XCTAssertEqual(try UsageHistoryStore.quotaRows(at: database).map(\.usedPercentage), [55])
    }

    func testUnknownQuotaTimestampAndFailedActivityAreNotFabricated() throws {
        let snapshot = ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                QuotaWindow(id: "weekly", usedPercentage: 20, resetsAt: nil, durationMinutes: 10080, displayName: nil)
            ],
            dailyUsage: [DailyTokenUsage(day: "2026-09-12", tokens: 123)], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: nil, activityReadSucceeded: false)
        try UsageHistoryStore.record(snapshot, at: database)
        XCTAssertTrue(try UsageHistoryStore.quotaRows(at: database).isEmpty)
        XCTAssertTrue(try UsageHistoryStore.tokenRows(at: database).isEmpty)
    }

    func testDatabaseStaysUserOnly() throws {
        try UsageHistoryStore.record(claudeSnapshot(), at: database)

        let mode = try FileManager.default.attributesOfItem(atPath: database.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testLegacyMigrationPreservesRowsAndNeverMarksThemVerified() throws {
        let base = Date(timeIntervalSince1970: 1_787_000_400)
        try executeSQL(
            """
            CREATE TABLE quota_samples (
                provider TEXT NOT NULL, window_id TEXT NOT NULL, sampled_at INTEGER NOT NULL,
                display_name TEXT, duration_minutes INTEGER, used_percentage REAL NOT NULL, resets_at INTEGER,
                PRIMARY KEY(provider, window_id, sampled_at)
            ) WITHOUT ROWID;
            INSERT INTO quota_samples VALUES ('claude', 'weekly_scoped', 1787000400, 'Fable', 10080, 22, 1787086800);
            """)
        for _ in 0..<2 {
            let rows = try UsageHistoryStore.quotaRows(at: database)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.usedPercentage, 22)
            XCTAssertEqual(rows.first?.sampledAt, base)
            XCTAssertEqual(rows.first?.durationMinutes, 10_080)
            XCTAssertEqual(rows.first?.isVerified, false)
            XCTAssertNil(rows.first?.continuityStartedAt)
        }
        try UsageHistoryStore.record(claudeSnapshot(capturedAt: base.addingTimeInterval(1800)), at: database, now: base)
        let rows = try UsageHistoryStore.quotaRows(at: database)
        XCTAssertEqual(rows.map(\.isVerified), [false, true])
        XCTAssertEqual(rows.first?.usedPercentage, 22)
    }

    func testQuotaRangeUsesActualObservationInsideBoundaryBuckets() throws {
        let base = Date(timeIntervalSince1970: 1_787_000_400)
        for delta in [120.5, 1800.5, 3600.5] {
            try UsageHistoryStore.record(
                claudeSnapshot(capturedAt: base.addingTimeInterval(delta)), at: database, now: base)
        }
        let middle = base.addingTimeInterval(1800.5)
        XCTAssertEqual(try UsageHistoryStore.quotaRows(since: middle, until: middle, at: database).count, 1)
        XCTAssertTrue(
            try UsageHistoryStore.quotaRows(
                since: middle.addingTimeInterval(0.1), until: middle.addingTimeInterval(10), at: database
            ).isEmpty)
        XCTAssertTrue(try UsageHistoryStore.quotaRows(provider: .codex, since: base, at: database).isEmpty)
        XCTAssertEqual(try UsageHistoryStore.quotaRows(until: middle, at: database).count, 2)
    }

    func testOlderObservationCannotOverwriteLatestValueWithinBucket() throws {
        let base = Date(timeIntervalSince1970: 1_787_000_400)
        try UsageHistoryStore.record(
            claudeSnapshot(used: 24, capturedAt: base.addingTimeInterval(120)), at: database, now: base)
        try UsageHistoryStore.record(claudeSnapshot(used: 20, capturedAt: base), at: database, now: base)
        let row = try XCTUnwrap(UsageHistoryStore.quotaRows(at: database).first)
        XCTAssertEqual(row.usedPercentage, 24)
        XCTAssertEqual(row.sampledAt, base.addingTimeInterval(120))
    }

    func testTokenInclusiveRangesAndBoundsPreserveExplicitZero() throws {
        XCTAssertEqual(try UsageHistoryStore.bounds(at: database), HistoryBounds(firstDay: nil, lastDay: nil))
        try UsageHistoryStore.record(
            claudeSnapshot(buckets: [
                bucket(day: "2026-08-26", hour: 0, model: "fable", tokens: 100),
                bucket(day: "2026-08-27", hour: 0, model: "fable", tokens: 0),
                bucket(day: "2026-08-29", hour: 0, model: "fable", tokens: 200),
            ]), at: database)
        XCTAssertEqual(
            try UsageHistoryStore.bounds(at: database), HistoryBounds(firstDay: "2026-08-26", lastDay: "2026-08-29"))
        let rows = try UsageHistoryStore.tokenRows(since: "2026-08-27", through: "2026-08-28", at: database)
        XCTAssertEqual(rows.map(\.day), ["2026-08-27"])
        XCTAssertEqual(rows.first?.tokens, 0)
        XCTAssertTrue(try UsageHistoryStore.tokenRows(since: "2026-09-01", through: "2026-08-01", at: database).isEmpty)
    }

    private func executeSQL(_ sql: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
        let db = try XCTUnwrap(handle)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func claudeSnapshot(
        used: Double = 44,
        capturedAt: Date = Date(timeIntervalSince1970: 1_787_000_400),
        buckets: [ModelTokenBucket] = []
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                QuotaWindow(
                    id: "weekly_scoped",
                    usedPercentage: used,
                    resetsAt: capturedAt.addingTimeInterval(86_400),
                    durationMinutes: 10_080,
                    displayName: "Fable"
                )
            ],
            dailyUsage: ModelTokenAggregator.daily(buckets),
            summary: nil,
            availableResetCredits: nil,
            creditBalance: nil,
            capturedAt: capturedAt,
            modelBuckets: buckets
        )
    }

    private func bucket(day: String, hour: Int, model: String, tokens: Int) -> ModelTokenBucket {
        ModelTokenBucket(
            day: day,
            hourStart: Date(timeIntervalSince1970: 1_787_000_000 + Double(hour) * 3_600),
            model: model,
            tokens: tokens
        )
    }
}
