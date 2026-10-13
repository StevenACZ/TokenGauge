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

    func testUnderAnHourShowsOnlyMinutes() {
        XCTAssertEqual(UsageFormatters.reset(now.addingTimeInterval(43 * 60 + 50), now: now), "Reinicia en 43 min")
        XCTAssertEqual(UsageFormatters.reset(now.addingTimeInterval(30), now: now), "Reinicia en 1 min")
    }

    func testUnderADayShowsHoursAndMinutesWithoutTheClock() {
        XCTAssertEqual(
            UsageFormatters.reset(now.addingTimeInterval(2 * 3_600 + 40 * 60), now: now), "Reinicia en 2 h 40 min")
        XCTAssertEqual(UsageFormatters.reset(now.addingTimeInterval(5 * 3_600 + 20), now: now), "Reinicia en 5 h")
    }

    func testDaysAwayShowDaysAndHours() {
        let text = UsageFormatters.reset(now.addingTimeInterval(3 * 86_400 + 4 * 3_600 + 59 * 60), now: now)
        XCTAssertEqual(text, "Reinicia en 3 d 4 h")
        XCTAssertEqual(UsageFormatters.reset(now.addingTimeInterval(86_400 + 15 * 60), now: now), "Reinicia en 1 d")
        LocalizationManager.shared.language = .english
        defer { LocalizationManager.shared.language = .spanish }
        XCTAssertEqual(UsageFormatters.reset(now.addingTimeInterval(80 * 60), now: now), "Resets in 1h 20m")
    }

    func testExpiredAndMissingResetsKeepTheirOwnPhrases() {
        XCTAssertEqual(UsageFormatters.reset(nil, now: now), "reset.unknown".localized)
        XCTAssertEqual(UsageFormatters.reset(now.addingTimeInterval(-60), now: now), "reset.pending".localized)
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
}
