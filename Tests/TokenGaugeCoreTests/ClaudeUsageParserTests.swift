import Foundation
import XCTest

@testable import TokenGaugeCore

final class ClaudeUsageParserTests: XCTestCase {
    func testCapturesOnlyNormalizedQuotaFields() throws {
        let input = Data(
            """
            {
              "cwd": "/private/project",
              "model": {"display_name": "Opus"},
              "rate_limits": {
                "five_hour": {"used_percentage": 23.5, "resets_at": 2000000000, "ignored": "secret"},
                "seven_day": {"used_percentage": 41.2, "resets_at": 2000100000},
                "extra_usage": {"enabled": true}
              }
            }
            """.utf8
        )
        let capturedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let capture = try ClaudeUsageParser.capture(from: input, capturedAt: capturedAt)

        XCTAssertEqual(capture.capturedAt, capturedAt)
        XCTAssertEqual(Set(capture.windows.keys), ["five_hour", "seven_day"])
        XCTAssertEqual(capture.windows["five_hour"]?.usedPercentage, 23.5)
        XCTAssertEqual(capture.windows["seven_day"]?.resetsAt, Date(timeIntervalSince1970: 2_000_100_000))

        let buckets = [
            ModelTokenBucket(
                day: "2026-08-25",
                hourStart: Date(timeIntervalSince1970: 1_900_000_000),
                model: "claude-fable-5",
                tokens: 30
            ),
            ModelTokenBucket(
                day: "2026-08-25",
                hourStart: Date(timeIntervalSince1970: 1_900_003_600),
                model: "claude-opus-5",
                tokens: 20
            ),
        ]
        let snapshot = ClaudeUsageParser.normalize(capture, modelBuckets: buckets)
        XCTAssertEqual(snapshot.windows.map(\.durationMinutes), [300, 10_080])
        XCTAssertEqual(snapshot.dailyUsage, [DailyTokenUsage(day: "2026-08-25", tokens: 50)])
        XCTAssertEqual(snapshot.modelBuckets.count, 2)
        XCTAssertEqual(
            ModelTokenAggregator.byModel(snapshot.modelBuckets, since: nil).map(\.model),
            ["claude-fable-5", "claude-opus-5"]
        )
        let sessionOnly = ModelTokenAggregator.byModel(
            snapshot.modelBuckets,
            since: Date(timeIntervalSince1970: 1_900_003_600)
        )
        XCTAssertEqual(sessionOnly.map(\.model), ["claude-opus-5"])
        XCTAssertEqual(sessionOnly.map(\.tokens), [20])
    }

    func testRejectsPayloadWithoutQuotaWindows() {
        let input = Data("{\"rate_limits\":{\"extra_usage\":{\"enabled\":true}}}".utf8)
        XCTAssertThrowsError(try ClaudeUsageParser.capture(from: input))
    }
}
