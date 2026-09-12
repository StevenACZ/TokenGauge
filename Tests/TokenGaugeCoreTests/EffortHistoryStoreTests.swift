import Foundation
import XCTest

@testable import TokenGaugeCore

final class EffortHistoryStoreTests: XCTestCase {
    private var root: URL!
    private var database: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        database = root.appending(path: "history.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRepeatedEventsKeepMaximumWithoutDoubleCounting() throws {
        try UsageHistoryStore.recordEffort([record(tokens: 10), record(tokens: 20), record(tokens: 5)], at: database)
        try UsageHistoryStore.recordEffort([record(tokens: 20)], at: database)
        let rows = try UsageHistoryStore.effortRows(at: database)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.tokens, 20)
    }

    func testUnknownMetadataCanUpgradeButKnownValuesNeverChangeOrDowngrade() throws {
        try UsageHistoryStore.recordEffort(
            [
                record(model: "unknown", effort: "unknown"),
                record(model: "gpt-6", effort: "high"),
                record(model: "other-model", effort: "low"),
                record(model: "unknown", effort: "unknown"),
            ], at: database)
        let rows = try UsageHistoryStore.effortRows(at: database)
        XCTAssertEqual(rows.first?.model, "gpt-6")
        XCTAssertEqual(rows.first?.effort, "high")
    }

    func testEarliestEventDayStaysStableAcrossLaterScans() throws {
        try UsageHistoryStore.recordEffort(
            [
                record(day: "2026-09-12", seconds: 200),
                record(day: "2026-09-11", seconds: 100),
                record(day: "2026-09-13", seconds: 300),
                record(day: "2026-09-10", seconds: 100),
            ], at: database)
        XCTAssertEqual(try UsageHistoryStore.effortRows(at: database).first?.day, "2026-09-11")
    }

    func testInclusiveRangesGroupOnlyMatchingMetadata() throws {
        try UsageHistoryStore.recordEffort(
            [
                record(id: hash("a"), tokens: 10), record(id: hash("b"), tokens: 20),
                record(id: hash("c"), effort: "medium", tokens: 30),
                record(id: hash("d"), day: "2026-09-13", tokens: 90),
                record(id: hash("e"), provider: .claude, tokens: 40),
            ], at: database)
        let rows = try UsageHistoryStore.effortRows(since: "2026-09-12", through: "2026-09-12", at: database)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first { $0.provider == .codex && $0.effort == "high" }?.tokens, 30)
        XCTAssertEqual(rows.first { $0.provider == .codex && $0.effort == "medium" }?.tokens, 30)
        XCTAssertEqual(rows.first { $0.provider == .claude }?.tokens, 40)
        XCTAssertTrue(try UsageHistoryStore.effortRows(since: "2026-10-01", at: database).isEmpty)
    }

    func testHashCaseNormalizesAndProviderCollisionCannotOverwrite() throws {
        try UsageHistoryStore.recordEffort(
            [
                record(id: hash("a"), tokens: 10), record(id: hash("A"), tokens: 20),
                record(id: hash("a"), provider: .claude, model: "other", tokens: 99),
            ], at: database)
        let rows = try UsageHistoryStore.effortRows(at: database)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.provider, .codex)
        XCTAssertEqual(rows.first?.tokens, 20)
    }

    func testMalformedRowsAreIgnoredIndividuallyAndZeroRemainsValid() throws {
        let malformed = [
            record(id: "raw-session-id"), record(id: hash("z")), record(model: "prompt content"),
            record(model: "../path/to/secret"), record(model: String(repeating: "a", count: 129)),
            record(effort: "arbitrary"), record(tokens: -1), record(day: "2026-02-30"),
            record(day: "2026-13-01"), record(day: "2026-09-12' OR 1=1"), record(seconds: .nan),
        ]
        try UsageHistoryStore.recordEffort(malformed + [record(id: hash("f"), tokens: 0)], at: database)
        let rows = try UsageHistoryStore.effortRows(at: database)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.tokens, 0)
    }

    func testExistingQuotaAndTokenHistorySurviveEffortSchemaAddition() throws {
        XCTAssertTrue(try UsageHistoryStore.tokenRows(at: database).isEmpty)
        try UsageHistoryStore.recordEffort([record()], at: database)
        XCTAssertTrue(try UsageHistoryStore.quotaRows(at: database).isEmpty)
        XCTAssertEqual(try UsageHistoryStore.effortRows(at: database).count, 1)
        XCTAssertEqual(
            try UsageHistoryStore.bounds(at: database), HistoryBounds(firstDay: "2026-09-12", lastDay: "2026-09-12"))
    }

    func testBoundsCombineEffortHistoryWithoutLosingOlderDailyHistory() throws {
        let snapshot = ProviderUsageSnapshot(
            provider: .codex, windows: [],
            dailyUsage: [DailyTokenUsage(day: "2026-08-01", tokens: 100)], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: nil)
        try UsageHistoryStore.record(snapshot, at: database)
        try UsageHistoryStore.recordEffort([record(day: "2026-09-12")], at: database)
        XCTAssertEqual(
            try UsageHistoryStore.bounds(at: database),
            HistoryBounds(firstDay: "2026-08-01", lastDay: "2026-09-12"))
        try UsageHistoryStore.recordEffort([record(id: hash("b"), day: "2026-07-01")], at: database)
        XCTAssertEqual(
            try UsageHistoryStore.bounds(at: database),
            HistoryBounds(firstDay: "2026-07-01", lastDay: "2026-09-12"))
    }

    private func hash(_ character: String) -> String { String(repeating: character, count: 64) }

    private func record(
        id: String = String(repeating: "a", count: 64), provider: UsageProvider = .codex,
        day: String = "2026-09-12", seconds: Double = 100,
        model: String = "gpt-6", effort: String = "high", tokens: Int = 10
    ) -> EffortUsageRecord {
        EffortUsageRecord(
            id: id, provider: provider, recordedAt: Date(timeIntervalSince1970: seconds), day: day,
            model: model, effort: effort, tokens: tokens)
    }
}
