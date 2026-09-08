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

    init(
        providers: [UsageProvider], state: (UsageProvider) -> ProviderViewState,
        appearance: NSAppearance
    ) {
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: Theme.Layout.menuBarFontSize, weight: .semibold)
        for (index, segment) in segments.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: segment.color, .font: font]
            if index > 0 {
                title.append(NSAttributedString(string: "  ", attributes: attributes))
                let attachment = NSTextAttachment()
                attachment.image = ProviderLogoAssets.menuBarImage(
                    for: segment.provider, size: Theme.Layout.menuBarIconSize)
                attachment.bounds = NSRect(
                    x: 0, y: (font.capHeight - Theme.Layout.menuBarIconSize) / 2,
                    width: Theme.Layout.menuBarIconSize, height: Theme.Layout.menuBarIconSize)
                title.append(NSAttributedString(attachment: attachment))
            }
            title.append(NSAttributedString(string: " \(segment.text)", attributes: attributes))
        }
        return title
    }
}
