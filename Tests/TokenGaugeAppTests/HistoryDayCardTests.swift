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

    func testTallCardFallsBelowAboveThenClampsToTheBottomOrTop() {
        let size = CGSize(width: HistoryDayCardPlacement.width, height: 160)
        let bounds = CGRect(x: -20, y: -300, width: 560, height: 700)
        func origin(_ y: CGFloat, in bounds: CGRect) -> CGPoint {
            HistoryDayCardPlacement.origin(
                anchor: CGRect(x: 280, y: y, width: 9, height: 9), cardSize: size, bounds: bounds)
        }
        XCTAssertEqual(origin(100, in: bounds).y, 109 + HistoryDayCardPlacement.spacing)
        XCTAssertEqual(origin(300, in: bounds).y, 300 - HistoryDayCardPlacement.spacing - size.height)
        let short = CGRect(x: 0, y: 0, width: 560, height: 200)
        XCTAssertEqual(origin(100, in: short).y, short.maxY - size.height)
        let tiny = CGRect(x: 0, y: 0, width: 560, height: 150)
        XCTAssertEqual(origin(60, in: tiny).y, tiny.minY)
        for (y, frame) in [(100, bounds), (300, bounds), (100, short)] {
            let point = origin(CGFloat(y), in: frame)
            XCTAssertTrue(frame.contains(CGRect(origin: point, size: size)), "\(y) in \(frame)")
        }
    }

    func testSharePercentagesUseLargestRemainderAndSumToOneHundred() {
        XCTAssertEqual(HistoryDayCardPlacement.percentages([505, 495]), [51, 49])
        XCTAssertEqual(HistoryDayCardPlacement.percentages([1, 1, 1]), [34, 33, 33])
        XCTAssertEqual(HistoryDayCardPlacement.percentages([800, 200]), [80, 20])
        XCTAssertEqual(HistoryDayCardPlacement.percentages([1, 999]), [0, 100])
        XCTAssertEqual(HistoryDayCardPlacement.percentages([7]), [100])
        XCTAssertEqual(HistoryDayCardPlacement.percentages([0, 0]), [0, 0])
        XCTAssertEqual(HistoryDayCardPlacement.percentages([]), [])
        for values in [[1, 2], [333, 333, 334], [2, 3, 5, 7, 11], [Int.max / 2, Int.max / 2]] {
            XCTAssertEqual(HistoryDayCardPlacement.percentages(values).reduce(0, +), 100, "\(values)")
        }
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
