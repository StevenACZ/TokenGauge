import SwiftUI
import TokenGaugeCore

struct ActivityDay: Identifiable {
    let id: String
    let date: Date
    let claudeTokens: Int
    let codexTokens: Int

    func tokens(for provider: UsageProvider) -> Int {
        provider == .claude ? claudeTokens : codexTokens
    }
}

struct ActivityChartData {
    let days: [ActivityDay]
    let providers: [UsageProvider]
    let maximumTokens: Int

    init(
        claude: ProviderUsageSnapshot?, codex: ProviderUsageSnapshot?,
        providers: [UsageProvider] = [.claude, .codex], now: Date = Date(), calendar: Calendar = .current
    ) {
        var seen: Set<UsageProvider> = []
        self.providers = providers.filter { seen.insert($0).inserted }
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let claudeTotals = Dictionary((claude?.dailyUsage ?? []).map { ($0.day, $0.tokens) }, uniquingKeysWith: max)
        let codexTotals = Dictionary((codex?.dailyUsage ?? []).map { ($0.day, $0.tokens) }, uniquingKeysWith: max)
        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return nil }
            let key = formatter.string(from: date)
            return ActivityDay(
                id: key, date: date, claudeTokens: claudeTotals[key] ?? 0, codexTokens: codexTotals[key] ?? 0)
        }
        maximumTokens = max(days.flatMap { day in providers.map { day.tokens(for: $0) } }.max() ?? 0, 1)
    }

    func selectedDay(key: String) -> ActivityDay? {
        days.first { $0.id == key } ?? days.last
    }

    @MainActor func summary(for day: ActivityDay, locale: Locale) -> String {
        let label = day.date.formatted(.dateTime.weekday(.abbreviated).day().locale(locale))
        let totals = providers.map { provider in
            let name = (provider == .claude ? "provider.claude_short" : "provider.codex").localized
            return "\(name) \(UsageFormatters.tokens(day.tokens(for: provider)))"
        }.joined(separator: " · ")
        return "activity.selected_scoped".localized(label, totals)
    }
}

struct ActivityChartView: View {
    private let data: ActivityChartData
    @State private var selectedKey: String

    init(
        claude: ProviderUsageSnapshot?, codex: ProviderUsageSnapshot?,
        providers: [UsageProvider] = [.claude, .codex]
    ) {
        let data = ActivityChartData(claude: claude, codex: codex, providers: providers)
        self.data = data
        _selectedKey = State(initialValue: data.days.last?.id ?? "")
    }

    var body: some View {
        let selectedDay = data.selectedDay(key: selectedKey)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("activity.title".localized)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                legend
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(data.days) { day in
                    let isToday = day.id == data.days.last?.id
                    Button {
                        select(day)
                    } label: {
                        VStack(spacing: 5) {
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(data.providers.filter { day.tokens(for: $0) > 0 }, id: \.self) { provider in
                                    bar(
                                        tokens: day.tokens(for: provider),
                                        tint: provider == .claude ? Theme.claude : Theme.codex)
                                }
                            }
                            .frame(height: 44, alignment: .bottom)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
                            }
                            Text(day.date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                                .font(.system(size: 9, weight: isToday || day.id == selectedDay?.id ? .bold : .regular))
                                .foregroundStyle(
                                    isToday ? .white : day.id == selectedDay?.id ? Color.primary : Color.secondary
                                )
                                .frame(width: 22, height: 16)
                                .background {
                                    if isToday {
                                        Capsule().fill(data.providers == [.claude] ? Theme.claude : Theme.codex)
                                    }
                                }
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
            .frame(width: 9, height: 44 * Double(tokens) / Double(data.maximumTokens))
            .accessibilityHidden(true)
    }

    private func summary(for day: ActivityDay) -> String {
        data.summary(for: day, locale: locale)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(data.providers, id: \.self) { provider in
                legendItem(
                    color: provider == .claude ? Theme.claude : Theme.codex,
                    title: (provider == .claude ? "provider.claude_short" : "provider.codex").localized)
            }
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

}
