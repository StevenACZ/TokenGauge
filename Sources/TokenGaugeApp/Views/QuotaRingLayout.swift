import SwiftUI

enum QuotaRingLayout {
    enum Mode: Equatable {
        case single
        case grid(columns: Int)
        case rows
    }

    static func choose(availableWidth: CGFloat, windows: Int) -> Mode {
        guard windows > 1 else { return .single }
        guard cellWidth(availableWidth: availableWidth, columns: windows) >= Theme.Layout.quotaRingCellWidth else {
            return .rows
        }
        return .grid(columns: windows)
    }

    static func cellWidth(availableWidth: CGFloat, columns: Int) -> CGFloat {
        let columns = max(1, columns)
        return (availableWidth - CGFloat(columns - 1) * Theme.Layout.quotaRingSpacing) / CGFloat(columns)
    }

    static func minimumGridWidth(windows: Int) -> CGFloat {
        let columns = max(1, windows)
        return CGFloat(columns) * Theme.Layout.quotaRingCellWidth
            + CGFloat(columns - 1) * Theme.Layout.quotaRingSpacing
    }

    static func minimumCardWidth(cells: Int) -> CGFloat {
        max(
            Theme.Layout.minimumRingCardWidth,
            minimumGridWidth(windows: min(max(cells, 1), 3)) + Theme.Layout.cardPadding * 2)
    }

    static func singlePanelWidth(cells: Int) -> CGFloat {
        max(Theme.Layout.ringPanelWidth, minimumCardWidth(cells: cells) + Theme.Layout.panelPadding * 2)
    }

    static func unifiedPanelWidth(codexCells: Int, claudeCells: Int) -> CGFloat {
        let content =
            minimumCardWidth(cells: codexCells) + minimumCardWidth(cells: claudeCells)
            + Theme.Layout.panelPadding * 2 + Theme.Layout.quotaRingSpacing
        return min(max(content, Theme.Layout.minimumRingUnifiedWidth), Theme.Layout.ringUnifiedWidth)
    }

    static func columns(availableWidth: CGFloat, windows: Int) -> Int {
        var columns = max(1, windows)
        while columns > 1,
            cellWidth(availableWidth: availableWidth, columns: columns) < Theme.Layout.quotaRingCellWidth
        {
            columns -= 1
        }
        return columns
    }
}

struct QuotaRingMetrics {
    let diameter: CGFloat
    let lineWidth: CGFloat
    let percentageSize: CGFloat
    let contentPadding: CGFloat
    let showsLabel: Bool

    static let single = QuotaRingMetrics(
        diameter: Theme.Layout.quotaRingSingleDiameter, lineWidth: Theme.Layout.quotaRingSingleLineWidth,
        percentageSize: Theme.Layout.quotaRingSinglePercentageSize, contentPadding: 5, showsLabel: true)
    static let grid = QuotaRingMetrics(
        diameter: Theme.Layout.quotaRingDiameter, lineWidth: Theme.Layout.quotaRingLineWidth,
        percentageSize: Theme.Layout.quotaRingPercentageSize, contentPadding: 5, showsLabel: true)
    static let row = QuotaRingMetrics(
        diameter: Theme.Layout.quotaRingRowDiameter, lineWidth: Theme.Layout.quotaRingRowLineWidth,
        percentageSize: Theme.Layout.quotaRingRowPercentageSize, contentPadding: 2, showsLabel: false)
}
