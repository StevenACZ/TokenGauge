import Foundation
import XCTest

@testable import TokenGaugeCore

final class ClaudeAccountUsageParserTests: XCTestCase {
    func testMapsEveryPlanLimitIncludingTheModelScopedWeekly() throws {
        let input = Data(
            """
            {
              "five_hour": {"utilization": 13.0},
              "limits": [
                {"kind": "session", "percent": 13, "resets_at": "2026-08-25T22:59:59.535623+00:00", "scope": null},
                {"kind": "weekly_all", "percent": 38, "resets_at": "2026-08-31T07:59:59.535654+00:00", "scope": null},
                {"kind": "weekly_scoped", "percent": 56, "resets_at": "2026-08-31T07:59:59.535961+00:00",
                 "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}},
                {"kind": "future_kind", "percent": 5, "resets_at": null, "scope": null}
              ]
            }
            """.utf8
        )

        let windows = try ClaudeAccountUsageParser.parse(input)

        XCTAssertEqual(windows.map(\.id), ["five_hour", "seven_day", "seven_day_fable"])
        XCTAssertEqual(windows.map(\.usedPercentage), [13, 38, 56])
        XCTAssertEqual(windows.map(\.durationMinutes), [300, 10_080, 10_080])
        XCTAssertEqual(windows.map(\.displayName), [nil, nil, "Fable"])
        let expected = ISO8601DateFormatter().date(from: "2026-08-25T22:59:59+00:00")!
        XCTAssertEqual(
            windows.first?.resetsAt?.timeIntervalSince1970 ?? 0,
            expected.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testSkipsScopedLimitsWithoutAModelName() throws {
        let input = Data(
            """
            {"limits": [
              {"kind": "weekly_all", "percent": 10, "resets_at": null, "scope": null},
              {"kind": "weekly_scoped", "percent": 90, "resets_at": null, "scope": {"model": null}}
            ]}
            """.utf8
        )
        XCTAssertEqual(try ClaudeAccountUsageParser.parse(input).map(\.id), ["seven_day"])
    }

    func testRejectsPayloadWithoutLimits() {
        XCTAssertThrowsError(try ClaudeAccountUsageParser.parse(Data("{\"limits\":[]}".utf8)))
    }
}
