import SwiftUI
import TokenGaugeCore

enum HistoryDayCardPlacement {
    static let width: CGFloat = 248
    static let spacing: CGFloat = 6

    static func origin(anchor: CGRect, cardSize: CGSize, bounds: CGRect) -> CGPoint {
        let below = anchor.maxY + spacing
        let above = anchor.minY - spacing - cardSize.height
        let y = below + cardSize.height <= bounds.maxY ? below : max(bounds.minY, above)
        let trailing = max(bounds.minX, bounds.maxX - cardSize.width)
        return CGPoint(x: min(max(bounds.minX, anchor.midX - cardSize.width / 2), trailing), y: y)
    }
}

struct HistoryDayCardView: View {
    let day: HistoryCalendarDay
    let providers: [UsageProvider]
    let isToday: Bool
    let isPinned: Bool
    let currentStreak: Int
    let longestStreak: Int
    let onClose: () -> Void

    private var locale: Locale { Locale(identifier: LocalizationManager.shared.language.rawValue) }
    private var rows: [UsageProvider] { providers.filter { (day.tokens(for: $0) ?? 0) > 0 } }
    private var total: Int { rows.compactMap { day.tokens(for: $0) }.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if rows.isEmpty {
                Text("history.no_activity".localized).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.self) { provider in
                        providerRow(provider)
                    }
                }
            }
            Divider()
            Text(
                "history.streak_current".localized(String(currentStreak)) + " · "
                    + "history.streak_longest".localized(String(longestStreak))
            )
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(width: HistoryDayCardPlacement.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius).fill(.regularMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius).stroke(Theme.Layout.cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)))
                .font(.system(size: 11, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if isToday {
                Text("history.today".localized)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 0)
            if isPinned {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .padding(4).background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain).accessibilityLabel("history.close".localized)
            }
        }
    }

    private func providerRow(_ provider: UsageProvider) -> some View {
        let tokens = day.tokens(for: provider) ?? 0
        let share = total > 0 ? Double(tokens) / Double(total) : 0
        let percentage = (share * 100).rounded().formatted(.number.locale(locale)) + " %"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ProviderLogo(provider: provider, size: 16)
                Text(name(provider)).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 6)
                Text(UsageFormatters.tokens(tokens)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                if rows.count > 1 {
                    Text(percentage).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                        .accessibilityLabel("history.share".localized(percentage))
                }
            }
            if rows.count > 1 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(color(provider)).frame(width: max(2, proxy.size.width * share))
                    }
                }
                .frame(height: Theme.Layout.barHeight)
            }
            let chips = models(provider)
            if !chips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(chips, id: \.self) { model in
                        Text(model).font(.system(size: 9)).lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(color(provider).opacity(0.12)))
                    }
                }
            }
        }
    }

    private func models(_ provider: UsageProvider) -> [String] {
        let rows = day.efforts.filter { $0.provider == provider }
        let totals = Dictionary(grouping: rows, by: \.model).mapValues { $0.map(\.tokens).reduce(0, +) }
        return totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3).map(\.key)
    }

    private func color(_ provider: UsageProvider) -> Color { provider == .claude ? Theme.claude : Theme.codex }
    private func name(_ provider: UsageProvider) -> String {
        (provider == .claude ? "provider.claude_short" : "provider.codex").localized
    }
}
