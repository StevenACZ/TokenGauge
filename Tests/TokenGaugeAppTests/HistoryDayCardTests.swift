import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class HistoryDayCardTests: XCTestCase {
    func testIntensityLevelsFollowTheQuantilesOfTheLoadedRange() {
        let thresholds = HistoryIntensity.thresholds(totals: [0, 10, 20, 30, 40, 50])
        XCTAssertEqual(thresholds, [10, 20, 30, 40])
        XCTAssertEqual(HistoryIntensity.level(total: 5, thresholds: thresholds), 0)
        XCTAssertEqual(HistoryIntensity.level(total: 15, thresholds: thresholds), 1)
        XCTAssertEqual(HistoryIntensity.level(total: 35, thresholds: thresholds), 3)
        XCTAssertEqual(HistoryIntensity.level(total: 50, thresholds: thresholds), 4)
        XCTAssertEqual(HistoryIntensity.opacity(total: 50, thresholds: thresholds), 1)
        XCTAssertEqual(HistoryIntensity.opacity(total: 1, thresholds: []), HistoryIntensity.opacities[0])
    }

    func testCardIsPlacedBelowThenAboveAndClampedToThePanel() {
        let bounds = CGRect(x: 0, y: 0, width: 560, height: 400)
        let size = CGSize(width: HistoryDayCardPlacement.width, height: 120)
        let below = HistoryDayCardPlacement.origin(
            anchor: CGRect(x: 280, y: 100, width: 9, height: 9), cardSize: size, bounds: bounds)
        XCTAssertEqual(below.y, 109 + HistoryDayCardPlacement.spacing)
        XCTAssertEqual(below.x, 284.5 - size.width / 2)
        let above = HistoryDayCardPlacement.origin(
            anchor: CGRect(x: 280, y: 330, width: 9, height: 9), cardSize: size, bounds: bounds)
        XCTAssertEqual(above.y, 330 - HistoryDayCardPlacement.spacing - size.height)
        let trailing = HistoryDayCardPlacement.origin(
            anchor: CGRect(x: 550, y: 100, width: 9, height: 9), cardSize: size, bounds: bounds)
        XCTAssertEqual(trailing.x, bounds.maxX - size.width)
        let leading = HistoryDayCardPlacement.origin(
            anchor: CGRect(x: 2, y: 100, width: 9, height: 9), cardSize: size, bounds: bounds)
        XCTAssertEqual(leading.x, bounds.minX)
    }

    func testCardRendersBothProvidersInEveryLanguage() {
        let language = LocalizationManager.shared.language
        defer { LocalizationManager.shared.language = language }
        for value in AppLanguage.allCases {
            LocalizationManager.shared.language = value
            let view = NSHostingView(
                rootView: HistoryDayCardView(
                    day: day, providers: [.codex, .claude], isToday: true, isPinned: true, currentStreak: 3,
                    longestStreak: 12, onClose: {}))
            XCTAssertEqual(view.fittingSize.width, HistoryDayCardPlacement.width)
            XCTAssertGreaterThan(view.fittingSize.height, 80)
        }
    }

    func testCardWithoutDataAnnouncesTheAbsenceOfActivity() {
        let empty = HistoryCalendarDay(
            id: "2026-09-16", date: Date(timeIntervalSince1970: 1_789_000_000), totals: [:], efforts: [])
        let view = NSHostingView(
            rootView: HistoryDayCardView(
                day: empty, providers: [.codex, .claude], isToday: false, isPinned: false, currentStreak: 0,
                longestStreak: 0, onClose: {}))
        XCTAssertEqual(view.fittingSize.width, HistoryDayCardPlacement.width)
        XCTAssertGreaterThan(view.fittingSize.height, 40)
    }

    private var day: HistoryCalendarDay {
        HistoryCalendarDay(
            id: "2026-09-17", date: Date(timeIntervalSince1970: 1_789_000_000),
            totals: [.codex: 800, .claude: 200],
            efforts: [
                HistoryEffortRow(
                    day: "2026-09-17", provider: .codex, model: "gpt-6-astra", effort: "medium", tokens: 800)
            ])
    }
}
