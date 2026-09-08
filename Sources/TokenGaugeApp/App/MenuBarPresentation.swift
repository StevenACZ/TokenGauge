import AppKit
import TokenGaugeCore

@MainActor
struct MenuBarPresentation: Equatable {
    struct Segment: Equatable {
        let provider: UsageProvider
        let text: String
        let color: NSColor
        let description: String
    }

    let segments: [Segment]
    let size: MenuBarSize

    init(
        providers: [UsageProvider], state: (UsageProvider) -> ProviderViewState,
        appearance: NSAppearance, size: MenuBarSize = .large
    ) {
        self.size = size
        segments = providers.map { provider in
            let window = ProviderStateResolver.menuBarWindow(state: state(provider))
            let remaining = window?.remainingPercentage
            let text = remaining.map { "\(Int($0.rounded()))%" } ?? "--"
            var color: NSColor = .labelColor
            switch remaining {
            case .some(let value) where value < 12: color = .systemRed
            case .some(let value) where value < 30: color = .systemOrange
            default: break
            }
            appearance.performAsCurrentDrawingAppearance {
                color = color.usingColorSpace(.sRGB) ?? color
            }
            let name = "provider.\(provider.rawValue)".localized
            let description =
                window.map { "\(name) · \(UsageFormatters.windowName($0)) · \(text)" }
                ?? "\(name) · \("status.unavailable".localized)"
            return Segment(provider: provider, text: text, color: color, description: description)
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
            title.append(NSAttributedString(string: " \(segment.text)", attributes: attributes))
        }
        return title
    }
}
