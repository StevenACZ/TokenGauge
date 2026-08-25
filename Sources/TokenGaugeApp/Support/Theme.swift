import SwiftUI

enum Theme {
    static let claude = Color(red: 0.84, green: 0.38, blue: 0.27)
    static let codex = Color(red: 0.27, green: 0.43, blue: 0.96)

    enum Layout {
        static let panelWidth: CGFloat = 410
        static let cardRadius: CGFloat = 16
        static let rowRadius: CGFloat = 10
        static let cardFill = Color.primary.opacity(0.045)
        static let cardStroke = Color.primary.opacity(0.085)
    }

    enum Motion {
        static let content = Animation.spring(response: 0.28, dampingFraction: 0.86)
        static let value = Animation.easeOut(duration: 0.2)
    }
}

private struct CardChrome: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                .fill(Theme.Layout.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

extension View {
    func providerCard(tint: Color) -> some View {
        modifier(CardChrome(tint: tint))
    }
}
