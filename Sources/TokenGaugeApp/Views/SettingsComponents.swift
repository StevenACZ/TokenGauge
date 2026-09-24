import SwiftUI
import TokenGaugeCore

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct SettingsToggleRow: View {
    let title: String
    let symbol: String
    var help: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let help { InfoTip(text: help) }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .frame(minHeight: 26)
    }
}

struct InfoTip: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}

struct ChoiceTile<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()
                    .frame(maxWidth: .infinity, minHeight: 30)
                Text(title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.07 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct QuotaChip: View {
    let title: String
    var detail: String?
    var provider: UsageProvider?
    let tint: Color
    let selected: Bool
    var automatic = false
    var interactive = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let provider { ProviderLogo(provider: provider, size: 14) }
                Text(title).font(.callout.weight(.semibold))
                if let detail {
                    Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if selected, interactive, provider == nil {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(fill))
            .overlay(stroke)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(interactive)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var fill: Color {
        if selected { return tint.opacity(0.2) }
        return Color.primary.opacity(hovering && interactive ? 0.08 : 0.035)
    }

    @ViewBuilder
    private var stroke: some View {
        if selected {
            Capsule().strokeBorder(tint.opacity(0.9), lineWidth: 1.2)
        } else if automatic {
            Capsule().strokeBorder(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        } else {
            Capsule().strokeBorder(Color.primary.opacity(0.1))
        }
    }
}

struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}
