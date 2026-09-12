import SwiftUI

enum Theme {
    static let claude = Color(red: 0.85, green: 0.44, blue: 0.29)
    static let codex = Color(red: 0.33, green: 0.47, blue: 0.96)

    enum Layout {
        static let menuBarIconSize: CGFloat = 17
        static let menuBarFontSize: CGFloat = 13.5
        static let menuRingGap: CGFloat = 8
        static let panelWidth: CGFloat = 340
        static let unifiedPanelWidth: CGFloat = 560
        static let providerMaxHeight: CGFloat = 182
        static let compactProviderMaxHeight: CGFloat = 230
        static let ringProviderMaxHeight: CGFloat = 250
        static let compactPanelWidth: CGFloat = 320
        static let compactUnifiedWidth: CGFloat = 360
        static let ringPanelWidth: CGFloat = 360
        static let ringUnifiedWidth: CGFloat = 520
        static let activityChartHeight: CGFloat = 64
        static let minimumRingUnifiedWidth: CGFloat = 440
        static let quotaRingCellWidth: CGFloat = 80
        static let quotaRingSpacing: CGFloat = 10
        static let minimumRingCardWidth: CGFloat = 155
        static let cardPadding: CGFloat = 12
        static let quotaRingDiameter: CGFloat = 68
        static let quotaRingLineWidth: CGFloat = 5
        static let panelPadding: CGFloat = 13
        static let panelBottomPadding: CGFloat = 14
        static let cardRadius: CGFloat = 11
        static let rowRadius: CGFloat = 7
        static let barHeight: CGFloat = 5
        static let sectionSpacing: CGFloat = 8
        static let cardFill = Color.primary.opacity(0.04)
        static let cardStroke = Color.primary.opacity(0.07)
    }

    enum Motion {
        static let content = Animation.spring(response: 0.28, dampingFraction: 0.86)
        static let value = Animation.easeOut(duration: 0.24)
    }

    static func severity(remaining: Double) -> Color? {
        if remaining < 12 { return .red }
        if remaining < 30 { return .orange }
        return nil
    }
}

private struct CardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                .fill(Theme.Layout.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                        .strokeBorder(Theme.Layout.cardStroke, lineWidth: 1)
                )
        )
    }
}

extension View {
    func providerCard() -> some View {
        modifier(CardChrome())
    }
}

struct GaugeBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.09))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.7), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: filledWidth(in: geometry.size.width))
            }
        }
        .frame(height: Theme.Layout.barHeight)
        .animation(animateChanges && !reduceMotion ? Theme.Motion.value : nil, value: fraction)
    }

    private func filledWidth(in total: CGFloat) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return 0 }
        return max(total * clamped, Theme.Layout.barHeight)
    }
}

enum MenuBarSize: String, CaseIterable, Identifiable {
    case large
    case medium
    case small

    var id: String { rawValue }
    var titleKey: String { "settings.menu_bar_size." + rawValue }

    var iconSize: CGFloat {
        switch self {
        case .large: return Theme.Layout.menuBarIconSize
        case .medium: return 15.5
        case .small: return 13.5
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .large: return Theme.Layout.menuBarFontSize
        case .medium: return 12.5
        case .small: return 11
        }
    }
}
