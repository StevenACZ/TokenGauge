import AppKit
import SwiftUI
import TokenGaugeCore

struct HistoryPanelView: View {
    @ObservedObject var model: HistoryDashboardModel
    @Binding var mode: HistoryMode
    let providers: [UsageProvider]
    var resets: [HistoryReset] = []
    var compact = false
    @State private var calendarFocusRequest = 0
    @State private var showingDetails = false
    @State private var lastPointerLocation = NSEvent.mouseLocation
    @State private var frames: [HistoryFrame: CGRect] = [:]
    @State private var cardHeight: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    @Namespace private var daySelection

    private var locale: Locale { Locale(identifier: LocalizationManager.shared.language.rawValue) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var accent: Color {
        if providers == [.claude] { return Theme.claude }
        if providers == [.codex] { return Theme.codex }
        return Color(nsColor: .labelColor)
    }

    private var calendarProviders: [UsageProvider] {
        let recorded = [UsageProvider.codex, .claude].filter { provider in
            model.days.contains { $0.tokens(for: provider) != nil } || resets.contains { $0.provider == provider }
        }
        return recorded.isEmpty ? [.codex, .claude] : recorded
    }

    private var stripProviders: [UsageProvider] {
        model.loadedMode == .calendar ? calendarProviders : providers
    }

    private var motion: Animation? {
        animateChanges && !reduceMotion ? .easeInOut(duration: 0.18) : nil
    }

    private var cardMotion: Animation? {
        animateChanges && !reduceMotion ? .easeOut(duration: 0.12) : nil
    }

    private var cardTransition: AnyTransition {
        animateChanges && !reduceMotion ? .opacity.combined(with: .scale(scale: 0.97)) : .identity
    }

    private var pinnedDayKey: String? {
        model.daySelection.flatMap { $0.isPinned ? $0.dayKey : nil }
    }

    private var cardFrame: CGRect? {
        guard let anchor = model.daySelection?.anchor, let calendar = frames[.calendar] else { return nil }
        let size = CGSize(width: HistoryDayCardPlacement.width, height: cardHeight)
        let origin = HistoryDayCardPlacement.origin(
            anchor: anchor.cell.offsetBy(dx: calendar.minX, dy: calendar.minY), cardSize: size,
            bounds: anchor.bounds.offsetBy(dx: calendar.minX, dy: calendar.minY))
        return CGRect(origin: origin, size: size)
    }

    private var pinSafeFrames: [CGRect] {
        guard let calendar = frames[.calendar] else { return [] }
        return [cardFrame, frames[.summary]].compactMap { $0?.offsetBy(dx: -calendar.minX, dy: -calendar.minY) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                historyToolbar(showsStreak: true)
                historyToolbar(showsStreak: false)
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
        .background(frameReporter(.panel))
        .overlay(alignment: .topLeading) { dayCard.animation(cardMotion, value: model.daySelection != nil) }
        .zIndex(1)
        .onPreferenceChange(HistoryFrameKey.self) { frames = $0 }
        .onPreferenceChange(HistoryDayCardHeightKey.self) { if $0 > 0 { cardHeight = $0 } }
        .onChange(of: providers) { _, _ in dismissDayCard() }
        .onChange(of: resets) { _, _ in dismissDayCard() }
        .onChange(of: mode) { _, newValue in
            model.offset = 0
            model.selectedDayKey = nil
            model.dismissDayCard()
            lastPointerLocation = NSEvent.mouseLocation
            if newValue == .calendar { model.selectedDayKey = HistoryDashboardModel.dayKey(today) }
        }
        .onChange(of: model.periodStart) { _, _ in
            lastPointerLocation = NSEvent.mouseLocation
            model.dismissDayCard()
            if mode == .calendar {
                model.selectedDayKey =
                    (model.days.first(where: { $0.date == today })
                    ?? model.days.last(where: { $0.total(for: calendarProviders) != nil }) ?? model.days.last)?.id
            }
        }
    }

    private func historyToolbar(showsStreak: Bool) -> some View {
        HStack(spacing: 0) {
            if mode == .recent {
                Text("history.heading".localized).font(.system(size: 11, weight: .semibold))
                    .fixedSize()
            } else {
                navigation
            }
            Spacer(minLength: 6)
            if showsStreak {
                streakBadge
                Spacer(minLength: 6)
            }
            modePicker
        }
    }

    private var streakBadge: some View {
        let streak = model.streak(for: providers)
        return HStack(spacing: 3) {
            Image(systemName: "flame.fill").foregroundStyle(streak.current > 0 ? accent : .secondary)
                .symbolEffect(.bounce, value: streak.current)
            Text("stats.days_value".localized(String(streak.current)))
                .foregroundStyle(.primary.opacity(0.85)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 10.5, weight: .semibold))
        .padding(.horizontal, 8)
        .frame(height: Theme.Layout.historyModeSegmentHeight + 4)
        .background(Capsule().fill(accent.opacity(streak.current > 0 ? 0.1 : 0.04)))
        .fixedSize()
        .help(streakLine)
        .accessibilityElement(children: .ignore).accessibilityLabel(streakLine)
    }

    @ViewBuilder private var dayCard: some View {
        if let selection = model.daySelection, let frame = cardFrame, let panel = frames[.panel],
            let day = model.days.first(where: { $0.id == selection.dayKey })
        {
            let streak = model.streak(for: providers)
            HistoryDayCardView(
                day: day, providers: calendarProviders, resets: resetsOn(day),
                isToday: Calendar.current.isDate(day.date, inSameDayAs: today),
                isPinned: selection.isPinned, currentStreak: streak.current, longestStreak: streak.longest,
                onClose: dismissDayCard
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HistoryDayCardHeightKey.self, value: proxy.size.height)
                }
            )
            .allowsHitTesting(selection.isPinned)
            .offset(x: frame.minX - panel.minX, y: frame.minY - panel.minY)
            .transition(cardTransition)
        }
    }

    private func frameReporter(_ kind: HistoryFrame) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HistoryFrameKey.self, value: [kind: proxy.frame(in: .global)])
        }
    }

    private func dismissDayCard() {
        guard model.daySelection != nil else { return }
        model.dismissDayCard()
        selectToday()
    }

    private func selectToday() {
        guard mode == .calendar else { return }
        model.selectedDayKey = HistoryDashboardModel.dayKey(today)
    }

    private var modePicker: some View {
        HistoryModeControl(mode: $mode)
    }

    private var todayBadge: some View {
        HStack(spacing: 3) {
            Circle().fill(accent).frame(width: 3, height: 3)
            Text("history.today".localized)
        }
        .font(.system(size: 9, weight: .medium))
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.08)))
    }

    private var navigation: some View {
        HistoryPeriodControl(
            title: periodLabel,
            canGoBack: model.canGoBack && !model.isLoading,
            canGoForward: model.canGoForward && !model.isLoading,
            onPrevious: { model.move(-1) }, onToday: returnToToday, onNext: { model.move(1) }
        )
    }

    private func returnToToday() {
        model.offset = 0
        model.selectedDayKey = HistoryDashboardModel.dayKey(today)
        calendarFocusRequest &+= 1
    }

    private var periodLabel: String {
        if mode == .calendar { return model.periodStart.formatted(.dateTime.year().locale(locale)) }
        let last = Calendar.current.date(byAdding: .day, value: -1, to: model.periodEnd) ?? model.periodEnd
        guard Calendar.current.isDate(model.periodStart, equalTo: last, toGranularity: .month) else {
            return model.periodStart.formatted(.dateTime.day().month(.abbreviated).locale(locale))
                + "–" + last.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        }
        return model.periodStart.formatted(.dateTime.day().locale(locale)) + "–"
            + last.formatted(.dateTime.day().month(.abbreviated).locale(locale))
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
                        .overlay(alignment: .top) {
                            HStack(spacing: 2) {
                                ForEach(
                                    providers.filter { provider in resetsOn(day).contains { $0.provider == provider } },
                                    id: \.self
                                ) { provider in
                                    RoundedRectangle(cornerRadius: 1).stroke(color(provider), lineWidth: 1)
                                        .frame(width: 4, height: 4)
                                }
                            }.offset(y: -3)
                        }
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
                .disabled(day.date > today && resetsOn(day).isEmpty)
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
        HStack(alignment: .top, spacing: 5) {
            VStack(spacing: 3) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                    let weekend = weekday == 7 || weekday == 1
                    Text(weekdayLabel(weekday))
                        .font(.system(size: 7, weight: weekend ? .semibold : .regular))
                        .foregroundStyle(weekend ? .primary : .secondary)
                        .frame(width: 20, height: 9)
                        .background {
                            if weekend { RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08)) }
                        }
                        .help(weekend ? "history.weekends".localized : weekdayLabel(weekday))
                }
            }
            .padding(.top, Theme.Layout.historyCalendarGridTop)
            HistoryCalendarView(
                days: model.days, providers: calendarProviders, selectedDayKey: model.selectedDay?.id,
                focusID: "\(model.periodStart.timeIntervalSince1970):\(calendarFocusRequest)",
                hoverEnabled: !showingDetails && !model.isLoading,
                accent: accent, resets: resets, pinnedDayKey: pinnedDayKey, pinSafeFrames: pinSafeFrames,
                onHoverCard: { key, anchor in
                    guard let key else {
                        model.hideDayCard()
                        return
                    }
                    model.showDayCard(key, anchor: anchor)
                },
                onPinCard: { key, anchor in
                    model.pinDayCard(key, anchor: anchor)
                    if model.daySelection == nil { selectToday() }
                },
                onExitCalendar: {
                    guard model.daySelection?.isPinned != true else { return }
                    model.hideDayCard()
                    selectToday()
                },
                onDismissCard: dismissDayCard
            ) { key in
                if let day = model.days.first(where: { $0.id == key }) { select(day) }
            }
            .background(frameReporter(.calendar))
        }
        .frame(height: Theme.Layout.historyCalendarHeight)
    }

    private func resetsOn(_ day: HistoryCalendarDay) -> [HistoryReset] {
        resets.filter { Calendar.current.isDate($0.date, inSameDayAs: day.date) }
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar.shortWeekdaySymbols[weekday - 1].capitalized(with: locale)
    }

    @ViewBuilder private var selectionSummary: some View {
        if let selected = model.selectedDay,
            let day = selected.date > today ? model.days.first(where: { $0.date == today }) : selected
        {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale)))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    todayBadge
                        .opacity(Calendar.current.isDate(day.date, inSameDayAs: today) ? 1 : 0)
                        .accessibilityHidden(!Calendar.current.isDate(day.date, inSameDayAs: today))
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
                    .disabled(day.efforts.filter { stripProviders.contains($0.provider) }.isEmpty)
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                        effortDetails(day)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(stripProviders, id: \.self) { provider in
                        providerTotal(provider, day: day)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.035)))
            .background(frameReporter(.summary))
            .animation(motion, value: day.id)
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
        let rows = day.efforts.filter { stripProviders.contains($0.provider) }.sorted { $0.tokens > $1.tokens }
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
        guard !showingDetails, !model.isLoading, (day.date <= today || !resetsOn(day).isEmpty),
            model.selectedDayKey != day.id
        else { return }
        withAnimation(motion) { model.selectedDayKey = day.id }
    }

    private func summary(_ day: HistoryCalendarDay) -> String {
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(locale))
        let totals = providers.map { provider in
            name(provider) + " " + (day.tokens(for: provider).map(exact) ?? "history.unknown".localized)
        }.joined(separator: " · ")
        return date + ": " + totals + resetsOn(day).map { " · " + $0.label }.joined()
    }

    private var streakLine: String {
        let streak = model.streak(for: providers)
        return "history.streak".localized(String(streak.current), String(streak.longest))
    }

    private func exact(_ tokens: Int) -> String { tokens.formatted(.number.locale(locale)) }
    private func color(_ provider: UsageProvider) -> Color { provider == .claude ? Theme.claude : Theme.codex }
    private func name(_ provider: UsageProvider) -> String {
        (provider == .claude ? "provider.claude_short" : "provider.codex").localized
    }
}

private enum HistoryFrame {
    case panel
    case calendar
    case summary
}

private struct HistoryFrameKey: PreferenceKey {
    static let defaultValue: [HistoryFrame: CGRect] = [:]
    static func reduce(value: inout [HistoryFrame: CGRect], nextValue: () -> [HistoryFrame: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct HistoryDayCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
