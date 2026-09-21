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
        let resets = HistoryReset.upcoming(provider: .codex, windows: windows, now: now, through: future)
        XCTAssertEqual(resets.map(\.date), [future])
    }

    func testSharedWeeklyQuotasProduceOneResetPerWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = now.addingTimeInterval(3600)
        let windows = ["weekly", "fable"].map {
            Fixture.window(id: $0, resetsAt: first, durationMinutes: 10080)
        }
        let resets = HistoryReset.upcoming(
            provider: .claude, windows: windows, now: now,
            through: first.addingTimeInterval(21 * 86400))
        XCTAssertEqual(resets.count, 4)
        XCTAssertEqual(resets.map(\.isProjected), [false, true, true, true])
        XCTAssertEqual(Set(resets.map(\.id)).count, 4)
        XCTAssertEqual(resets.last?.date, first.addingTimeInterval(21 * 86400))
        XCTAssertTrue(HistoryReset.upcoming(provider: .claude, windows: [], now: now).isEmpty)
    }

    func testDifferentWeeklySchedulesRemainSeparateAndConfirmedDatesWin() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = now.addingTimeInterval(3600)
        let next = first.addingTimeInterval(7 * 86400)
        let windows = [
            Fixture.window(id: "general", resetsAt: first, durationMinutes: 10080),
            Fixture.window(id: "reserve", resetsAt: next, durationMinutes: 10080),
            Fixture.window(id: "different", resetsAt: first.addingTimeInterval(86400), durationMinutes: 10080),
        ]
        let resets = HistoryReset.upcoming(provider: .codex, windows: windows, now: now, through: next)
        XCTAssertEqual(resets.count, 3)
        XCTAssertTrue(resets.allSatisfy { !$0.isProjected })
    }

    func testCancellationRemovesOnlyThatProvidersEntireForecast() throws {
        try withDefaults { defaults in
            let snapshots = UsageProvider.allCases.map { provider in
                Fixture.snapshot(
                    provider,
                    windows: [
                        Fixture.window(
                            id: provider == .codex ? "codex.primary" : "seven_day",
                            resetsAt: Date().addingTimeInterval(86400), durationMinutes: 10080)
                    ])
            }
            let store = Fixture.store(defaults: defaults, snapshots: snapshots)
            store.displayMode = .unified
            let view = PopoverView(store: store, showSettings: {}, showAbout: {})
            XCTAssertGreaterThan(view.upcomingResets.filter { $0.provider == .claude }.count, 3)
            store.setCancelled(true, for: .claude)
            XCTAssertFalse(view.upcomingResets.contains { $0.provider == .claude })
            XCTAssertGreaterThan(view.upcomingResets.filter { $0.provider == .codex }.count, 3)
            store.setCancelled(true, for: .codex)
            XCTAssertTrue(view.upcomingResets.isEmpty)
        }
    }

    func testFutureResetCanBeSelectedAndRefreshRemovesItsMarker() throws {
        let calendar = Calendar.current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        let date = calendar.startOfDay(for: tomorrow)
        let day = HistoryCalendarDay(id: HistoryDashboardModel.dayKey(date), date: date, totals: [:], efforts: [])
        let resets = [UsageProvider.codex, .claude].map {
            HistoryReset(provider: $0, date: tomorrow)
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
