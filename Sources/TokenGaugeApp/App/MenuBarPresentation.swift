import AppKit
import TokenGaugeCore

@MainActor
struct MenuBarPresentation: Equatable {
    struct Segment: Equatable {
        let provider: UsageProvider
        let label: String?
        let text: String
        let color: NSColor
        let description: String
        let remainingPercentage: Double?
        let graphicColor: NSColor
    }

    let segments: [Segment]
    let size: MenuBarSize
    let style: QuotaMenuBarStyle
    let labelColor: NSColor

    init(
        providers: [UsageProvider], state: (UsageProvider) -> ProviderViewState,
        appearance: NSAppearance, size: MenuBarSize = .large, style: QuotaMenuBarStyle = .numbers,
        selection: [UsageProvider: Set<QuotaWindowKind>] = [:]
    ) {
        self.size = size
        self.style = style
        var labelColor = NSColor.secondaryLabelColor
        appearance.performAsCurrentDrawingAppearance {
            labelColor = labelColor.usingColorSpace(.sRGB) ?? labelColor
        }
        self.labelColor = labelColor
        segments = providers.flatMap { provider -> [Segment] in
            let windows = ProviderStateResolver.menuBarWindows(
                state: state(provider), selection: selection[provider] ?? [])
            guard !windows.isEmpty else {
                return [Self.segment(provider: provider, window: nil, appearance: appearance)]
            }
            return windows.map {
                Self.segment(
                    provider: provider, window: $0,
                    label: windows.count > 1 ? Self.shortLabel($0, provider: provider) : nil,
                    appearance: appearance)
            }
        }
    }

    private static func segment(
        provider: UsageProvider, window: QuotaWindow?, label: String? = nil, appearance: NSAppearance
    ) -> Segment {
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
            provider: provider, label: label, text: text, color: color, description: description,
            remainingPercentage: remaining, graphicColor: graphicColor)
    }

    static func shortLabel(_ window: QuotaWindow, provider: UsageProvider = .claude) -> String {
        switch QuotaWindowKind.of(window, provider: provider) {
        case .session: return "menu.label.session".localized
        case .weekly: return "menu.label.weekly".localized
        case .modelWeekly:
            let name = window.displayName?.split(separator: " ").first.map(String.init) ?? ""
            return name.isEmpty ? "menu.label.weekly".localized : String(name.prefix(6))
        case nil: return UsageFormatters.windowName(window)
        }
    }

    var accessibilityLabel: String {
        segments.map(\.description).joined(separator: "\n")
    }

    var groups: [[Segment]] {
        segments.reduce(into: [[Segment]]()) { groups, segment in
            if groups.last?.first?.provider == segment.provider {
                groups[groups.count - 1].append(segment)
            } else {
                groups.append([segment])
            }
        }
    }

    func attributedTitle() -> NSAttributedString {
        let title = NSMutableAttributedString(string: "")
        let font = NSFont.monospacedDigitSystemFont(ofSize: size.fontSize, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: (size.fontSize * 0.78).rounded(), weight: .semibold)
        for (index, group) in groups.enumerated() {
            let provider = group[0].provider
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: group[0].color, .font: font]
            if style == .rings {
                if index > 0 {
                    let gap = NSMutableAttributedString(string: " ", attributes: attributes)
                    gap.addAttribute(.kern, value: Theme.Layout.menuRingGap, range: NSRange(location: 0, length: 1))
                    title.append(gap)
                }
                if group.count > 1 {
                    appendLogo(provider, to: title, font: font)
                    title.append(NSAttributedString(string: " ", attributes: attributes))
                }
                let image =
                    quotaImage(for: group) ?? ProviderLogoAssets.menuBarImage(for: provider, size: size.iconSize)
                if let image {
                    append(image, to: title, font: font)
                } else {
                    title.append(
                        NSAttributedString(string: "provider.\(provider.rawValue)".localized, attributes: attributes))
                }
                if group.allSatisfy({ $0.remainingPercentage == nil }) {
                    title.append(NSAttributedString(string: " --", attributes: attributes))
                }
                continue
            }
            if index > 0 {
                let gap = NSMutableAttributedString(string: "  ", attributes: attributes)
                gap.addAttribute(.kern, value: 3, range: NSRange(location: 0, length: 1))
                title.append(gap)
                appendLogo(provider, to: title, font: font)
            }
            if style != .numbers, let image = quotaImage(for: group) {
                title.append(NSAttributedString(string: " ", attributes: attributes))
                append(image, to: title, font: font)
                continue
            }
            for (position, segment) in group.enumerated() {
                let segmentAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: segment.color, .font: font]
                let spacer = NSMutableAttributedString(string: " ", attributes: segmentAttributes)
                if position > 0 { spacer.addAttribute(.kern, value: 5, range: NSRange(location: 0, length: 1)) }
                title.append(spacer)
                if let label = segment.label {
                    title.append(
                        NSAttributedString(
                            string: label + "\u{2009}", attributes: [.foregroundColor: labelColor, .font: labelFont]))
                }
                title.append(NSAttributedString(string: segment.text, attributes: segmentAttributes))
            }
        }
        return title
    }

    private func appendLogo(_ provider: UsageProvider, to title: NSMutableAttributedString, font: NSFont) {
        let attachment = NSTextAttachment()
        attachment.image = ProviderLogoAssets.menuBarImage(for: provider, size: size.iconSize)
        attachment.bounds = NSRect(
            x: 0, y: (font.capHeight - size.iconSize) / 2, width: size.iconSize, height: size.iconSize)
        title.append(NSAttributedString(attachment: attachment))
    }

    private func append(_ image: NSImage, to title: NSMutableAttributedString, font: NSFont) {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0, y: (font.capHeight - image.size.height) / 2, width: image.size.width, height: image.size.height)
        title.append(NSAttributedString(attachment: attachment))
    }

    func renderedImage() -> NSImage {
        let title = attributedTitle()
        let logo =
            style == .rings
            ? nil : segments.first.flatMap { ProviderLogoAssets.menuBarImage(for: $0.provider, size: size.iconSize) }
        let titleSize = title.size()
        let logoWidth = logo == nil ? 0 : size.iconSize
        let height = max(22, ceil(titleSize.height))
        let imageSize = NSSize(width: max(ceil(logoWidth + titleSize.width), 1), height: height)
        let iconSize = size.iconSize
        return NSImage(size: imageSize, flipped: false) { _ in
            logo?.draw(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
            title.draw(at: NSPoint(x: logoWidth, y: (height - titleSize.height) / 2))
            return true
        }
    }

    func quotaImage(for segment: Segment) -> NSImage? {
        quotaImage(for: [segment])
    }

    func quotaImage(for group: [Segment]) -> NSImage? {
        let values = group.compactMap { segment in segment.remainingPercentage.map { (segment, $0) } }
        guard style != .numbers, !values.isEmpty else { return nil }
        let diameter = min(22, size.iconSize + 5)
        let imageSize =
            style == .bars
            ? NSSize(width: size.iconSize * 1.8, height: size.iconSize)
            : NSSize(width: diameter, height: diameter)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        if style == .bars {
            let gap: CGFloat = 1.5
            let count = CGFloat(values.count)
            let height =
                values.count == 1 ? size.iconSize * 0.42 : (imageSize.height - gap * (count - 1)) / count
            let stack = height * count + gap * (count - 1)
            for (index, (segment, remaining)) in values.enumerated() {
                let top = (imageSize.height + stack) / 2 - CGFloat(index) * (height + gap)
                drawBar(
                    NSRect(x: 0, y: top - height, width: imageSize.width, height: height), remaining: remaining,
                    segment: segment)
            }
        } else if values.count == 1, let (segment, remaining) = values.first {
            let lineWidth: CGFloat = 2
            drawRing(
                NSRect(origin: .zero, size: imageSize).insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                lineWidth: lineWidth, remaining: remaining, segment: segment)
            let logoSize = min(14, diameter - 6)
            let logo = ProviderLogoAssets.menuBarImage(for: segment.provider, size: logoSize)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: NSRect(origin: .zero, size: imageSize).insetBy(dx: 3, dy: 3)).addClip()
            logo?.draw(
                in: NSRect(
                    x: (diameter - logoSize) / 2, y: (diameter - logoSize) / 2, width: logoSize, height: logoSize))
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let lineWidth: CGFloat = values.count == 2 ? 2.5 : 2
            let gap: CGFloat = 1
            for (index, (segment, remaining)) in values.enumerated() {
                let inset = lineWidth / 2 + CGFloat(index) * (lineWidth + gap)
                drawRing(
                    NSRect(origin: .zero, size: imageSize).insetBy(dx: inset, dy: inset), lineWidth: lineWidth,
                    remaining: remaining, segment: segment)
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawBar(_ rect: NSRect, remaining: Double, segment: Segment) {
        let fraction = min(max(remaining / 100, 0), 1)
        let radius = rect.height / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        segment.color.withAlphaComponent(0.2).setFill()
        track.fill()
        guard fraction > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        segment.graphicColor.setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawRing(_ rect: NSRect, lineWidth: CGFloat, remaining: Double, segment: Segment) {
        let fraction = min(max(remaining / 100, 0), 1)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth
        segment.color.withAlphaComponent(0.2).setStroke()
        track.stroke()
        guard fraction > 0 else { return }
        segment.graphicColor.setStroke()
        if fraction == 1 {
            track.stroke()
            return
        }
        let arc = NSBezierPath()
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .butt
        arc.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
            startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        arc.stroke()
    }
}
