import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class UsageFormattersTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var now = Date()

    override func setUp() async throws {
        try await super.setUp()
        let anchor = Date(timeIntervalSince1970: 1_787_000_400)
        now = calendar.startOfDay(for: anchor).addingTimeInterval(9 * 3_600)
        LocalizationManager.shared.language = .spanish
    }

    func testUnderAnHourShowsMinutesAndTheClockTime() {
        let reset = now.addingTimeInterval(43 * 60)

        let text = UsageFormatters.reset(reset, now: now, calendar: calendar)

        XCTAssertTrue(text.contains("43"), text)
        XCTAssertTrue(text.contains(clock(reset)), text)
    }

    func testSameDayShowsHoursAndTheClockTime() {
        let reset = now.addingTimeInterval(5 * 3_600)

        let text = UsageFormatters.reset(reset, now: now, calendar: calendar)

        XCTAssertTrue(text.contains(clock(reset)), text)
        XCTAssertFalse(text.contains("mañana"), text)
    }

    func testNextCalendarDayShowsTomorrowAndTheClockTime() {
        let reset = day(offset: 1).addingTimeInterval(9 * 3_600 + 15 * 60)

        let text = UsageFormatters.reset(reset, now: now, calendar: calendar)

        XCTAssertTrue(text.contains("mañana"), text)
        XCTAssertTrue(text.contains(clock(reset)), text)
    }

    func testTwoOrMoreDaysAwayShowsOnlyDays() {
        let reset = day(offset: 3).addingTimeInterval(9 * 3_600)

        let text = UsageFormatters.reset(reset, now: now, calendar: calendar)

        XCTAssertTrue(text.contains("3"), text)
        XCTAssertFalse(text.contains(clock(reset)), text)
        XCTAssertFalse(text.contains("mañana"), text)
    }

    func testFarResetsCountRealDaysNotMidnightCrossings() {
        let lateNow = calendar.startOfDay(for: now).addingTimeInterval(22 * 3_600)
        let reset = day(offset: 3).addingTimeInterval(6 * 3_600)

        let text = UsageFormatters.reset(reset, now: lateNow, calendar: calendar)

        XCTAssertTrue(text.contains("2"), text)
        XCTAssertFalse(text.contains("3"), text)
    }

    func testExpiredAndMissingResetsKeepTheirOwnPhrases() {
        XCTAssertEqual(UsageFormatters.reset(nil, now: now, calendar: calendar), "reset.unknown".localized)
        XCTAssertEqual(
            UsageFormatters.reset(now.addingTimeInterval(-60), now: now, calendar: calendar),
            "reset.pending".localized
        )
    }

    func testServerReserveIdentifierHasItsOwnLabelAndExplanationInBothLanguages() {
        let reserve = QuotaWindow(
            id: "base_model_inference.primary", usedPercentage: 0, resetsAt: nil,
            durationMinutes: 10_080, displayName: "gpt-reserve")
        for language in [AppLanguage.spanish, .english] {
            LocalizationManager.shared.language = language
            XCTAssertEqual(UsageFormatters.windowName(reserve), "window.reserve_weekly".localized)
            XCTAssertTrue(UsageFormatters.windowName(reserve).contains("Luna"))
            XCTAssertTrue(UsageFormatters.windowHelp(reserve).contains("Luna"))
            let general = QuotaWindow(
                id: "codex.primary", usedPercentage: 92, resetsAt: nil,
                durationMinutes: 10_080, displayName: nil)
            XCTAssertEqual(UsageFormatters.windowName(general), "window.general_weekly".localized)
        }
    }

    private func day(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
