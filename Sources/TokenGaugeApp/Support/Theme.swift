import SwiftUI

enum Theme {
    static let claude = Color(red: 0.85, green: 0.44, blue: 0.29)
    static let codex = Color(red: 0.33, green: 0.47, blue: 0.96)

    enum Layout {
        static let menuBarIconSize: CGFloat = 18
        static let menuBarFontSize: CGFloat = 14
        static let panelWidth: CGFloat = 300
        static let providerMaxHeight: CGFloat = 210
        static let panelPadding: CGFloat = 13
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
        .animation(Theme.Motion.value, value: fraction)
    }

    private func filledWidth(in total: CGFloat) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return 0 }
        return max(total * clamped, Theme.Layout.barHeight)
    }
}
