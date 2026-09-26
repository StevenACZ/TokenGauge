import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class StatsSummaryTests: XCTestCase {
    private let calendar = Calendar.current
    private var now: Date { calendar.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date() }

    private func input(days range: ClosedRange<Int>, today: Int, extraModel: String? = nil) -> StatsSummary.Input {
        let start = calendar.startOfDay(for: now)
        var days: [HistoryCalendarDay] = []
        var tokens: [HistoryTokenRow] = []
        for offset in range {
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let key = HistoryDashboardModel.dayKey(date)
            let total = offset == 0 ? today : 100
            days.append(HistoryCalendarDay(id: key, date: date, totals: [.claude: total], efforts: []))
            tokens.append(HistoryTokenRow(day: key, provider: .claude, model: "claude-opus-5-5", tokens: total))
        }
        if let extraModel {
            tokens.append(
                HistoryTokenRow(
                    day: HistoryDashboardModel.dayKey(start), provider: .claude, model: extraModel, tokens: 1))
        }
        return StatsSummary.Input(days: days, tokens: tokens, efforts: [])
    }

    func testSpikeAgainstTypicalDay() {
        let summary = StatsSummary.make(input(days: -40...0, today: 300), providers: [.claude], now: now)
        XCTAssertEqual(summary.typicalDay, 100)
        XCTAssertEqual(summary.today, 300)
        guard case .spike(let ratio) = summary.insight else { return XCTFail("\(String(describing: summary.insight))") }
        XCTAssertEqual(ratio, 3, accuracy: 0.001)
    }

    func testNewModelWinsOverSpike() {
        let summary = StatsSummary.make(
            input(days: -40...0, today: 300, extraModel: "claude-fable-5-1"), providers: [.claude], now: now)
        guard case .newModel(let name) = summary.insight else {
            return XCTFail("\(String(describing: summary.insight))")
        }
        XCTAssertEqual(name, "Fable 5.1")
    }

    func testDeltasNeedFullPreviousPeriod() {
        let short = StatsSummary.make(input(days: -2...0, today: 100), providers: [.claude], now: now)
        XCTAssertNil(short.previousWeek)
        XCTAssertNil(short.previousMonth)
        XCTAssertNil(short.typicalDay)
        let long = StatsSummary.make(input(days: -70...0, today: 100), providers: [.claude], now: now)
        XCTAssertNotNil(long.previousWeek)
        XCTAssertNotNil(long.previousMonth)
        XCTAssertEqual(long.previousWeek, long.week)
    }

    func testSkillsAndTurnsFollowSelectedProviders() {
        var data = input(days: -10...0, today: 100)
        let today = HistoryDashboardModel.dayKey(now)
        data.activity = [
            HistoryActivityRow(
                day: today, provider: .claude, kind: .skill, key: "memory-closeout", count: 3, total: 3, maximum: 1),
            HistoryActivityRow(
                day: today, provider: .claude, kind: .skill, key: "iabrain-board", count: 5, total: 5, maximum: 1),
            HistoryActivityRow(
                day: today, provider: .codex, kind: .skill, key: "agent-delegation", count: 9, total: 9, maximum: 1),
            HistoryActivityRow(
                day: today, provider: .claude, kind: .turn, key: "", count: 2, total: 90_000, maximum: 60_000),
        ]
        let summary = StatsSummary.make(data, providers: [.claude], now: now)
        XCTAssertEqual(summary.skills.map(\.label), ["iabrain-board", "memory-closeout"])
        XCTAssertEqual(summary.turns, StatsTurns(todayMilliseconds: 90_000, todayCount: 2, longestMilliseconds: 60_000))
    }
}
