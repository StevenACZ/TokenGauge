import Foundation
import XCTest

@testable import TokenGaugeCore

final class CodexUsageParserTests: XCTestCase {
    func testParsesQuotaWindowsUsageAndCredits() throws {
        let input = """
            {"id":1,"result":{"userAgent":"test"}}
            {"method":"remoteControl/status/changed","params":{"status":"disconnected"}}
            {"id":3,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":2000100000},"credits":{"balance":3}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":2000100000}},"codex_other":{"limitId":"codex_other","limitName":"Other","primary":{"usedPercent":50,"windowDurationMins":60,"resetsAt":2000200000},"secondary":null}},"rateLimitResetCredits":{"availableCount":2}}}
            {"id":4,"result":{"summary":{"lifetimeTokens":123456,"peakDailyTokens":45000,"longestRunningTurnSec":99,"currentStreakDays":4,"longestStreakDays":8},"dailyUsageBuckets":[{"startDate":"2026-08-24","tokens":1000},{"startDate":"2026-08-25","tokens":2000}]}}
            """

        let capturedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let snapshot = try CodexUsageParser.parse(Data(input.utf8), capturedAt: capturedAt)

        XCTAssertTrue(snapshot.activityReadSucceeded)
        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.windows.map(\.durationMinutes), [60, 300, 10_080])
        XCTAssertEqual(snapshot.windows.first { $0.durationMinutes == 300 }?.remainingPercentage, 75)
        XCTAssertEqual(
            snapshot.dailyUsage,
            [
                DailyTokenUsage(day: "2026-08-24", tokens: 1000),
                DailyTokenUsage(day: "2026-08-25", tokens: 2000),
            ])
        XCTAssertEqual(snapshot.summary?.lifetimeTokens, 123_456)
        XCTAssertEqual(snapshot.summary?.currentStreakDays, 4)
        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertEqual(snapshot.creditBalance, 3)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertEqual(snapshot.longestWindow?.usedPercentage, 40)
    }

    func testKeepsQuotaWhenUsageHistoryResponseIsMissing() throws {
        let input = Data(
            "{\"id\":3,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":10,\"windowDurationMins\":300}}}}\n"
                .utf8
        )
        let snapshot = try CodexUsageParser.parse(input)
        XCTAssertEqual(snapshot.windows.first?.usedPercentage, 10)
        XCTAssertTrue(snapshot.dailyUsage.isEmpty)
        XCTAssertNil(snapshot.summary)
    }

    func testActivityReadDistinguishesEmptySuccessFromMissingOrMalformedResponses() throws {
        let quota = #"{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":10}}}}"#
        let invalid = [
            "", #"{"id":4,"error":{"code":-1}}"#, #"{"id":4,"result":{}}"#,
            #"{"id":4,"result":{"dailyUsageBuckets":null}}"#,
            #"{"id":4,"result":{"dailyUsageBuckets":{}}}"#,
            #"{"id":4,"result":{"dailyUsageBuckets":[{}]}}"#,
            #"{"id":4,"result":{"dailyUsageBuckets":[{"startDate":"2026-09-07","tokens":true}]}}"#,
            #"{"id":4,"result":{"dailyUsageBuckets":[{"startDate":"invalid","tokens":1}]}}"#,
            #"{"id":4,"result":{"dailyUsageBuckets":[{"startDate":"2026-09-07","tokens":1.5}]}}"#,
            #"{"id":4,"result":{"dailyUsageBuckets":[{"startDate":"2026-09-07","tokens":1},{}]}}"#,
        ]
        for usage in invalid {
            let snapshot = try CodexUsageParser.parse(Data((quota + "\n" + usage).utf8))
            XCTAssertFalse(snapshot.activityReadSucceeded)
            XCTAssertTrue(snapshot.dailyUsage.isEmpty)
            XCTAssertEqual(snapshot.windows.first?.usedPercentage, 10)
        }
        let empty = quota + "\n" + #"{"id":4,"result":{"dailyUsageBuckets":[]}}"#
        XCTAssertTrue(try CodexUsageParser.parse(Data(empty.utf8)).activityReadSucceeded)
    }

    func testOlderSnapshotCacheCannotClaimSuccessfulActivityRead() throws {
        let old = Data(#"{"provider":"codex","windows":[],"dailyUsage":[]}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(ProviderUsageSnapshot.self, from: old).activityReadSucceeded)
        let fresh = ProviderUsageSnapshot(
            provider: .codex, windows: [], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: nil
        )
        XCTAssertTrue(fresh.activityReadSucceeded)
        let roundTrip = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: JSONEncoder().encode(fresh))
        XCTAssertTrue(roundTrip.activityReadSucceeded)
    }

    func testRejectsMissingQuotaResponse() {
        let input = Data("{\"id\":4,\"result\":{\"dailyUsageBuckets\":[]}}\n".utf8)
        XCTAssertThrowsError(try CodexUsageParser.parse(input))
    }

    func testPreservesDistinctBucketsWithMatchingMetrics() throws {
        let input = Data(
            """
            {"id":3,"result":{"rateLimitsByLimitId":{"first":{"limitName":"First","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":2000000000}},"second":{"limitName":"Second","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":2000000000}}}}}
            """.utf8
        )
        let snapshot = try CodexUsageParser.parse(input)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(Set(snapshot.windows.compactMap(\.displayName)), ["First", "Second"])
    }
}
