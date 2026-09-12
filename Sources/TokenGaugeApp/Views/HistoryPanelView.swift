import SwiftUI
import TokenGaugeCore

struct HistoryPanelView: View {
    @ObservedObject var model: HistoryDashboardModel
    @Binding var mode: HistoryMode
    let providers: [UsageProvider]
    var compact = false
    @State private var scrollToCurrentDay = true

    private var locale: Locale { Locale(identifier: LocalizationManager.shared.language.rawValue) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var accent: Color { providers == [.claude] ? Theme.claude : Theme.codex }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("history.title".localized).font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                legend
            }
            HStack(spacing: 6) {
                Picker("history.view".localized, selection: $mode) {
                    ForEach(HistoryMode.allCases) { item in
                        Text(item.titleKey.localized).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Spacer(minLength: 0)
                if mode != .recent {
                    navigation
                }
            }
            if model.loadFailed {
                Text("history.load_failed".localized).font(.caption).foregroundStyle(.secondary)
            } else if model.isLoading {
                Text("history.loading".localized).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: Theme.Layout.activityChartHeight)
            } else {
                if mode == .calendar {
                    calendarGrid
                } else {
                    bars
                }
                selectionSummary
            }
        }
        .onChange(of: mode) { _, newValue in
            model.offset = 0
            model.selectedDayKey = nil
            scrollToCurrentDay = newValue == .calendar
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            ForEach(providers, id: \.self) { provider in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color(provider)).frame(width: 7, height: 7)
                    Text(name(provider))
                }
            }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }

    private var navigation: some View {
        HStack(spacing: 3) {
            Button {
                model.move(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack || model.isLoading)
            .help("history.previous".localized)
            .accessibilityLabel("history.previous".localized)
            Text(periodLabel).font(.system(size: 10)).monospacedDigit().lineLimit(1)
            Button {
                model.move(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward || model.isLoading)
            .help("history.next".localized)
            .accessibilityLabel("history.next".localized)
        }
        .buttonStyle(.borderless)
    }

    private var periodLabel: String {
        if mode == .calendar { return model.periodStart.formatted(.dateTime.year().locale(locale)) }
        let last = Calendar.current.date(byAdding: .day, value: -1, to: model.periodEnd) ?? model.periodEnd
        return model.periodStart.formatted(.dateTime.month(.abbreviated).day().locale(locale))
            + " – " + last.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }

    private var bars: some View {
        let maximum = max(1, model.days.flatMap { day in providers.compactMap { day.tokens(for: $0) } }.max() ?? 0)
        let selectedID = model.selectedDay?.id
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(model.days) { day in
                Button {
                    select(day)
                } label: {
                    VStack(spacing: 4) {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(providers, id: \.self) { provider in
                                if let tokens = day.tokens(for: provider) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color(provider).opacity(tokens == 0 ? 0.2 : 1))
                                        .frame(
                                            width: compact ? 6 : 8,
                                            height: max(
                                                1, Theme.Layout.activityChartHeight * Double(tokens) / Double(maximum)))
                                } else if day.date <= today {
                                    RoundedRectangle(cornerRadius: 1).strokeBorder(
                                        Color.secondary.opacity(0.4), lineWidth: 1
                                    )
                                    .frame(width: compact ? 6 : 8, height: 3)
                                }
                            }
                        }
                        .frame(height: Theme.Layout.activityChartHeight, alignment: .bottom)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                        Text(day.date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                            .font(.system(size: 9, weight: selectedID == day.id ? .bold : .regular))
                            .foregroundStyle(day.date == today ? .white : .secondary)
                            .frame(width: 20, height: 15)
                            .background { if day.date == today { Capsule().fill(accent) } }
                    }
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(day.date > today)
                .onHover { if $0 { select(day) } }
                .help(summary(day))
                .accessibilityLabel(summary(day))
                .accessibilityAddTraits(selectedID == day.id ? [.isSelected] : [])
            }
        }
    }

    private var calendarGrid: some View {
        let padding = model.days.first.map { (Calendar.current.component(.weekday, from: $0.date) + 5) % 7 } ?? 0
        let count = (padding + model.days.count + 6) / 7
        let maximum = max(1, model.days.compactMap { $0.total(for: providers) }.max() ?? 0)
        let selectedID = model.selectedDay?.id
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<count, id: \.self) { week in
                        VStack(spacing: 3) {
                            Text(monthLabel(week: week, padding: padding))
                                .font(.system(size: 8)).foregroundStyle(.secondary)
                                .fixedSize().frame(width: 9, height: 10, alignment: .leading)
                            ForEach(0..<7, id: \.self) { weekday in
                                let index = week * 7 + weekday - padding
                                if model.days.indices.contains(index) {
                                    calendarCell(
                                        model.days[index], maximum: maximum,
                                        selected: selectedID == model.days[index].id)
                                } else {
                                    Color.clear.frame(width: 9, height: 9)
                                }
                            }
                        }
                        .id(week)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
            .task(id: model.periodStart) {
                guard scrollToCurrentDay, model.days.count > 7 else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                if let index = model.days.firstIndex(where: { $0.id == model.selectedDay?.id }) {
                    proxy.scrollTo((index + padding) / 7, anchor: .trailing)
                }
                scrollToCurrentDay = false
            }
        }
        .frame(height: 96)
    }

    private func monthLabel(week: Int, padding: Int) -> String {
        let start = max(0, week * 7 - padding)
        let end = min(model.days.count, (week + 1) * 7 - padding)
        guard start < end,
            let day = model.days[start..<end].first(where: { Calendar.current.component(.day, from: $0.date) == 1 })
        else { return "" }
        return day.date.formatted(.dateTime.month(.abbreviated).locale(locale))
    }

    private func calendarCell(_ day: HistoryCalendarDay, maximum: Int, selected: Bool) -> some View {
        let total = day.total(for: providers)
        let future = day.date > today
        return Button {
            select(day)
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    total.map {
                        $0 > 0
                            ? accent.opacity(0.25 + 0.75 * Double($0) / Double(maximum)) : Color.primary.opacity(0.08)
                    } ?? .clear
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(
                            selected ? Color.primary : Color.secondary.opacity(total == nil && !future ? 0.4 : 0),
                            lineWidth: 1)
                }
                .frame(width: 9, height: 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .onHover { if $0 { select(day) } }
        .help(summary(day))
        .accessibilityLabel(summary(day))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var selectionSummary: some View {
        if let day = model.selectedDay {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary(day)).font(.system(size: 10)).foregroundStyle(.secondary)
                    .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                let efforts = day.efforts.filter { providers.contains($0.provider) }.sorted { $0.tokens > $1.tokens }
                if !efforts.isEmpty {
                    Text("history.local_tokens".localized).font(.system(size: 9)).foregroundStyle(.tertiary)
                    ForEach(Array(efforts.prefix(2).enumerated()), id: \.offset) { _, row in
                        Text(
                            "\(name(row.provider)) · \(row.model) · \(effortName(row.effort)): \(exact(row.tokens))"
                        )
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        .help("\(row.model) · \(row.effort): \(exact(row.tokens))")
                    }
                    if efforts.count > 2 {
                        Menu("history.all_efforts".localized) {
                            ForEach(Array(efforts.enumerated()), id: \.offset) { _, row in
                                Text(
                                    "\(name(row.provider)) · \(row.model) · \(effortName(row.effort)): \(exact(row.tokens))"
                                )
                            }
                        }.font(.system(size: 9)).menuStyle(.borderlessButton).fixedSize()
                    }
                }
            }
        }
    }

    private func effortName(_ value: String) -> String {
        if value == "unknown" { return "history.effort_unknown".localized }
        if value == "xhigh" { return "XHigh" }
        return value.capitalized
    }

    private func select(_ day: HistoryCalendarDay) {
        guard day.date <= today, model.selectedDayKey != day.id else { return }
        model.selectedDayKey = day.id
    }

    private func summary(_ day: HistoryCalendarDay) -> String {
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(locale))
        let totals = providers.map { provider in
            name(provider) + " " + (day.tokens(for: provider).map(exact) ?? "history.unknown".localized)
        }.joined(separator: " · ")
        return date + ": " + totals
    }

    private func exact(_ tokens: Int) -> String { tokens.formatted(.number.locale(locale)) }
    private func color(_ provider: UsageProvider) -> Color { provider == .claude ? Theme.claude : Theme.codex }
    private func name(_ provider: UsageProvider) -> String {
        (provider == .claude ? "provider.claude_short" : "provider.codex").localized
    }
}
