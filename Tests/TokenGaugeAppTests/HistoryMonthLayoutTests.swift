import Foundation
import XCTest

@testable import TokenGaugeApp

@MainActor
final class HistoryMonthLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 1
        return value
    }

    private func days(in year: Int) -> [HistoryCalendarDay] {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        return HistoryDashboardModel.makeDays(
            interval: DateInterval(start: start, end: end), tokens: [], efforts: [], calendar: calendar)
    }

    func testStaleAccessibilityIndicesDoNotCrashAfterChangingPeriods() {
        let layout = HistoryMonthLayout(days: [])
        XCTAssertEqual(layout.cellRect(-1), .zero)
        XCTAssertEqual(layout.cellRect(365), .zero)
    }

    func testLeapYearRetainsEveryDayInTwelveIndependentMonths() throws {
        let days = days(in: 2024)
        let layout = HistoryMonthLayout(days: days, calendar: calendar)
        XCTAssertEqual(layout.sections.count, 12)
        XCTAssertEqual(layout.sections.flatMap { Array($0.indices) }, Array(0..<366))
        let february = layout.sections[1]
        XCTAssertEqual(february.indices.count, 29)
        XCTAssertEqual(days[february.indices.last!].id, "2024-02-29")
        XCTAssertEqual(layout.gridWidth, try XCTUnwrap(layout.sections.last).originX + layout.sections.last!.width)
        XCTAssertTrue(layout.sections.allSatisfy { $0.width == Theme.Layout.historyMonthWidth })
    }

    func testMidweekBoundaryStartsANewBlockWithMondayPadding() {
        let days = days(in: 2024)
        let layout = HistoryMonthLayout(days: days, calendar: calendar)
        let january = layout.sections[0]
        let february = layout.sections[1]
        let lastJanuary = layout.cellRect(january.indices.last!)
        let firstFebruary = layout.cellRect(february.indices.lowerBound)
        XCTAssertEqual(february.leadingDays, 3)
        XCTAssertEqual(firstFebruary.minY, Theme.Layout.historyCalendarGridTop + 36)
        XCTAssertEqual(firstFebruary.minX, february.originX + 6)
        XCTAssertEqual(february.originX - january.originX - january.width, Theme.Layout.historyMonthGap)
        XCTAssertGreaterThan(firstFebruary.minX, lastJanuary.maxX)
        XCTAssertNil(layout.index(at: CGPoint(x: february.originX + 4.5, y: Theme.Layout.historyCalendarGridTop + 4.5)))
    }

    func testMonthGapsAndCellSpacingAreNotHittable() {
        let layout = HistoryMonthLayout(days: days(in: 2024), calendar: calendar)
        for section in layout.sections.dropLast() {
            for row in 0..<7 {
                let gap = CGPoint(
                    x: section.originX + section.width + 6,
                    y: Theme.Layout.historyCalendarGridTop + 4.5 + CGFloat(row) * 12)
                XCTAssertNil(layout.index(at: gap))
            }
        }
        let first = layout.cellRect(0)
        XCTAssertNil(layout.index(at: CGPoint(x: first.maxX + 1.5, y: first.midY)))
        XCTAssertNil(layout.index(at: CGPoint(x: first.midX, y: first.maxY + 1.5)))
        XCTAssertNil(layout.index(at: CGPoint(x: -1, y: 20)))
        XCTAssertNil(layout.index(at: CGPoint(x: layout.gridWidth + 1, y: 20)))
        XCTAssertNil(layout.index(at: CGPoint(x: 4.5, y: 10)))
    }

    func testEveryActualDayRoundTripsWithinSevenRows() {
        for year in [2023, 2024, 2026] {
            let days = days(in: year)
            let layout = HistoryMonthLayout(days: days, calendar: calendar)
            for index in days.indices {
                let rect = layout.cellRect(index)
                XCTAssertEqual(layout.index(at: CGPoint(x: rect.midX, y: rect.midY)), index)
                XCTAssertEqual(rect.width, 9)
                XCTAssertEqual(rect.height, 9)
                XCTAssertGreaterThanOrEqual(rect.minY, Theme.Layout.historyCalendarGridTop)
                XCTAssertLessThanOrEqual(rect.maxY, Theme.Layout.historyCalendarHeight - 6)
                XCTAssertEqual(
                    rect.minY,
                    Theme.Layout.historyCalendarGridTop + CGFloat(
                        (calendar.component(.weekday, from: days[index].date) + 5) % 7) * 12)
            }
        }
    }

    func testEmptyLayoutHasNoGeometryOrHitTargets() {
        let layout = HistoryMonthLayout(days: [], calendar: calendar)
        XCTAssertTrue(layout.sections.isEmpty)
        XCTAssertEqual(layout.gridWidth, 0)
        XCTAssertNil(layout.index(at: CGPoint(x: 0, y: 15)))
    }
}
