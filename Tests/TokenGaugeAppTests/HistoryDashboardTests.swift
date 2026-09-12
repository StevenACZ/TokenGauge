import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class HistoryDashboardTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        return value
    }

    func testWeekNavigationUsesMondayAcrossTheYearBoundary() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let week = HistoryDashboardModel.interval(mode: .week, offset: 0, now: now, calendar: calendar)
        XCTAssertEqual(HistoryDashboardModel.dayKey(week.start, calendar: calendar), "2025-12-29")
        XCTAssertEqual(HistoryDashboardModel.dayKey(week.end, calendar: calendar), "2026-01-05")
        let previous = HistoryDashboardModel.interval(mode: .week, offset: -1, now: now, calendar: calendar)
        XCTAssertEqual(HistoryDashboardModel.dayKey(previous.start, calendar: calendar), "2025-12-22")
    }

    func testLeapYearIncludesEveryDateButDoesNotInventZeroDays() {
        let now = calendar.date(from: DateComponents(year: 2024, month: 7, day: 1))!
        let year = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now, calendar: calendar)
        let days = HistoryDashboardModel.makeDays(interval: year, tokens: [], efforts: [], calendar: calendar)
        XCTAssertEqual(days.count, 366)
        XCTAssertTrue(days.contains { $0.id == "2024-02-29" })
        XCTAssertTrue(days.allSatisfy { $0.total(for: [.codex, .claude]) == nil })
    }

    func testObservedSourcesAreNeverAddedTwiceAndZeroRemainsDistinct() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let interval = HistoryDashboardModel.interval(mode: .recent, offset: 0, now: now, calendar: calendar)
        let days = HistoryDashboardModel.makeDays(
            interval: interval,
            tokens: [
                HistoryTokenRow(day: "2026-09-12", provider: .codex, model: "all", tokens: 100),
                HistoryTokenRow(day: "2026-09-12", provider: .codex, model: "gpt-6-astra", tokens: 60),
                HistoryTokenRow(day: "2026-09-11", provider: .codex, model: "all", tokens: 0),
            ],
            efforts: [
                HistoryEffortRow(
                    day: "2026-09-12", provider: .codex, model: "gpt-6-astra", effort: "medium", tokens: 150)
            ], calendar: calendar)
        XCTAssertEqual(days.last?.tokens(for: .codex), 150)
        XCTAssertEqual(days.first { $0.id == "2026-09-11" }?.tokens(for: .codex), 0)
        XCTAssertNil(days.last?.tokens(for: .claude))
        XCTAssertNil(days.first { $0.id == "2026-09-10" }?.tokens(for: .codex))
    }

    func testEffortOnlyHistoryHasAUsableObservedTotal() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let interval = HistoryDashboardModel.interval(mode: .recent, offset: 0, now: now, calendar: calendar)
        let days = HistoryDashboardModel.makeDays(
            interval: interval, tokens: [],
            efforts: [
                HistoryEffortRow(
                    day: "2026-09-12", provider: .claude, model: "claude-fable", effort: "high", tokens: 10),
                HistoryEffortRow(
                    day: "2026-09-12", provider: .claude, model: "claude-fable", effort: "xhigh", tokens: 20),
            ], calendar: calendar)
        XCTAssertEqual(days.last?.tokens(for: .claude), 30)
    }

    func testPaceImmediatelyRejectsResetOrDecreaseBeforeHistoryReloads() {
        let now = Date()
        let reset = now.addingTimeInterval(86400)
        let pace = QuotaPace(
            pointsPerHour: 5, observedMinutes: 40, sampledAt: now,
            resetsAt: reset, lastUsedPercentage: 20)
        func window(_ used: Double, reset: Date) -> QuotaWindow {
            QuotaWindow(
                id: "weekly", usedPercentage: used, resetsAt: reset,
                durationMinutes: 10080, displayName: nil)
        }
        XCTAssertNotNil(HistoryDashboardModel.usablePace(pace, for: window(21, reset: reset), now: now))
        XCTAssertNil(HistoryDashboardModel.usablePace(pace, for: window(19, reset: reset), now: now))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(pace, for: window(21, reset: reset.addingTimeInterval(86400)), now: now))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(pace, for: window(21, reset: reset), now: now.addingTimeInterval(1201)))
    }

    func testPreviewStoresDoNotReadOrCollectLiveHistory() {
        let name = "TokenGauge.history-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(UsageStore(defaults: defaults).historyReadsEnabled)
        let store = UsageStore(defaults: defaults)
        store.historyMode = .calendar
        store.showHourlyPace = false
        let reopened = UsageStore(defaults: defaults)
        XCTAssertEqual(reopened.historyMode, .calendar)
        XCTAssertFalse(reopened.showHourlyPace)
    }
}
