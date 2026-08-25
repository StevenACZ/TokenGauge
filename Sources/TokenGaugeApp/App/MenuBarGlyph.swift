import AppKit

@MainActor
enum MenuBarGlyph {
    private static let height: CGFloat = 16
    private static let barWidths: [CGFloat] = [2.5, 2.5, 2.5]
    private static let barHeights: [CGFloat] = [5, 8, 11]
    private static let barGap: CGFloat = 1.5
    private static let glyphGap: CGFloat = 3.5

    static func image(remaining: Double?) -> NSImage {
        let text = remaining.map { "\(Int($0.rounded()))%" } ?? "--"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let glyphWidth = barWidths.reduce(0, +) + barGap * CGFloat(barWidths.count - 1)
        let width = (glyphWidth + glyphGap + textSize.width).rounded(.up)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let baseline = ((height - barHeights.max()!) / 2).rounded()
            var x: CGFloat = 0
            for (index, barWidth) in barWidths.enumerated() {
                let rect = NSRect(x: x, y: baseline, width: barWidth, height: barHeights[index])
                NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                x += barWidth + barGap
            }
            let textOrigin = NSPoint(
                x: glyphWidth + glyphGap,
                y: ((height - textSize.height) / 2).rounded()
            )
            (text as NSString).draw(at: textOrigin, withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "app.name".localized
        return image
    }

    private static var font: NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: 11) ?? base
    }
}
