import SwiftUI
import TokenGaugeCore

private struct ActivityDay: Identifiable {
    let id: String
    let date: Date
    let claudeTokens: Int
    let codexTokens: Int
}

struct ActivityChartView: View {
    private let days: [ActivityDay]
    private let maximumTokens: Int
    @State private var selectedKey: String

    init(claude: ProviderUsageSnapshot?, codex: ProviderUsageSnapshot?) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let claudeTotals = Dictionary((claude?.dailyUsage ?? []).map { ($0.day, $0.tokens) }, uniquingKeysWith: max)
        let codexTotals = Dictionary((codex?.dailyUsage ?? []).map { ($0.day, $0.tokens) }, uniquingKeysWith: max)
        let days = (0..<7).compactMap { offset -> ActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return nil }
            let key = Self.dayFormatter.string(from: date)
            return ActivityDay(
                id: key, date: date, claudeTokens: claudeTotals[key] ?? 0, codexTokens: codexTotals[key] ?? 0)
        }
        self.days = days
        maximumTokens = max(days.map { max($0.claudeTokens, $0.codexTokens) }.max() ?? 0, 1)
        _selectedKey = State(initialValue: Self.dayFormatter.string(from: today))
    }

    var body: some View {
        let selectedDay = days.first { $0.id == selectedKey } ?? days.last
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("activity.title".localized)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                legend
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    Button {
                        select(day)
                    } label: {
                        VStack(spacing: 5) {
                            HStack(alignment: .bottom, spacing: 3) {
                                bar(tokens: day.claudeTokens, tint: Theme.claude)
                                bar(tokens: day.codexTokens, tint: Theme.codex)
                            }
                            .frame(height: 44, alignment: .bottom)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                            }
                            Text(day.date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                                .font(.system(size: 9, weight: day.id == selectedDay?.id ? .bold : .regular))
                                .foregroundStyle(day.id == selectedDay?.id ? Color.primary : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { select(day) }
                    }
                    .accessibilityLabel(summary(for: day))
                    .accessibilityAddTraits(day.id == selectedDay?.id ? [.isSelected] : [])
                }
            }

            Text(selectedDay.map(summary) ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var locale: Locale {
        Locale(identifier: LocalizationManager.shared.language.rawValue)
    }

    private func select(_ day: ActivityDay) {
        guard selectedKey != day.id else { return }
        selectedKey = day.id
    }

    private func bar(tokens: Int, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(tint)
            .frame(width: 9, height: 44 * Double(tokens) / Double(maximumTokens))
            .accessibilityHidden(true)
    }

    private func summary(for day: ActivityDay) -> String {
        let label = day.date.formatted(.dateTime.weekday(.abbreviated).day().locale(locale))
        return "activity.selected".localized(
            label, UsageFormatters.tokens(day.claudeTokens), UsageFormatters.tokens(day.codexTokens))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem(color: Theme.claude, title: "provider.claude_short".localized)
            legendItem(color: Theme.codex, title: "provider.codex".localized)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
