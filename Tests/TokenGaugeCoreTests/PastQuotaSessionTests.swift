import XCTest

@testable import TokenGaugeCore

final class PastQuotaSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600

    private func row(_ offset: Double, used: Double, resetIn reset: Double, account: String? = "a") -> HistoryQuotaRow {
        HistoryQuotaRow(
            sampledAt: now.addingTimeInterval(offset * hour), provider: .claude, windowID: "five_hour",
            displayName: nil, usedPercentage: used, resetsAt: now.addingTimeInterval(reset * hour),
            durationMinutes: 300, accountFingerprint: account)
    }

    private func history(_ rows: [HistoryQuotaRow]) throws -> [PastQuotaSession] {
        let window = QuotaWindow(
            id: "five_hour", usedPercentage: 30, resetsAt: now.addingTimeInterval(2 * hour), durationMinutes: 300,
            displayName: nil)
        let current = try XCTUnwrap(
            QuotaForecast.make(provider: .claude, window: window, rows: rows, now: now, accountFingerprint: "a"))
        return PastQuotaSession.history(like: current, rows: rows, accountFingerprint: "a")
    }

    func testPastSessionsAreNewestFirstWithTheirOutcomeAndGradedCall() throws {
        let rows = [
            row(-17, used: 0, resetIn: -13), row(-14, used: 0, resetIn: -13),
            row(-12.5, used: 50, resetIn: -8), row(-9, used: 52, resetIn: -8),
            row(-7.5, used: 20, resetIn: -3), row(-7, used: 55, resetIn: -3 + 1 / 3600),
            row(-6, used: 80, resetIn: -3), row(-5, used: 100, resetIn: -3), row(-4, used: 100, resetIn: -3),
            row(-6.5, used: 99, resetIn: -1, account: "b"),
            row(-2, used: 10, resetIn: 2), row(-1, used: 25, resetIn: 2),
        ]

        let sessions = try history(rows)

        XCTAssertEqual(
            sessions.map(\.forecast.reset), [now.addingTimeInterval(-3 * hour), now.addingTimeInterval(-8 * hour)])
        let ranOut = try XCTUnwrap(sessions.first)
        XCTAssertTrue(ranOut.forecast.isCompleted)
        XCTAssertEqual(ranOut.forecast.verdict, .exhausted)
        XCTAssertEqual(ranOut.forecast.start, now.addingTimeInterval(-8 * hour))
        XCTAssertEqual(ranOut.forecast.points.count, 7)
        XCTAssertEqual(ranOut.depletedAt, now.addingTimeInterval(-5 * hour))
        XCTAssertEqual(ranOut.call?.madeAt, now.addingTimeInterval(-7 * hour))
        let predicted = try XCTUnwrap(ranOut.call?.predictedRunOut)
        XCTAssertEqual(predicted.timeIntervalSince(now), (-7 + 45.0 / 55) * hour, accuracy: 60)
        XCTAssertEqual(ranOut.callWasRight, true)

        let lasted = try XCTUnwrap(sessions.last)
        XCTAssertNil(lasted.depletedAt)
        XCTAssertEqual(lasted.forecast.remaining, 48)
        XCTAssertEqual(lasted.forecast.verdict, .lasts(margin: 48))
        XCTAssertNotNil(lasted.call?.predictedRunOut)
        XCTAssertEqual(lasted.callWasRight, false)
    }

    func testASessionThatJumpsPastTheThresholdStraightToFullHasNoCall() throws {
        let sessions = try history([row(-7, used: 30, resetIn: -3), row(-6, used: 100, resetIn: -3)])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.depletedAt, now.addingTimeInterval(-6 * hour))
        XCTAssertNil(sessions.first?.call)
        XCTAssertNil(sessions.first?.callWasRight)
    }
}
