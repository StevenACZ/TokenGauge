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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: Theme.Layout.historyCalendarHeight),
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

    func testLastRowSelectionHasRoomForItsEntireStroke() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let lastRow = try XCTUnwrap(days.firstIndex { Calendar.current.component(.weekday, from: $0.date) == 1 })
        let view = HistoryCalendarScrollView()
        view.frame = NSRect(x: 0, y: 0, width: 440, height: Theme.Layout.historyCalendarHeight)
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex],
                selectedDayKey: days[lastRow].id, focusID: "year"
            ) { _ in })
        view.layout()
        let paintedBounds = view.calendar.cellRect(lastRow).insetBy(dx: -2, dy: -2)
        XCTAssertTrue(view.calendar.bounds.contains(paintedBounds))
        XCTAssertGreaterThanOrEqual(view.contentView.bounds.height - paintedBounds.maxY, 4)
    }

    func testLayoutDoesNotTriggerHoverAndFutureDaysCannotBeSelected() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let view = HistoryCalendarScrollView()
        view.frame = NSRect(x: 0, y: 0, width: 440, height: Theme.Layout.historyCalendarHeight)
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

    func testExitResetsToTodayOnlyWhileNothingIsPinned() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let view = HistoryCalendarScrollView()
        view.frame = NSRect(x: 0, y: 0, width: 440, height: Theme.Layout.historyCalendarHeight)
        var exits = 0
        var hovers: [String?] = []
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex, .claude], selectedDayKey: nil, focusID: "year",
                onHoverCard: { key, _ in hovers.append(key) }, onExitCalendar: { exits += 1 }
            ) { _ in })
        view.layout()
        view.calendar.updateTrackingAreas()
        XCTAssertTrue(view.calendar.trackingOptions.contains(.mouseEnteredAndExited))
        XCTAssertTrue(view.calendar.trackingOptions.contains(.mouseMoved))
        view.calendar.mouseExited(with: try exitEvent())
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(hovers, [nil])
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex, .claude], selectedDayKey: days[0].id, focusID: "year",
                pinnedDayKey: days[0].id, onHoverCard: { key, _ in hovers.append(key) },
                onExitCalendar: { exits += 1 }
            ) { _ in })
        view.calendar.mouseExited(with: try exitEvent())
        XCTAssertEqual(exits, 1)
    }

    func testCardAnchorIsRelativeToTheCalendarAndCarriesTheRootBounds() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let today = try XCTUnwrap(days.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: now) })
        let view = HistoryCalendarScrollView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: Theme.Layout.historyCalendarHeight),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.calendar.update(
            HistoryCalendarView(days: days, providers: [.codex], selectedDayKey: days[today].id, focusID: "year") {
                _ in
            })
        view.layout()
        let anchor = try XCTUnwrap(view.calendar.cardAnchor(today))
        let cell = view.calendar.cellRect(today)
        XCTAssertEqual(anchor.bounds, CGRect(x: 0, y: 0, width: 440, height: Theme.Layout.historyCalendarHeight))
        XCTAssertEqual(anchor.cell.minX, cell.minX - view.contentView.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(anchor.cell.minY, cell.minY, accuracy: 0.5)
        XCTAssertEqual(anchor.cell.size, cell.size)
        XCTAssertTrue(anchor.bounds.contains(anchor.cell))
        window.contentView = nil
        XCTAssertNil(view.calendar.cardAnchor(today))
    }

    func testScrollAndEmptyAreaClicksDismissTheCard() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let view = HistoryCalendarScrollView()
        view.frame = NSRect(x: 0, y: 0, width: 440, height: Theme.Layout.historyCalendarHeight)
        var dismissals = 0
        var hovers: [String?] = []
        var pins: [String] = []
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex], selectedDayKey: nil, focusID: "year",
                onHoverCard: { key, _ in hovers.append(key) }, onPinCard: { key, _ in pins.append(key) },
                onDismissCard: { dismissals += 1 }
            ) { _ in })
        view.layout()
        view.calendar.scrollDidMove()
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(hovers, [nil])
        view.calendar.mouseDown(with: try mouseDown(at: NSPoint(x: -1000, y: 0), windowNumber: 0))
        XCTAssertEqual(dismissals, 2)
        XCTAssertTrue(pins.isEmpty)
    }

    func testPinnedEventFilterDismissesOutsideClicksAndSwallowsEscape() throws {
        let now = Date()
        let interval = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let days = HistoryDashboardModel.makeDays(interval: interval, tokens: [], efforts: [])
        let view = HistoryCalendarScrollView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered,
            defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 600))
        window.contentView = root
        defer { window.contentView = nil }
        view.frame = NSRect(x: 0, y: 200, width: 440, height: Theme.Layout.historyCalendarHeight)
        root.addSubview(view)
        var dismissals = 0
        view.calendar.update(
            HistoryCalendarView(
                days: days, providers: [.codex], selectedDayKey: days[0].id, focusID: "year",
                pinnedDayKey: days[0].id, pinSafeFrames: [CGRect(x: 0, y: -100, width: 440, height: 60)],
                onDismissCard: { dismissals += 1 }
            ) { _ in })
        view.layout()
        let number = window.windowNumber
        XCTAssertTrue(view.calendar.passesPinnedEvent(try mouseDown(at: NSPoint(x: 220, y: 250), windowNumber: number)))
        XCTAssertEqual(dismissals, 0)
        XCTAssertTrue(view.calendar.passesPinnedEvent(try mouseDown(at: NSPoint(x: 220, y: 380), windowNumber: number)))
        XCTAssertEqual(dismissals, 0)
        XCTAssertTrue(view.calendar.passesPinnedEvent(try mouseDown(at: NSPoint(x: 220, y: 100), windowNumber: number)))
        XCTAssertEqual(dismissals, 1)
        XCTAssertFalse(view.calendar.passesPinnedEvent(try key(53, windowNumber: number)))
        XCTAssertEqual(dismissals, 2)
        XCTAssertTrue(view.calendar.passesPinnedEvent(try key(36, windowNumber: number)))
        XCTAssertEqual(dismissals, 2)
    }

    private func mouseDown(at location: NSPoint, windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func key(_ code: UInt16, windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }

    private func exitEvent() throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.enterExitEvent(
                with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
    }
}
