import XCTest

@testable import TokenGaugeCore

final class QuotaForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600

    private func row(
        _ offset: Double, used: Double, reset: Date, account: String? = nil
    ) -> HistoryQuotaRow {
        HistoryQuotaRow(
            sampledAt: now.addingTimeInterval(offset * hour), provider: .claude, windowID: "weekly",
            displayName: nil, usedPercentage: used, resetsAt: reset, durationMinutes: 10_080,
            accountFingerprint: account)
    }

    private func forecast(
        used: Double, resetIn hours: Double, rows: [HistoryQuotaRow], account: String? = nil
    ) -> QuotaForecast? {
        let window = QuotaWindow(
            id: "weekly", usedPercentage: used, resetsAt: now.addingTimeInterval(hours * hour),
            durationMinutes: 10_080, displayName: nil)
        return QuotaForecast.make(provider: .claude, window: window, rows: rows, now: now, accountFingerprint: account)
    }

    func testSteadyBurnRunsOutBeforeReset() throws {
        let reset = now.addingTimeInterval(72 * hour)
        let rows = (1...15).map { row(-96 + Double($0) * 6, used: 0.75 * Double($0) * 6, reset: reset) }
        let foreign = row(-3, used: 99, reset: reset, account: "b")
        let result = try XCTUnwrap(forecast(used: 72, resetIn: 72, rows: rows + [foreign], account: "a"))
        XCTAssertEqual(result.points.count, 17)
        XCTAssertEqual(try XCTUnwrap(result.pointsPerHour), 0.75, accuracy: 0.001)
        guard case .runsOut(let date) = result.verdict else { return XCTFail("\(result.verdict)") }
        XCTAssertEqual(date.timeIntervalSince(now), 28 / 0.75 * hour, accuracy: 60)
    }

    func testEarlyResetKeepsConsumptionOnBothSides() throws {
        let reset = now.addingTimeInterval(72 * hour)
        let rows = (1...15).map { index -> HistoryQuotaRow in
            let elapsed = Double(index) * 6
            return row(-96 + elapsed, used: elapsed <= 60 ? elapsed : elapsed - 66, reset: reset)
        }
        let result = try XCTUnwrap(forecast(used: 30, resetIn: 72, rows: rows))
        XCTAssertEqual(result.boosts.map(\.date), [now.addingTimeInterval(-30 * hour)])
        XCTAssertEqual(try XCTUnwrap(result.pointsPerHour), 66 / 72, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.recentPointsPerHour), 1, accuracy: 0.001)
        guard case .tight(let margin) = result.verdict else { return XCTFail("\(result.verdict)") }
        XCTAssertEqual(margin, 4, accuracy: 0.01)
    }

    func testFlatRecentDaysLast() throws {
        let reset = now.addingTimeInterval(48 * hour)
        let rows = (1...19).map { row(-120 + Double($0) * 6, used: min(50, Double($0) * 12.5), reset: reset) }
        let result = try XCTUnwrap(forecast(used: 50, resetIn: 48, rows: rows))
        XCTAssertEqual(result.pointsPerHour, 0)
        XCTAssertEqual(result.verdict, .lasts(margin: 50))
        XCTAssertNil(result.runsOutAt)
    }

    func testUntouchedWindowHasNoUsage() throws {
        let result = try XCTUnwrap(forecast(used: 0, resetIn: 144, rows: []))
        XCTAssertEqual(result.verdict, .noUsage)
    }

    func testPaceSpansThePreviousWindow() throws {
        let start = now.addingTimeInterval(-12 * hour)
        let previous = (0...9).map { row(-72 + Double($0) * 6, used: 20 + Double($0) * 6, reset: start) }
        let current = row(-6, used: 6, reset: now.addingTimeInterval(156 * hour))
        let result = try XCTUnwrap(forecast(used: 12, resetIn: 156, rows: previous + [current]))
        XCTAssertEqual(result.points.count, 3)
        XCTAssertEqual(try XCTUnwrap(result.pointsPerHour), 66 / 72, accuracy: 0.001)
    }

    func testShortWindowHasNoPace() throws {
        let result = try XCTUnwrap(forecast(used: 2, resetIn: 166, rows: []))
        XCTAssertNil(result.pointsPerHour)
        XCTAssertNil(result.recentPointsPerHour)
        XCTAssertEqual(result.verdict, .lasts(margin: 98))
    }

    private func sessionRow(_ offset: Double, used: Double, reset: Date) -> HistoryQuotaRow {
        HistoryQuotaRow(
            sampledAt: now.addingTimeInterval(offset * hour), provider: .claude, windowID: "five_hour",
            displayName: nil, usedPercentage: used, resetsAt: reset, durationMinutes: 300, accountFingerprint: nil)
    }

    private func session(used: Double, resetIn hours: Double, rows: [HistoryQuotaRow] = []) -> QuotaForecast? {
        let window = QuotaWindow(
            id: "five_hour", usedPercentage: used, resetsAt: now.addingTimeInterval(hours * hour),
            durationMinutes: 300, displayName: nil)
        return QuotaForecast.make(provider: .claude, window: window, rows: rows, now: now)
    }

    func testSessionRunsOutBeforeItsReset() throws {
        let result = try XCTUnwrap(session(used: 78, resetIn: 1.15))
        XCTAssertTrue(result.isSession)
        XCTAssertEqual(try XCTUnwrap(result.pointsPerHour), 78 / 3.85, accuracy: 0.001)
        guard case .runsOut(let date) = result.verdict else { return XCTFail("\(result.verdict)") }
        XCTAssertEqual(date.timeIntervalSince(now), 22 / (78 / 3.85) * hour, accuracy: 1)
        XCTAssertEqual(result.budget, 22 / 1.15, accuracy: 0.001)
    }

    func testSessionIgnoresThePreviousSession() throws {
        let previous = (0...8).map {
            sessionRow(-3 + Double($0) * 0.25, used: Double($0) * 10, reset: now.addingTimeInterval(-hour / 3))
        }
        let result = try XCTUnwrap(session(used: 10, resetIn: 5 - 1.0 / 3, rows: previous))
        XCTAssertEqual(try XCTUnwrap(result.pointsPerHour), 30, accuracy: 0.001)
        XCTAssertNil(result.recentPointsPerHour)
        XCTAssertEqual(result.points.count, 2)
    }

    func testSessionRecentHourShowsASlowdown() throws {
        let reset = now.addingTimeInterval(2 * hour)
        let rows = (1...12).map { sessionRow(-3 + Double($0) * 0.25, used: min(45, Double($0) * 7.5), reset: reset) }
        let result = try XCTUnwrap(session(used: 45, resetIn: 2, rows: rows))
        XCTAssertEqual(try XCTUnwrap(result.pointsPerHour), 15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.recentPointsPerHour), 0, accuracy: 0.001)
        XCTAssertEqual(result.verdict, .lasts(margin: 25))
    }

    func testOtherAccountTimeIsNeitherResetNorPace() throws {
        let reset = now.addingTimeInterval(120 * hour)
        let before = (30...47).map { row(-Double($0), used: 2 * (48 - Double($0)), reset: reset, account: "a") }
        let other = (10...29).map { row(-Double($0) - 0.5, used: 80, reset: now, account: "b") }
        let after = (1...9).map { row(-Double($0), used: 10 - Double($0), reset: reset, account: "a") }
        let result = try XCTUnwrap(forecast(used: 10, resetIn: 120, rows: before + other + after, account: "a"))
        XCTAssertEqual(
            result.away,
            [DateInterval(start: now.addingTimeInterval(-29.5 * hour), end: now.addingTimeInterval(-9 * hour))])
        XCTAssertEqual(result.boosts, [])
        XCTAssertEqual(try XCTUnwrap(result.pointsPerHour), 45 / 27, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.recentPointsPerHour), 1, accuracy: 0.001)
    }
}
