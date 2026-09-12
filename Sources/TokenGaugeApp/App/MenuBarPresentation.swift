import AppKit
import TokenGaugeCore

@MainActor
struct MenuBarPresentation: Equatable {
    struct Segment: Equatable {
        let provider: UsageProvider
        let text: String
        let color: NSColor
        let description: String
        let remainingPercentage: Double?
        let graphicColor: NSColor
    }

    let segments: [Segment]
    let size: MenuBarSize
    let style: QuotaMenuBarStyle

    init(
        providers: [UsageProvider], state: (UsageProvider) -> ProviderViewState,
        appearance: NSAppearance, size: MenuBarSize = .large, style: QuotaMenuBarStyle = .numbers,
        claudeSource: ClaudeMenuBarSource = .automatic
    ) {
        self.size = size
        self.style = style
        segments = providers.map { provider in
            let window = ProviderStateResolver.menuBarWindow(state: state(provider), claudeSource: claudeSource)
            let remaining = window?.remainingPercentage
            let text = remaining.map { "\(Int($0.rounded()))%" } ?? "--"
            var color: NSColor = .labelColor
            switch remaining {
            case .some(let value) where value < 12: color = .systemRed
            case .some(let value) where value < 30: color = .systemOrange
            default: break
            }
            var graphicColor: NSColor = provider == .codex ? .systemBlue : .systemOrange
            if let remaining, remaining < 12 { graphicColor = .systemRed }
            appearance.performAsCurrentDrawingAppearance {
                graphicColor = graphicColor.usingColorSpace(.sRGB) ?? graphicColor
                color = color.usingColorSpace(.sRGB) ?? color
            }
            let name = "provider.\(provider.rawValue)".localized
            let description =
                window.map { "\(name) · \(UsageFormatters.windowName($0)) · \(text)" }
                ?? "\(name) · \("status.unavailable".localized)"
            return Segment(
                provider: provider, text: text, color: color, description: description,
                remainingPercentage: remaining, graphicColor: graphicColor)
        }
    }

    var accessibilityLabel: String {
        segments.map(\.description).joined(separator: "\n")
    }

    func attributedTitle() -> NSAttributedString {
        let title = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedDigitSystemFont(ofSize: size.fontSize, weight: .semibold)
        for (index, segment) in segments.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: segment.color, .font: font]
            if style == .rings {
                if index > 0 {
                    let gap = NSMutableAttributedString(string: " ", attributes: attributes)
                    gap.addAttribute(.kern, value: Theme.Layout.menuRingGap, range: NSRange(location: 0, length: 1))
                    title.append(gap)
                }
                let image =
                    quotaImage(for: segment)
                    ?? ProviderLogoAssets.menuBarImage(for: segment.provider, size: size.iconSize)
                if let image {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attachment.bounds = NSRect(
                        x: 0, y: (font.capHeight - image.size.height) / 2,
                        width: image.size.width, height: image.size.height)
                    title.append(NSAttributedString(attachment: attachment))
                } else {
                    title.append(
                        NSAttributedString(
                            string: "provider.\(segment.provider.rawValue)".localized, attributes: attributes))
                }
                if segment.remainingPercentage == nil {
                    title.append(NSAttributedString(string: " --", attributes: attributes))
                }
                continue
            }
            if index > 0 {
                let gap = NSMutableAttributedString(string: "  ", attributes: attributes)
                gap.addAttribute(.kern, value: 3, range: NSRange(location: 0, length: 1))
                title.append(gap)
                let attachment = NSTextAttachment()
                attachment.image = ProviderLogoAssets.menuBarImage(
                    for: segment.provider, size: size.iconSize)
                attachment.bounds = NSRect(
                    x: 0, y: (font.capHeight - size.iconSize) / 2,
                    width: size.iconSize, height: size.iconSize)
                title.append(NSAttributedString(attachment: attachment))
            }
            if style != .numbers, let image = quotaImage(for: segment) {
                title.append(NSAttributedString(string: " ", attributes: attributes))
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(
                    x: 0, y: (font.capHeight - image.size.height) / 2,
                    width: image.size.width, height: image.size.height)
                title.append(NSAttributedString(attachment: attachment))
            } else {
                title.append(NSAttributedString(string: " \(segment.text)", attributes: attributes))
            }
        }
        return title
    }

    func quotaImage(for segment: Segment) -> NSImage? {
        guard style != .numbers, let remaining = segment.remainingPercentage else { return nil }
        let diameter = min(22, size.iconSize + 5)
        let imageSize =
            style == .bars
            ? NSSize(width: size.iconSize * 1.8, height: size.iconSize)
            : NSSize(width: diameter, height: diameter)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        let fraction = min(max(remaining / 100, 0), 1)
        let trackColor = segment.color.withAlphaComponent(0.2)
        if style == .bars {
            let height = size.iconSize * 0.42
            let rect = NSRect(x: 0, y: (imageSize.height - height) / 2, width: imageSize.width, height: height)
            let track = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
            trackColor.setFill()
            track.fill()
            if fraction > 0 {
                NSGraphicsContext.saveGraphicsState()
                track.addClip()
                segment.graphicColor.setFill()
                NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: height))
                    .fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        } else {
            let lineWidth: CGFloat = 2
            let rect = NSRect(origin: .zero, size: imageSize).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let track = NSBezierPath(ovalIn: rect)
            track.lineWidth = lineWidth
            trackColor.setStroke()
            track.stroke()
            if fraction > 0 {
                let arc = NSBezierPath()
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .butt
                arc.appendArc(
                    withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                    startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                segment.graphicColor.setStroke()
                if fraction == 1 { track.stroke() } else { arc.stroke() }
            }
            let logoSize = min(14, diameter - 6)
            let logo = ProviderLogoAssets.menuBarImage(for: segment.provider, size: logoSize)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: NSRect(origin: .zero, size: imageSize).insetBy(dx: 3, dy: 3)).addClip()
            logo?.draw(
                in: NSRect(
                    x: (diameter - logoSize) / 2, y: (diameter - logoSize) / 2, width: logoSize, height: logoSize))
            NSGraphicsContext.restoreGraphicsState()
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
