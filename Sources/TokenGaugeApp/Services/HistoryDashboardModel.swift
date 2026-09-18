import Combine
import Foundation
import TokenGaugeCore

enum HistoryMode: String, CaseIterable, Identifiable {
    case recent
    case week
    case calendar
    var id: String { rawValue }
    var titleKey: String { "history.mode." + rawValue }
}

struct HistoryCalendarDay: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let totals: [UsageProvider: Int]
    let efforts: [HistoryEffortRow]

    func tokens(for provider: UsageProvider) -> Int? { totals[provider] }
    func dominantProviders(for providers: [UsageProvider]) -> [UsageProvider] {
        let observed = providers.filter { (totals[$0] ?? 0) > 0 }
        guard let maximum = observed.compactMap({ totals[$0] }).max() else { return [] }
        return observed.filter { totals[$0] == maximum }
    }

    func total(for providers: [UsageProvider]) -> Int? {
        let values = providers.compactMap { totals[$0] }
        return values.isEmpty
            ? nil
            : values.reduce(0) { partial, value in
                let result = partial.addingReportingOverflow(value)
                return result.overflow ? Int.max : result.partialValue
            }
    }
}

// Rects relative to the calendar view's top-left corner; `bounds` is the popover root, so it may start negative.
struct HistoryDayCardAnchor: Equatable, Sendable {
    var cell: CGRect
    var bounds: CGRect
}

struct HistoryDaySelection: Equatable, Sendable {
    var dayKey: String
    var isPinned: Bool
    var anchor: HistoryDayCardAnchor?
}

struct HistoryUsageDays: Equatable, Sendable {
    var claude: Set<String> = []
    var codex: Set<String> = []
    var any: Set<String> { claude.union(codex) }

    func days(for providers: [UsageProvider]) -> Set<String> {
        if providers == [.claude] { return claude }
        if providers == [.codex] { return codex }
        return any
    }
}

struct HistoryStreak: Equatable, Sendable {
    var current = 0
    var longest = 0
}

struct HistoryStreaks: Equatable, Sendable {
    var claude = HistoryStreak()
    var codex = HistoryStreak()
    var unified = HistoryStreak()

    init() {}

    init(usageDays: HistoryUsageDays, today: String, calendar: Calendar = .current) {
        claude = Self.streak(usageDays.claude, today: today, calendar: calendar)
        codex = Self.streak(usageDays.codex, today: today, calendar: calendar)
        unified = Self.streak(usageDays.any, today: today, calendar: calendar)
    }

    func streak(for providers: [UsageProvider]) -> HistoryStreak {
        if providers == [.claude] { return claude }
        if providers == [.codex] { return codex }
        return unified
    }

    private static func streak(_ days: Set<String>, today: String, calendar: Calendar) -> HistoryStreak {
        let value = HistoryAnalytics.streaks(usageDays: days, today: today, calendar: calendar)
        return HistoryStreak(current: value.current, longest: value.longest)
    }
}

@MainActor
final class HistoryDashboardModel: ObservableObject {
    @Published var offset = 0
    @Published var selectedDayKey: String?
    @Published var daySelection: HistoryDaySelection?
    @Published private(set) var usageDays = HistoryUsageDays()
    @Published private(set) var streaks = HistoryStreaks()
    @Published private(set) var days: [HistoryCalendarDay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadedMode: HistoryMode?
    @Published private(set) var loadFailed = false
    @Published private(set) var periodStart = Date()
    @Published private(set) var periodEnd = Date()
    @Published private(set) var firstRecordedDay: String?
    @Published private(set) var paces: [String: QuotaPace] = [:]
    private var generation = UUID()
    private var savedPaces: [String: [QuotaPace]] = [:]
    private var paceActivity: [String: Bool] = [:]
    private let previewEfforts: [HistoryEffortRow]
    private let historyURL: URL
    private var cachedReads: [String: ReadResult] = [:]
    private var cacheOrder: [String] = []
    private var cacheRevision: Int?

    init(
        previewSnapshots: [ProviderUsageSnapshot]? = nil, mode: HistoryMode = .recent,
        previewEfforts: [HistoryEffortRow] = [], now: Date = Date(), historyURL: URL = UsagePaths.history()
    ) {
        self.previewEfforts = previewEfforts
        self.historyURL = historyURL
        if let snapshots = previewSnapshots {
            let interval = Self.interval(mode: mode, offset: 0, now: now)
            let rows = snapshots.flatMap { snapshot in
                snapshot.dailyUsage.map {
                    HistoryTokenRow(day: $0.day, provider: snapshot.provider, model: "all", tokens: $0.tokens)
                }
            }
            days = Self.makeDays(interval: interval, tokens: rows, efforts: previewEfforts)
            usageDays = Self.usageDays(tokens: rows)
            streaks = HistoryStreaks(usageDays: usageDays, today: Self.dayKey(now))
            loadedMode = mode
            periodStart = interval.start
            periodEnd = interval.end
            firstRecordedDay = rows.map(\.day).min()
        }
    }

    var selectedDay: HistoryCalendarDay? {
        days.first { $0.id == selectedDayKey }
            ?? days.last { $0.date <= Date() }
    }

    var canGoBack: Bool {
        guard let firstRecordedDay else { return false }
        return Self.dayKey(periodStart) > firstRecordedDay
    }

    var canGoForward: Bool { offset < 0 }

    func move(_ direction: Int) {
        guard direction < 0 ? canGoBack : canGoForward else { return }
        offset = min(0, offset + direction)
        selectedDayKey = nil
    }

    func streak(for providers: [UsageProvider]) -> HistoryStreak {
        streaks.streak(for: providers)
    }

    func showDayCard(_ dayKey: String, anchor: HistoryDayCardAnchor?) {
        guard daySelection?.isPinned != true else { return }
        daySelection = HistoryDaySelection(dayKey: dayKey, isPinned: false, anchor: anchor)
    }

    func hideDayCard() {
        guard let selection = daySelection, !selection.isPinned else { return }
        daySelection = nil
    }

    func pinDayCard(_ dayKey: String, anchor: HistoryDayCardAnchor?) {
        if let current = daySelection, current.isPinned, current.dayKey == dayKey {
            daySelection = nil
            return
        }
        daySelection = HistoryDaySelection(dayKey: dayKey, isPinned: true, anchor: anchor)
    }

    func dismissDayCard() {
        guard daySelection != nil else { return }
        daySelection = nil
    }

    func popoverDidClose() {
        daySelection = nil
        selectedDayKey = nil
    }

    func pace(provider: UsageProvider, window: QuotaWindow, capturedAt: Date?) -> QuotaPace? {
        let key = provider.rawValue + ":" + window.id
        guard let current = Self.usablePace(paces[key], for: window, capturedAt: capturedAt)
        else { return nil }
        if current.pointsPerHour > 0 && paceActivity[key] != true { return nil }
        return current
    }

    func retainedPace(provider: UsageProvider, windowID: String, excluding current: QuotaPace?) -> QuotaPace? {
        let saved = savedPaces[provider.rawValue + ":" + windowID] ?? []
        guard let current, current.pointsPerHour > 0 else { return saved.first }
        return saved.first { $0.sampledAt < current.sampledAt.addingTimeInterval(-0.001) }
    }

    static func usablePace(_ pace: QuotaPace?, for window: QuotaWindow, capturedAt: Date?, now: Date = Date())
        -> QuotaPace?
    {
        guard let pace, pace.sampledAt.timeIntervalSince1970 == capturedAt?.timeIntervalSince1970,
            let reset = pace.resetsAt,
            HistoryAnalytics.sameReset(reset, window.resetsAt), reset > now,
            let used = pace.lastUsedPercentage, window.usedPercentage.isFinite, window.usedPercentage >= used,
            window.durationMinutes == 10080, now.timeIntervalSince(pace.sampledAt) >= 0,
            now.timeIntervalSince(pace.sampledAt) <= 1200
        else { return nil }
        return pace
    }

    func load(
        mode: HistoryMode, revision: Int, previewSnapshots: [ProviderUsageSnapshot]? = nil,
        paceKeys: [HistoryPaceKey] = [], accountFingerprint: String? = nil
    ) async {
        let request = UUID()
        generation = request
        isLoading = true
        loadFailed = false
        let now = Date()
        let interval = Self.interval(mode: mode, offset: offset, now: now)
        let first = Self.dayKey(interval.start)
        let last = Self.dayKey(interval.end.addingTimeInterval(-1))
        let today = Self.dayKey(now)
        if cacheRevision != revision {
            cachedReads.removeAll(keepingCapacity: true)
            cacheOrder.removeAll(keepingCapacity: true)
            cacheRevision = revision
        }
        let cacheKey =
            first + ":" + last + ":" + today + ":" + (accountFingerprint ?? "")
            + ":" + paceKeys.map(\.id).sorted().joined(separator: "|")
        do {
            let result: ReadResult
            if let cached = cachedReads[cacheKey] {
                result = cached
            } else if let snapshots = previewSnapshots {
                let rows = snapshots.flatMap { snapshot in
                    snapshot.dailyUsage.map {
                        HistoryTokenRow(day: $0.day, provider: snapshot.provider, model: "all", tokens: $0.tokens)
                    }
                }
                result = ReadResult(
                    days: Self.makeDays(interval: interval, tokens: rows, efforts: previewEfforts),
                    latest: [], retained: [], first: rows.map(\.day).min(), usage: Self.usageDays(tokens: rows),
                    today: today)
            } else {
                let url = historyURL
                result = try await Task.detached(priority: .utility) {
                    let tokens = try UsageHistoryStore.tokenRows(since: first, through: last, at: url)
                    let efforts = try UsageHistoryStore.effortRows(since: first, through: last, at: url)
                    let usage = try UsageHistoryStore.usageDaysByProvider(at: url)
                    return ReadResult(
                        days: Self.makeDays(interval: interval, tokens: tokens, efforts: efforts),
                        latest: try UsageHistoryStore.recentPaces(
                            for: paceKeys, limitPerWindow: 1, before: now, matchingLatestQuota: true,
                            accountFingerprint: accountFingerprint, at: url),
                        retained: try UsageHistoryStore.recentPaces(
                            for: paceKeys, activeOnly: true, before: now, accountFingerprint: accountFingerprint,
                            at: url),
                        first: try UsageHistoryStore.bounds(at: url).firstDay,
                        usage: HistoryUsageDays(claude: usage[.claude] ?? [], codex: usage[.codex] ?? []),
                        today: today)
                }.value
            }
            guard !Task.isCancelled, generation == request else { return }
            if cachedReads[cacheKey] == nil {
                cachedReads[cacheKey] = result
                cacheOrder.append(cacheKey)
                if cacheOrder.count > 4 { cachedReads.removeValue(forKey: cacheOrder.removeFirst()) }
            }
            periodStart = interval.start
            periodEnd = interval.end
            firstRecordedDay = result.first
            days = result.days
            usageDays = result.usage
            streaks = result.streaks
            loadedMode = mode
            paces = Dictionary(uniqueKeysWithValues: result.latest.map { ($0.key.id, $0.pace) })
            paceActivity = Dictionary(uniqueKeysWithValues: result.latest.map { ($0.key.id, $0.isActive) })
            savedPaces = Dictionary(grouping: result.retained, by: { $0.key.id }).mapValues { $0.map(\.pace) }
            if !days.contains(where: { $0.id == selectedDayKey }) { selectedDayKey = nil }
            isLoading = false
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            loadFailed = true
            isLoading = false
            paces = [:]
            days = []
            usageDays = HistoryUsageDays()
            streaks = HistoryStreaks()
        }
    }

    nonisolated static func interval(mode: HistoryMode, offset: Int, now: Date, calendar: Calendar = .current)
        -> DateInterval
    {
        var calendar = calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let today = calendar.startOfDay(for: now)
        switch mode {
        case .recent:
            return DateInterval(
                start: calendar.date(byAdding: .day, value: -6, to: today)!,
                end: calendar.date(byAdding: .day, value: 1, to: today)!)
        case .week:
            let date = calendar.date(byAdding: .weekOfYear, value: min(0, offset), to: today)!
            return calendar.dateInterval(of: .weekOfYear, for: date)!
        case .calendar:
            let date = calendar.date(byAdding: .year, value: min(0, offset), to: today)!
            return calendar.dateInterval(of: .year, for: date)!
        }
    }

    private nonisolated static var dayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar = dayCalendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    nonisolated static func makeDays(
        interval: DateInterval, tokens: [HistoryTokenRow], efforts: [HistoryEffortRow], calendar: Calendar = .current
    ) -> [HistoryCalendarDay] {
        let tokenDays = Dictionary(grouping: tokens, by: \.day)
        let effortDays = Dictionary(grouping: efforts, by: \.day)
        var date = interval.start
        var result: [HistoryCalendarDay] = []
        while date < interval.end {
            let key = dayKey(date, calendar: calendar)
            var totals: [UsageProvider: Int] = [:]
            for provider in UsageProvider.allCases {
                let rows = (tokenDays[key] ?? []).filter { $0.provider == provider && $0.tokens >= 0 }
                let observed = (effortDays[key] ?? []).filter { $0.provider == provider && $0.tokens >= 0 }
                guard !rows.isEmpty || !observed.isEmpty else { continue }
                let aggregate = rows.filter { $0.model == "all" }.map(\.tokens).max() ?? 0
                let detail = Self.sum(rows.filter { $0.model != "all" }.map(\.tokens))
                totals[provider] = max(aggregate, detail, Self.sum(observed.map(\.tokens)))
            }
            result.append(HistoryCalendarDay(id: key, date: date, totals: totals, efforts: effortDays[key] ?? []))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    nonisolated static func usageDays(tokens: [HistoryTokenRow]) -> HistoryUsageDays {
        let used = tokens.filter { $0.tokens > 0 }
        let claude = Set(used.filter { $0.provider == .claude }.map(\.day))
        let codex = Set(used.filter { $0.provider == .codex }.map(\.day))
        return HistoryUsageDays(claude: claude, codex: codex)
    }

    nonisolated private static func sum(_ values: [Int]) -> Int {
        values.reduce(0) { partial, value in
            let addition = partial.addingReportingOverflow(value)
            return addition.overflow ? Int.max : addition.partialValue
        }
    }

    private struct ReadResult: Sendable {
        let days: [HistoryCalendarDay]
        let latest: [HistoryPaceRow]
        let retained: [HistoryPaceRow]
        let first: String?
        let usage: HistoryUsageDays
        let streaks: HistoryStreaks

        init(
            days: [HistoryCalendarDay], latest: [HistoryPaceRow], retained: [HistoryPaceRow], first: String?,
            usage: HistoryUsageDays, today: String
        ) {
            self.days = days
            self.latest = latest
            self.retained = retained
            self.first = first
            self.usage = usage
            streaks = HistoryStreaks(usageDays: usage, today: today)
        }
    }
}
