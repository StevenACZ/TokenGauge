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

        let snapshot = ClaudeUsageParser.normalize(
            capture,
            dailyUsage: [DailyTokenUsage(day: "2026-08-25", tokens: 50)]
        )
        XCTAssertEqual(snapshot.windows.map(\.durationMinutes), [300, 10_080])
        XCTAssertEqual(snapshot.dailyUsage.first?.tokens, 50)
    }

    func testRejectsPayloadWithoutQuotaWindows() {
        let input = Data("{\"rate_limits\":{\"extra_usage\":{\"enabled\":true}}}".utf8)
        XCTAssertThrowsError(try ClaudeUsageParser.capture(from: input))
    }
}
