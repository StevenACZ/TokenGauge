import AppKit
import SwiftUI
import TokenGaugeCore

struct HistoryPanelView: View {
    @ObservedObject var model: HistoryDashboardModel
    @Binding var mode: HistoryMode
    let providers: [UsageProvider]
    var compact = false
    @State private var calendarFocusRequest = 0
    @State private var showingDetails = false
    @State private var lastPointerLocation = NSEvent.mouseLocation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    @Namespace private var daySelection

    private var locale: Locale { Locale(identifier: LocalizationManager.shared.language.rawValue) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var accent: Color { providers == [.claude] ? Theme.claude : Theme.codex }

    private var motion: Animation? {
        animateChanges && !reduceMotion ? .easeInOut(duration: 0.18) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if mode == .recent {
                    Text("history.heading".localized).font(.system(size: 11, weight: .semibold))
                } else {
                    navigation
                }
                Spacer(minLength: 0)
                modePicker
            }
            if model.loadFailed {
                Text("history.load_failed".localized).font(.caption).foregroundStyle(.secondary)
            } else if model.isLoading && model.days.isEmpty {
                Text("history.loading".localized).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: Theme.Layout.activityChartHeight)
            } else {
                Group {
                    if model.loadedMode == .calendar {
                        calendarGrid.transition(.opacity)
                    } else {
                        bars.transition(.opacity)
                    }
                }
                .animation(motion, value: model.loadedMode)
                .animation(motion, value: model.periodStart)
                selectionSummary
            }
        }
        .onChange(of: mode) { _, newValue in
            model.offset = 0
            model.selectedDayKey = nil
            lastPointerLocation = NSEvent.mouseLocation
            if newValue == .calendar { model.selectedDayKey = HistoryDashboardModel.dayKey(today) }
        }
        .onChange(of: model.periodStart) { _, _ in
            lastPointerLocation = NSEvent.mouseLocation
            if mode == .calendar {
                model.selectedDayKey =
                    (model.days.first(where: { $0.date == today })
                    ?? model.days.last(where: { $0.total(for: providers) != nil }) ?? model.days.last)?.id
            }
        }
    }

    private var modePicker: some View {
        HistoryModeControl(mode: $mode)
            .frame(
                width: Theme.Layout.historyModeSegmentWidth * 3 + 4,
                height: Theme.Layout.historyModeSegmentHeight + 4)
    }

    private var todayButton: some View {
        Button {
            model.offset = 0
            model.selectedDayKey = HistoryDashboardModel.dayKey(today)
            calendarFocusRequest &+= 1
        } label: {
            HStack(spacing: 3) {
                Circle().fill(accent).frame(width: 3, height: 3)
                Text("history.today".localized)
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("history.return_today".localized)
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            periodButton(-1, enabled: model.canGoBack)
            Text(periodLabel)
                .font(.system(size: 10, weight: .medium)).monospacedDigit().lineLimit(1)
                .frame(width: mode == .calendar ? 52 : 90)
            periodButton(1, enabled: model.canGoForward)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.045)))
    }

    private func periodButton(_ direction: Int, enabled: Bool) -> some View {
        Button {
            model.move(direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
                .opacity(enabled && !model.isLoading ? 1 : 0.25)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || model.isLoading)
        .help((direction < 0 ? "history.previous" : "history.next").localized)
        .accessibilityLabel((direction < 0 ? "history.previous" : "history.next").localized)
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
                                            width: compact ? 8 : 10,
                                            height: max(
                                                1, Theme.Layout.activityChartHeight * Double(tokens) / Double(maximum)))
                                } else if day.date <= today {
                                    Capsule().fill(Color.secondary.opacity(0.25))
                                        .frame(width: 5, height: 1)
                                }
                            }
                        }
                        .frame(height: Theme.Layout.activityChartHeight, alignment: .bottom)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
                        HStack(spacing: 3) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                            Text(day.date.formatted(.dateTime.day().locale(locale)))
                        }
                        .font(.system(size: 9, weight: selectedID == day.id ? .semibold : .regular))
                        .foregroundStyle(selectedID == day.id ? .primary : .secondary)
                        .frame(height: 18).frame(maxWidth: .infinity)
                        .background {
                            if selectedID == day.id {
                                RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.14))
                                    .matchedGeometryEffect(id: "day", in: daySelection)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if day.date == today { Circle().fill(accent).frame(width: 3, height: 3) }
                        }
                    }
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(day.date > today)
                .onContinuousHover { phase in
                    guard case .active = phase else { return }
                    let pointer = NSEvent.mouseLocation
                    guard pointer != lastPointerLocation else { return }
                    lastPointerLocation = pointer
                    select(day)
                }
                .help(summary(day))
                .accessibilityLabel(summary(day))
                .accessibilityAddTraits(selectedID == day.id ? [.isSelected] : [])
            }
        }
    }

    private var calendarGrid: some View {
        HistoryCalendarView(
            days: model.days, providers: providers, selectedDayKey: model.selectedDay?.id,
            focusID: "\(model.periodStart.timeIntervalSince1970):\(calendarFocusRequest)",
            hoverEnabled: !showingDetails && !model.isLoading
        ) { key in
            if let day = model.days.first(where: { $0.id == key }) { select(day) }
        }
        .frame(height: 96)
    }

    @ViewBuilder private var selectionSummary: some View {
        if let day = model.selectedDay {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale)))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if mode != .recent { todayButton }
                    Spacer()
                    Button {
                        showingDetails.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text("history.details".localized)
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        }.font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(day.efforts.filter { providers.contains($0.provider) }.isEmpty)
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                        effortDetails(day)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(providers, id: \.self) { provider in
                        providerTotal(provider, day: day)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.035)))
        }
    }

    private func providerTotal(_ provider: UsageProvider, day: HistoryCalendarDay) -> some View {
        let tokens = day.tokens(for: provider)
        let full = name(provider) + ": " + (tokens.map { exact($0) } ?? "history.unknown".localized)
        let value = tokens.map { UsageFormatters.tokens($0) } ?? "—"
        return HStack(spacing: 7) {
            ProviderLogo(provider: provider, size: 14)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(color(provider).opacity(0.075)))
        .help(full).accessibilityElement(children: .ignore).accessibilityLabel(full)
    }

    private func effortDetails(_ day: HistoryCalendarDay) -> some View {
        let rows = day.efforts.filter { providers.contains($0.provider) }.sorted { $0.tokens > $1.tokens }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("history.details_title".localized).font(.system(size: 12, weight: .semibold))
                    Text(day.date.formatted(.dateTime.day().month(.wide).year().locale(locale)))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingDetails = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .padding(5).background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain).accessibilityLabel("history.close_details".localized)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            ProviderLogo(provider: row.provider, size: 13)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.model).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(effortName(row.effort)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(UsageFormatters.tokens(row.tokens))
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                .help(exact(row.tokens))
                                .accessibilityLabel(exact(row.tokens))
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(rows.count) * 41, 230))
            Text("history.details_note".localized)
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(width: 300)
    }

    private func effortName(_ value: String) -> String {
        if value == "unknown" { return "history.effort_unknown".localized }
        if value == "xhigh" { return "XHigh" }
        return value.capitalized
    }

    private func select(_ day: HistoryCalendarDay) {
        guard !showingDetails, !model.isLoading, day.date <= today, model.selectedDayKey != day.id else { return }
        withAnimation(motion) { model.selectedDayKey = day.id }
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
