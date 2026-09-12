import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class HistoryProvenanceTests: XCTestCase {
    func testMixedFallbackCannotRewriteOldQuotaButPreservesFreshActivity() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appending(path: "history.sqlite")
        let now = Date()
        let old = now.addingTimeInterval(-3600)
        let windows = [
            QuotaWindow(
                id: "seven_day", usedPercentage: 10, resetsAt: now.addingTimeInterval(86400), durationMinutes: 10080,
                displayName: nil),
            QuotaWindow(
                id: "seven_day_fable", usedPercentage: 12, resetsAt: now.addingTimeInterval(86400),
                durationMinutes: 10080, displayName: "Fable"),
        ]
        let initial = ProviderUsageSnapshot(
            provider: .claude, windows: windows, dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: old)
        try UsageHistoryStore.record(initial, at: database)
        let fallback = ClaudeUsageClient.resolve(
            account: .failure(ClaudeAccountUsageError.credentialExpired),
            cached: ClaudeAccountSnapshot(capturedAt: old, windows: windows),
            capture: ClaudeCapturedSnapshot(
                capturedAt: now,
                windows: [
                    "seven_day": ClaudeCapturedWindow(usedPercentage: 80, resetsAt: now.addingTimeInterval(86400))
                ]),
            modelBuckets: [ModelTokenBucket(day: "2026-09-12", hourStart: now, model: "fable", tokens: 123)], now: now)
        XCTAssertEqual(fallback.snapshot.windows.first { $0.id == "seven_day" }?.usedPercentage, 80)
        UsageStore.archive(
            claudeResult: fallback,
            codexState: ProviderViewState(snapshot: nil, status: .unavailable, isRefreshing: false),
            at: database)
        let quota = try UsageHistoryStore.quotaRows(at: database)
        XCTAssertEqual(quota.count, 2)
        XCTAssertEqual(quota.first { $0.windowID == "seven_day" }?.usedPercentage, 10)
        XCTAssertEqual(try UsageHistoryStore.tokenRows(at: database).first?.tokens, 123)
    }

    func testStaleCodexCacheIsNotRecordedAsANewActivityObservation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appending(path: "history.sqlite")
        let snapshot = ProviderUsageSnapshot(
            provider: .codex, windows: [], dailyUsage: [DailyTokenUsage(day: "2026-09-12", tokens: 100)],
            summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
        UsageStore.archive(
            claudeResult: nil, codexState: ProviderViewState(snapshot: snapshot, status: .stale, isRefreshing: false),
            at: database)
        XCTAssertTrue(try UsageHistoryStore.tokenRows(at: database).isEmpty)
        UsageStore.archive(
            claudeResult: nil, codexState: ProviderViewState(snapshot: snapshot, status: .ready, isRefreshing: false),
            at: database)
        XCTAssertEqual(try UsageHistoryStore.tokenRows(at: database).first?.tokens, 100)
    }
}
