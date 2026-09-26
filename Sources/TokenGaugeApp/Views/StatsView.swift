import SwiftUI
import TokenGaugeCore

struct StatsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var model: StatsModel
    let providers: [UsageProvider]
    var scrolls = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    @State private var selectedForecast: String?
    @State private var appeared = false

    private var locale: Locale { Locale(identifier: LocalizationManager.shared.language.rawValue) }
    private var animates: Bool { animateChanges && !reduceMotion }
    private var shown: Bool { appeared || !animates }
    private var accent: Color { providers == [.codex] ? Theme.codex : Theme.claude }

    private var forecasts: [QuotaForecast] {
        let states = providers.compactMap { provider -> (UsageProvider, [QuotaWindow])? in
            let state = store.state(for: provider)
            guard state.status == .ready, let snapshot = state.snapshot else { return nil }
            return (
                provider,
                WindowVisibility.visible(
                    snapshot.windows, provider: provider, showLunaReserve: store.showLunaReserve,
                    hiddenClaudeWindows: store.hiddenClaudeWindows)
            )
        }
        return model.forecasts(for: states, accountFingerprint: store.claudeAccountFingerprint)
            .sorted { urgency($0) < urgency($1) }
    }

    private var summary: StatsSummary? {
        model.summary(for: providers, codexSummary: store.codex.snapshot?.summary)
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { sections }.scrollIndicators(.never)
            } else {
                sections
            }
        }
        .onAppear {
            guard !appeared else { return }
            if animates { withAnimation(.easeOut(duration: 0.35)) { appeared = true } } else { appeared = true }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.loadFailed {
                placeholder("stats.load_failed".localized, symbol: "exclamationmark.triangle")
            } else if model.records == nil {
                placeholder("stats.loading".localized, symbol: "chart.xyaxis.line")
            } else {
                let forecasts = forecasts
                section(0) { forecastCard(forecasts) }
                if let summary {
                    section(1) { todayCard(summary) }
                    section(2) { totalsGrid(summary) }
                    section(3) { dailyCard(summary) }
                    if summary.turns != nil || summary.cachedShare != nil {
                        section(4) { activityCard(summary) }
                    }
                    section(5) { rankings(summary) }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func section<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .animation(
                animates ? .spring(response: 0.42, dampingFraction: 0.85).delay(0.05 * Double(index)) : nil,
                value: appeared)
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).accessibilityHidden(true).foregroundStyle(
                .secondary)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).frame(height: 180)
    }

    private func card<Content: View>(
        _ id: StatsCard, _ title: String, symbol: String, trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let collapsed = store.collapsedStatsCards.contains(id)
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(animates ? .spring(response: 0.34, dampingFraction: 0.88) : nil) {
                    store.toggleStatsCard(id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
                        .foregroundStyle(accent)
                    Text(title).font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 4)
                    if let trailing {
                        Text(trailing).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help((collapsed ? "stats.card.expand" : "stats.card.collapse").localized)
            .accessibilityValue((collapsed ? "stats.card.collapsed" : "stats.card.expanded").localized)
            if !collapsed {
                content().transition(.opacity)
            }
        }
        .padding(Theme.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .providerCard()
    }

    private func urgency(_ forecast: QuotaForecast) -> Double {
        switch forecast.verdict {
        case .exhausted: return -1_000
        case .runsOut(let date): return -100 + date.timeIntervalSince(forecast.now) / 86_400
        case .tight(let margin), .lasts(let margin): return margin
        case .noUsage: return 1_000
        }
    }

    @ViewBuilder private func forecastCard(_ forecasts: [QuotaForecast]) -> some View {
        let selected = forecasts.first { $0.id == selectedForecast } ?? forecasts.first
        card(.forecast, "stats.forecast.title".localized, symbol: "gauge.with.needle") {
            if let selected {
                VStack(alignment: .leading, spacing: 10) {
                    headline(selected)
                    ForecastChartView(forecast: selected, tint: color(selected.provider), locale: locale)
                        .id(selected.id)
                        .transition(.opacity)
                    paceLine(selected)
                    if forecasts.count > 1 {
                        VStack(spacing: 4) {
                            ForEach(forecasts) { forecast in
                                forecastRow(forecast, selected: forecast.id == selected.id)
                            }
                        }
                    }
                }
                .animation(animates ? .easeInOut(duration: 0.22) : nil, value: selected.id)
            } else {
                Text("stats.forecast.unavailable".localized)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .help((selected?.isSession == true ? "stats.forecast.help_session" : "stats.forecast.help").localized)
    }

    private func headline(_ forecast: QuotaForecast) -> some View {
        let (symbol, tint) = verdictStyle(forecast.verdict)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).accessibilityHidden(true)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(headlineText(forecast.verdict))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.opacity)
                Text(verdictText(forecast))
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    ProviderLogo(provider: forecast.provider, size: 11)
                    Text(windowName(forecast)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                Text(UsageFormatters.reset(forecast.reset))
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func paceLine(_ forecast: QuotaForecast) -> some View {
        HStack(spacing: 10) {
            let session = forecast.isSession
            if let average = forecast.pointsPerHour {
                label(
                    "speedometer",
                    (session ? "stats.pace.session" : "stats.pace.average").localized(pace(average, forecast)))
            }
            if let recent = forecast.recentPointsPerHour {
                label(
                    "clock.arrow.circlepath",
                    (session ? "stats.pace.hour" : "stats.pace.today").localized(pace(recent, forecast)))
            }
            Spacer(minLength: 0)
            if forecast.remaining > 0, forecast.pointsPerHour != nil {
                label(
                    session ? "hourglass" : "calendar",
                    (session ? "stats.budget.hour" : "stats.budget").localized(
                        UsageFormatters.percentage(forecast.budget)))
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.secondary)
    }

    private func label(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8.5)).accessibilityHidden(true)
            Text(text).lineLimit(1).monospacedDigit()
        }
    }

    private func forecastRow(_ forecast: QuotaForecast, selected: Bool) -> some View {
        let (symbol, tint) = verdictStyle(forecast.verdict)
        return Button {
            selectedForecast = forecast.id
        } label: {
            HStack(spacing: 7) {
                ProviderLogo(provider: forecast.provider, size: 11)
                Text(windowName(forecast)).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
                    .foregroundStyle(tint)
                Text(shortVerdict(forecast)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8).frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? color(forecast.provider).opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? color(forecast.provider).opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func verdictStyle(_ verdict: QuotaForecast.Verdict) -> (String, Color) {
        switch verdict {
        case .lasts: return ("checkmark.seal.fill", .green)
        case .tight: return ("exclamationmark.circle.fill", .orange)
        case .runsOut: return ("exclamationmark.triangle.fill", .red)
        case .exhausted: return ("xmark.octagon.fill", .red)
        case .noUsage: return ("moon.zzz.fill", .secondary)
        }
    }

    private func headlineText(_ verdict: QuotaForecast.Verdict) -> String {
        switch verdict {
        case .lasts: return "stats.headline.lasts".localized
        case .tight: return "stats.headline.tight".localized
        case .runsOut: return "stats.headline.runs_out".localized
        case .exhausted: return "stats.headline.exhausted".localized
        case .noUsage: return "stats.headline.no_usage".localized
        }
    }

    private func verdictText(_ forecast: QuotaForecast) -> String {
        switch forecast.verdict {
        case .lasts(let margin): return "stats.verdict.lasts".localized(UsageFormatters.percentage(margin))
        case .tight(let margin): return "stats.verdict.tight".localized(UsageFormatters.percentage(max(0, margin)))
        case .runsOut(let date):
            return (forecast.isSession ? "stats.verdict.runs_out_session" : "stats.verdict.runs_out").localized(
                moment(date, forecast),
                UsageFormatters.duration(forecast.reset.timeIntervalSince(date)))
        case .exhausted: return "stats.verdict.exhausted".localized
        case .noUsage: return "stats.verdict.no_usage".localized
        }
    }

    private func shortVerdict(_ forecast: QuotaForecast) -> String {
        switch forecast.verdict {
        case .lasts(let margin), .tight(let margin):
            return "stats.row.left".localized(UsageFormatters.percentage(max(0, margin)))
        case .runsOut(let date): return moment(date, forecast)
        case .exhausted: return "stats.headline.exhausted".localized
        case .noUsage: return UsageFormatters.percentage(forecast.remaining)
        }
    }

    private func windowName(_ forecast: QuotaForecast) -> String {
        UsageFormatters.windowName(
            QuotaWindow(
                id: forecast.windowID, usedPercentage: 100 - forecast.remaining, resetsAt: forecast.reset,
                durationMinutes: Int(forecast.reset.timeIntervalSince(forecast.start) / 60),
                displayName: forecast.displayName))
    }

    private func pace(_ value: Double, _ forecast: QuotaForecast) -> String {
        UsageFormatters.percentage(value * forecast.budgetUnit / 3600)
    }

    private func moment(_ date: Date, _ forecast: QuotaForecast) -> String {
        date.formatted(
            forecast.isSession
                ? .dateTime.hour().minute().locale(locale)
                : .dateTime.weekday(.abbreviated).hour().minute().locale(locale))
    }

    private func todayCard(_ summary: StatsSummary) -> some View {
        card(
            .today, "stats.today.title".localized, symbol: "sun.max.fill",
            trailing: summary.typicalDay.map { "stats.today.typical".localized(UsageFormatters.tokens($0)) }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.today.map(UsageFormatters.tokens) ?? "—")
                        .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    if let ratio = summary.ratio {
                        Text("stats.today.ratio".localized(ratioText(ratio)))
                            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(ratioColor(ratio))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(ratioColor(ratio).opacity(0.13)))
                    }
                    Spacer(minLength: 0)
                }
                if let insight = summary.insight {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: insightSymbol(insight)).font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                            .foregroundStyle(insightColor(insight))
                        Text(insightText(insight)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func ratioText(_ ratio: Double) -> String {
        ratio.formatted(.number.precision(.fractionLength(ratio >= 10 ? 0 : 1)).locale(locale))
    }

    private func ratioColor(_ ratio: Double) -> Color {
        if ratio >= 1.8 { return .orange }
        if ratio <= 0.4 { return Theme.codex }
        return .secondary
    }

    private func insightSymbol(_ insight: StatsInsight) -> String {
        switch insight {
        case .newModel: return "sparkles"
        case .spike: return "flame.fill"
        case .quiet: return "moon.fill"
        case .steady: return "checkmark.circle.fill"
        }
    }

    private func insightColor(_ insight: StatsInsight) -> Color {
        switch insight {
        case .newModel: return .purple
        case .spike: return .orange
        case .quiet: return Theme.codex
        case .steady: return .green
        }
    }

    private func insightText(_ insight: StatsInsight) -> String {
        switch insight {
        case .newModel(let model): return "stats.insight.new_model".localized(model)
        case .spike: return "stats.insight.spike".localized
        case .quiet: return "stats.insight.quiet".localized
        case .steady: return "stats.insight.steady".localized
        }
    }

    private func totalsGrid(_ summary: StatsSummary) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            tile(
                "stats.week".localized, value: UsageFormatters.tokens(summary.week),
                delta: delta(summary.week, summary.previousWeek))
            tile(
                "stats.month".localized, value: UsageFormatters.tokens(summary.month),
                delta: delta(summary.month, summary.previousMonth))
            tile(
                "stats.lifetime".localized, value: UsageFormatters.tokens(summary.lifetime),
                caption: summary.since.map {
                    "stats.since".localized($0.formatted(.dateTime.month(.abbreviated).year().locale(locale)))
                })
            tile(
                "stats.peak".localized, value: summary.peak.map { UsageFormatters.tokens($0.tokens) } ?? "—",
                caption: summary.peak.map { $0.date.formatted(.dateTime.day().month(.abbreviated).locale(locale)) })
            tile(
                "stats.streak".localized, value: "stats.days_value".localized(String(summary.streak.current)),
                caption: "stats.streak_best".localized(String(summary.streak.longest)), symbol: "flame.fill")
            tile(
                "stats.active_days".localized, value: String(summary.activeDays),
                caption: summary.since.map {
                    "stats.since".localized($0.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                })
        }
    }

    private func delta(_ current: Int, _ previous: Int?) -> Double? {
        guard let previous, previous > 0 else { return nil }
        return Double(current - previous) / Double(previous)
    }

    private func tile(
        _ title: String, value: String, delta: Double? = nil, caption: String? = nil, symbol: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 8, weight: .semibold)).accessibilityHidden(true)
                        .foregroundStyle(accent)
                }
                Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if let delta {
                Text((delta >= 0 ? "▲ " : "▼ ") + UsageFormatters.percentage(abs(delta) * 100))
                    .font(.system(size: 8.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(delta >= 0 ? Color.orange : Color.green)
                    .help("stats.vs_previous".localized)
            } else if let caption {
                Text(caption).font(.system(size: 8.5)).foregroundStyle(.tertiary).lineLimit(1)
            } else {
                Text(" ").font(.system(size: 8.5))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func dailyCard(_ summary: StatsSummary) -> some View {
        card(.daily, "stats.daily.title".localized, symbol: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 8) {
                StatsBarsView(
                    days: summary.recent, typical: summary.typicalDay, providers: providers, locale: locale,
                    tint: accent)
                legend(summary.legend)
            }
        }
    }

    private func legend(_ items: [StatsSegment]) -> some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(StatsBarsView.color(item, providers: providers))
                        .frame(width: 8, height: 8)
                    Text(segmentName(item.id)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func segmentName(_ id: String) -> String {
        if id == StatsSummary.otherLabel { return "stats.other".localized }
        if let provider = UsageProvider(rawValue: id) { return name(provider) }
        return id
    }

    private func activityCard(_ summary: StatsSummary) -> some View {
        card(.activity, "stats.activity.title".localized, symbol: "bolt.fill") {
            HStack(spacing: 8) {
                if let turns = summary.turns, turns.todayCount > 0 {
                    tile(
                        "stats.activity.today".localized,
                        value: UsageFormatters.duration(Double(turns.todayMilliseconds) / 1000),
                        caption: "stats.activity.turns".localized(String(turns.todayCount)))
                }
                if let turns = summary.turns {
                    tile(
                        "stats.activity.longest".localized,
                        value: UsageFormatters.duration(Double(turns.longestMilliseconds) / 1000),
                        caption: "stats.activity.longest_hint".localized)
                }
                if let share = summary.cachedShare {
                    tile(
                        "stats.activity.cache".localized, value: UsageFormatters.percentage(share * 100),
                        caption: "stats.activity.cache_hint".localized)
                }
            }
        }
    }

    @ViewBuilder private func rankings(_ summary: StatsSummary) -> some View {
        VStack(spacing: 10) {
            if !summary.models.isEmpty {
                card(.models, "stats.models.title".localized, symbol: "cpu") { rankList(summary.models, unit: nil) }
            }
            if !summary.efforts.isEmpty {
                card(.efforts, "stats.efforts.title".localized, symbol: "brain.head.profile") {
                    rankList(summary.efforts, unit: nil)
                }
            }
            if !summary.skills.isEmpty {
                card(.skills, "stats.skills.title".localized, symbol: "wand.and.stars") {
                    rankList(summary.skills, unit: "stats.skills.runs")
                }
            }
        }
    }

    private func rankList(_ items: [StatsRankItem], unit: String?) -> some View {
        let maximum = max(1, items.map(\.value).max() ?? 1)
        let total = max(1, items.map(\.value).reduce(0, +))
        return VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let tint = item.provider.map(color) ?? accent
                HStack(spacing: 8) {
                    if let provider = item.provider, providers.count > 1 {
                        ProviderLogo(provider: provider, size: 10)
                    }
                    Text(item.label).font(.system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        .frame(width: unit == nil ? 104 : 150, alignment: .leading)
                        .help(item.label)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule().fill(tint.opacity(1 - Double(index) * 0.12))
                                .frame(
                                    width: shown
                                        ? max(4, proxy.size.width * CGFloat(item.value) / CGFloat(maximum)) : 4
                                )
                                .animation(
                                    animates
                                        ? .spring(response: 0.55, dampingFraction: 0.8).delay(
                                            0.25 + 0.04 * Double(index))
                                        : nil, value: appeared)
                        }
                    }
                    .frame(height: 6)
                    Text(
                        unit.map { (item.value == 1 ? $0 + "_one" : $0).localized(String(item.value)) }
                            ?? UsageFormatters.tokens(item.value)
                    )
                    .font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: unit == nil ? 44 : 58, alignment: .trailing)
                    .help(unit == nil ? UsageFormatters.percentage(Double(item.value) * 100 / Double(total)) : "")
                }
            }
        }
    }

    private func color(_ provider: UsageProvider) -> Color { provider == .claude ? Theme.claude : Theme.codex }
    private func name(_ provider: UsageProvider) -> String {
        (provider == .claude ? "provider.claude_short" : "provider.codex").localized
    }

}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
