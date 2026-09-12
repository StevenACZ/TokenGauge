import SwiftUI

struct QuotaRingGrid: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cells = min(max(subviews.count, 1), 3)
        let idealWidth =
            CGFloat(cells) * Theme.Layout.quotaRingCellWidth
            + CGFloat(cells - 1) * Theme.Layout.quotaRingSpacing
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? idealWidth
        return geometry(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = geometry(width: bounds.width, subviews: subviews)
        for (index, frame) in layout.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func geometry(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        guard !subviews.isEmpty else { return (.zero, []) }
        let spacing = Theme.Layout.quotaRingSpacing
        let columns = min(subviews.count, max(1, Int((width + spacing) / (Theme.Layout.quotaRingCellWidth + spacing))))
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let count = min(columns, subviews.count - start)
            let cellWidth = max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
            let rowHeight =
                (start..<(start + count)).map {
                    subviews[$0].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
                }.max() ?? 0
            for index in 0..<count {
                frames.append(
                    CGRect(x: CGFloat(index) * (cellWidth + spacing), y: y, width: cellWidth, height: rowHeight))
            }
            y += rowHeight + spacing
        }
        return (CGSize(width: width, height: y - spacing), frames)
    }
}
