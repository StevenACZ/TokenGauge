import SwiftUI

struct SegmentChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

struct SegmentFill: View {
    let selected: Bool
    let hovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(selected ? 0.11 : hovered ? 0.05 : 0))
            .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1.5, y: 0.5)
    }
}

struct HistoryModeControl: View {
    @Binding var mode: HistoryMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    @State private var hovered: HistoryMode?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryMode.allCases) { item in
                let selected = item == mode
                Button {
                    guard mode != item else { return }
                    withAnimation(animateChanges && !reduceMotion ? .easeOut(duration: 0.16) : nil) { mode = item }
                } label: {
                    Text(item.titleKey.localized)
                        .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: Theme.Layout.historyModeSegmentHeight)
                        .background(SegmentFill(selected: selected, hovered: hovered == item))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? .primary : .secondary)
                .onHover { inside in
                    if inside { hovered = item } else if hovered == item { hovered = nil }
                }
                .accessibilityIdentifier("TokenGauge.historyMode.\(item.rawValue)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .modifier(SegmentChrome())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TokenGauge.historyMode.control")
        .accessibilityLabel("history.view".localized)
    }
}

struct HistoryPeriodControl: View {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void
    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", index: 0, enabled: canGoBack, key: "history.previous", action: onPrevious)
            divider
            Button(action: onToday) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8)
                    .frame(height: Theme.Layout.historyModeSegmentHeight)
                    .background(SegmentFill(selected: false, hovered: hovered == 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? 1 : (hovered == 1 ? nil : hovered) }
            .help("history.return_today".localized)
            divider
            chevron("chevron.right", index: 2, enabled: canGoForward, key: "history.next", action: onNext)
        }
        .modifier(SegmentChrome())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TokenGauge.historyPeriod.control")
        .accessibilityLabel("history.period".localized)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 11)
    }

    private func chevron(_ symbol: String, index: Int, enabled: Bool, key: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 19, height: Theme.Layout.historyModeSegmentHeight)
                .background(SegmentFill(selected: false, hovered: enabled && hovered == index))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .secondary : .quaternary)
        .disabled(!enabled)
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .help(key.localized)
        .accessibilityLabel(key.localized)
    }
}
