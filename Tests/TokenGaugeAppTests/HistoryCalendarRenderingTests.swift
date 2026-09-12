import AppKit
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class HistoryCalendarRenderingTests: XCTestCase {
    func testCalendarCentersBeforeDrawingAndKeepsViewportOnSelectionAndRefresh() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let today = try XCTUnwrap(days.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: now) })
        let view = HistoryCalendarScrollView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 96),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex, .claude],
                selectedDayKey: days[today].id, focusID: "year"
            ) { _ in })
        view.layout()
        XCTAssertEqual(view.contentView.bounds.midX, view.calendar.cellRect(today).midX, accuracy: 0.5)
        XCTAssertFalse(view.hasHorizontalScroller)
        XCTAssertFalse(view.hasVerticalScroller)
        let offset: CGFloat = 100
        view.contentView.scroll(to: NSPoint(x: offset, y: 0))
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex, .claude],
                selectedDayKey: days[0].id, focusID: "year"
            ) { _ in })
        view.layout()
        XCTAssertEqual(view.contentView.bounds.minX, offset, accuracy: 0.5)
        view.needsCenter = true
        view.layout()
        XCTAssertEqual(view.contentView.bounds.midX, view.calendar.cellRect(today).midX, accuracy: 0.5)
        XCTAssertLessThan(view.subviews.count, 10)
    }

    func testLayoutDoesNotTriggerHoverAndFutureDaysCannotBeSelected() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let view = HistoryCalendarScrollView()
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 96)
        var selected: [String] = []
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex],
                selectedDayKey: nil, focusID: "year"
            ) { selected.append($0) })
        view.layout()
        view.calendar.updateTrackingAreas()
        XCTAssertTrue(selected.isEmpty)
        view.calendar.select(0)
        XCTAssertEqual(selected, [days[0].id])
        if let future = days.firstIndex(where: { $0.date > now }) {
            view.calendar.select(future)
            XCTAssertEqual(selected.count, 1)
        }
    }
}
