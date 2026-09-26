import SwiftUI

struct FlipCard<Front: View, Back: View>: View {
    let flipped: Bool
    let animated: Bool
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back
    @State private var angle: Double = 0
    @State private var target = false
    @State private var showsFront = true
    @State private var showsBack = false
    @State private var frontHeight: CGFloat = 0

    static var minimumBackHeight: CGFloat { 360 }

    var body: some View {
        ZStack(alignment: .top) {
            if showsFront {
                front()
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: { height in
                        if !showsBack { frontHeight = height }
                    }
                    .modifier(FlipFace(angle: angle, isBack: false))
            }
            if showsBack {
                back()
                    .frame(height: max(frontHeight, Self.minimumBackHeight))
                    .modifier(FlipFace(angle: angle, isBack: true))
            }
        }
        .onChange(of: flipped) { _, newValue in turn(to: newValue) }
    }

    private func turn(to value: Bool) {
        target = value
        showsFront = true
        showsBack = true
        let destination: Double = value ? 180 : 0
        guard animated else {
            angle = destination
            settle(value)
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.84), completionCriteria: .logicallyComplete) {
            angle = destination
        } completion: {
            settle(value)
        }
    }

    private func settle(_ value: Bool) {
        guard value == target else { return }
        showsFront = !value
        showsBack = value
    }
}

private struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let visible = isBack ? angle > 90 : angle <= 90
        let depth = 1 - 0.07 * sin(angle * .pi / 180)
        content
            .rotation3DEffect(.degrees(isBack ? angle - 180 : angle), axis: (0, 1, 0), perspective: 0.32)
            .scaleEffect(depth)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible && (angle == 0 || angle == 180))
            .accessibilityHidden(!visible)
    }
}
