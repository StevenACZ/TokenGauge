import CoreGraphics
import XCTest

@testable import TokenGaugeApp

final class QuotaRingLayoutTests: XCTestCase {
    private let cell = Theme.Layout.quotaRingCellWidth
    private let spacing = Theme.Layout.quotaRingSpacing

    func testOneWindowAlwaysChoosesTheSingleRing() {
        for width: CGFloat in [0, 90, 146, 170, 310, 560] {
            XCTAssertEqual(QuotaRingLayout.choose(availableWidth: width, windows: 1), .single, "width \(width)")
        }
    }

    func testGridIsChosenOnlyWhenEveryCellReachesTheMinimumCellWidth() {
        for windows in 2...5 {
            let exact = QuotaRingLayout.minimumGridWidth(windows: windows)
            XCTAssertEqual(exact, cell * CGFloat(windows) + spacing * CGFloat(windows - 1), "windows \(windows)")
            XCTAssertEqual(
                QuotaRingLayout.choose(availableWidth: exact, windows: windows), .grid(columns: windows),
                "windows \(windows)")
            XCTAssertEqual(
                QuotaRingLayout.choose(availableWidth: exact + 40, windows: windows), .grid(columns: windows),
                "windows \(windows)")
            XCTAssertEqual(
                QuotaRingLayout.choose(availableWidth: exact - 1, windows: windows), .rows, "windows \(windows)")
            XCTAssertEqual(QuotaRingLayout.choose(availableWidth: 0, windows: windows), .rows, "windows \(windows)")
        }
    }

    func testPanelWidthsMapToTheExpectedModes() {
        let individual =
            Theme.Layout.ringPanelWidth - Theme.Layout.panelPadding * 2 - Theme.Layout.cardPadding * 2
        let unified = Theme.Layout.ringUnifiedWidth - Theme.Layout.panelPadding * 2 - Theme.Layout.quotaRingSpacing
        let narrowCard = Theme.Layout.minimumRingCardWidth - Theme.Layout.cardPadding * 2
        let wideCard = unified - Theme.Layout.minimumRingCardWidth - Theme.Layout.cardPadding * 2
        let halfCard = unified / 2 - Theme.Layout.cardPadding * 2
        let matrix: [(CGFloat, Int, QuotaRingLayout.Mode)] = [
            (individual, 1, .single),
            (individual, 2, .grid(columns: 2)),
            (individual, 3, .rows),
            (narrowCard, 1, .single),
            (narrowCard, 2, .rows),
            (halfCard, 2, .grid(columns: 2)),
            (wideCard, 3, .grid(columns: 3)),
            (wideCard, 2, .grid(columns: 2)),
        ]
        for (width, windows, mode) in matrix {
            XCTAssertEqual(
                QuotaRingLayout.choose(availableWidth: width, windows: windows), mode, "\(width) / \(windows)")
        }
    }

    func testColumnsNeverExceedTheWindowCountAndStayAtLeastOne() {
        XCTAssertEqual(QuotaRingLayout.columns(availableWidth: 600, windows: 2), 2)
        XCTAssertEqual(
            QuotaRingLayout.columns(availableWidth: QuotaRingLayout.minimumGridWidth(windows: 3), windows: 3), 3)
        XCTAssertEqual(QuotaRingLayout.columns(availableWidth: cell * 3, windows: 3), 2)
        XCTAssertEqual(QuotaRingLayout.columns(availableWidth: cell * 2, windows: 3), 1)
        XCTAssertEqual(QuotaRingLayout.columns(availableWidth: 0, windows: 3), 1)
    }

    func testTheGridThresholdIsTheCellFormulaSharedWithTheGridLayout() {
        for windows in 2...4 {
            let minimum = QuotaRingLayout.minimumGridWidth(windows: windows)
            XCTAssertEqual(
                QuotaRingLayout.cellWidth(availableWidth: minimum, columns: windows), cell, accuracy: 0.001,
                "windows \(windows)")
            XCTAssertEqual(
                QuotaRingLayout.choose(availableWidth: minimum, windows: windows), .grid(columns: windows),
                "windows \(windows)")
            XCTAssertEqual(
                QuotaRingLayout.choose(availableWidth: minimum - 1, windows: windows), .rows, "windows \(windows)")
        }
    }

    func testSingleCodexAndThreeClaudeWindowsFitACompleteGrid() {
        let width = QuotaRingLayout.unifiedPanelWidth(codexCells: 1, claudeCells: 3)
        let claude =
            width - Theme.Layout.panelPadding * 2 - spacing
            - Theme.Layout.minimumRingCardWidth - Theme.Layout.cardPadding * 2
        XCTAssertEqual(QuotaRingLayout.choose(availableWidth: claude, windows: 3), .grid(columns: 3))
    }

    func testUnifiedPanelWidthStaysWithinItsBounds() {
        XCTAssertEqual(
            QuotaRingLayout.unifiedPanelWidth(codexCells: 1, claudeCells: 1), Theme.Layout.minimumRingUnifiedWidth)
        XCTAssertEqual(
            QuotaRingLayout.unifiedPanelWidth(codexCells: 3, claudeCells: 3), Theme.Layout.ringUnifiedWidth)
        let wideCard = QuotaRingLayout.minimumGridWidth(windows: 2) + Theme.Layout.cardPadding * 2
        let chrome: CGFloat = Theme.Layout.panelPadding * 2 + spacing
        XCTAssertEqual(
            QuotaRingLayout.unifiedPanelWidth(codexCells: 1, claudeCells: 2),
            Theme.Layout.minimumRingCardWidth + wideCard + chrome)
    }
}
