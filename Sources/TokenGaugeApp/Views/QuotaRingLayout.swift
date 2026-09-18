import SwiftUI

enum QuotaRingLayout {
    enum Mode: Equatable {
        case single
        case grid(columns: Int)
        case rows
    }

    static func choose(availableWidth: CGFloat, windows: Int) -> Mode {
        guard windows > 1 else { return .single }
        guard availableWidth / CGFloat(windows) >= Theme.Layout.quotaRingCellWidth else { return .rows }
        return .grid(columns: windows)
    }

    static func columns(availableWidth: CGFloat, windows: Int) -> Int {
        max(1, min(windows, Int(availableWidth / Theme.Layout.quotaRingCellWidth)))
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

struct QuotaRingModeLayout: Layout {
    let windows: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width =
            proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
            ?? subviews[0].sizeThatFits(.unspecified).width
        let height = subviews[index(for: width)].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let chosen = index(for: bounds.width)
        for (offset, subview) in subviews.enumerated() {
            let visible = offset == chosen
            subview.place(
                at: visible ? CGPoint(x: bounds.minX, y: bounds.minY) : CGPoint(x: bounds.maxX, y: bounds.maxY),
                anchor: .topLeading,
                proposal: visible ? ProposedViewSize(width: bounds.width, height: bounds.height) : .zero)
        }
    }

    private func index(for width: CGFloat) -> Int {
        QuotaRingLayout.choose(availableWidth: width, windows: windows) == .rows ? 1 : 0
    }
}

extension View {
    func quotaRingVariant() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
    }
}
