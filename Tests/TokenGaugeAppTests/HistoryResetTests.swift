import AppKit
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class HistoryResetTests: XCTestCase {
    func testOnlyKnownFutureWeeklyResetsAreScheduled() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = now.addingTimeInterval(86400)
        let windows = [
            Fixture.window(id: "expired", resetsAt: now, durationMinutes: 10080),
            Fixture.window(id: "unknown", durationMinutes: 10080),
            Fixture.window(id: "session", resetsAt: future, durationMinutes: 300),
            Fixture.window(id: "weekly", resetsAt: future, durationMinutes: 10080),
        ]
        let resets = HistoryReset.upcoming(provider: .codex, windows: windows, now: now)
        XCTAssertEqual(resets.map(\.window.id), ["weekly"])
        XCTAssertEqual(resets.map(\.date), [future])
    }

    func testFutureResetCanBeSelectedAndRefreshRemovesItsMarker() throws {
        let calendar = Calendar.current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        let date = calendar.startOfDay(for: tomorrow)
        let day = HistoryCalendarDay(id: HistoryDashboardModel.dayKey(date), date: date, totals: [:], efforts: [])
        let resets = [UsageProvider.codex, .claude].map {
            HistoryReset(provider: $0, window: Fixture.window(id: "weekly", durationMinutes: 10080), date: tomorrow)
        }
        let canvas = HistoryCalendarCanvas()
        var selected: String?
        canvas.update(
            HistoryCalendarView(
                days: [day], providers: [.codex, .claude], selectedDayKey: nil, focusID: "test", resets: resets
            ) { selected = $0 })
        XCTAssertTrue(canvas.isEnabled(at: 0))
        XCTAssertTrue(canvas.accessibilityLabel(at: 0).contains("Codex"))
        XCTAssertTrue(canvas.accessibilityLabel(at: 0).contains("Claude"))
        canvas.select(0)
        XCTAssertEqual(selected, day.id)
        canvas.update(
            HistoryCalendarView(
                days: [day], providers: [.codex, .claude], selectedDayKey: nil, focusID: "test"
            ) { selected = $0 })
        XCTAssertFalse(canvas.isEnabled(at: 0))
    }
}
