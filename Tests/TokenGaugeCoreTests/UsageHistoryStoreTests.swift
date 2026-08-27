import Foundation
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
        XCTAssertEqual(rows.count, 1)
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
        XCTAssertTrue(
            rows.allSatisfy { UsageHistoryStore.bucket($0.sampledAt) == Int64($0.sampledAt.timeIntervalSince1970) })
    }

    func testQuotaSamplesOlderThanTheRetentionWindowAreDropped() throws {
        let now = Date(timeIntervalSince1970: 1_787_000_400)
        let ancient = now.addingTimeInterval(-Double(UsageHistoryStore.quotaRetentionDays + 5) * 86_400)
        try UsageHistoryStore.record(claudeSnapshot(used: 10, capturedAt: ancient), at: database, now: ancient)
        try UsageHistoryStore.record(claudeSnapshot(used: 55, capturedAt: now), at: database, now: now)

        XCTAssertEqual(try UsageHistoryStore.quotaRows(at: database).map(\.usedPercentage), [55])
    }

    func testDatabaseStaysUserOnly() throws {
        try UsageHistoryStore.record(claudeSnapshot(), at: database)

        let mode = try FileManager.default.attributesOfItem(atPath: database.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
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
