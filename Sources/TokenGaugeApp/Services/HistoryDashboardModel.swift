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

@MainActor
final class HistoryDashboardModel: ObservableObject {
    @Published var offset = 0
    @Published var selectedDayKey: String?
    @Published private(set) var days: [HistoryCalendarDay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadedMode: HistoryMode?
    @Published private(set) var loadFailed = false
    @Published private(set) var periodStart = Date()
    @Published private(set) var periodEnd = Date()
    @Published private(set) var firstRecordedDay: String?
    @Published private(set) var paces: [String: QuotaPace] = [:]
    private var generation = UUID()
    private let previewEfforts: [HistoryEffortRow]
    private var cachedReads: [String: ReadResult] = [:]
    private var cacheOrder: [String] = []
    private var cacheRevision: Int?

    init(
        previewSnapshots: [ProviderUsageSnapshot]? = nil, mode: HistoryMode = .recent,
        previewEfforts: [HistoryEffortRow] = [], now: Date = Date()
    ) {
        self.previewEfforts = previewEfforts
        if let snapshots = previewSnapshots {
            let interval = Self.interval(mode: mode, offset: 0, now: now)
            let rows = snapshots.flatMap { snapshot in
                snapshot.dailyUsage.map {
                    HistoryTokenRow(day: $0.day, provider: snapshot.provider, model: "all", tokens: $0.tokens)
                }
            }
            days = Self.makeDays(interval: interval, tokens: rows, efforts: previewEfforts)
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

    func pace(provider: UsageProvider, window: QuotaWindow) -> QuotaPace? {
        Self.usablePace(paces[provider.rawValue + ":" + window.id], for: window)
    }

    static func usablePace(_ pace: QuotaPace?, for window: QuotaWindow, now: Date = Date()) -> QuotaPace? {
        guard let pace, let reset = pace.resetsAt, reset == window.resetsAt, reset > now,
            let used = pace.lastUsedPercentage, window.usedPercentage.isFinite, window.usedPercentage >= used,
            window.durationMinutes == 10080, now.timeIntervalSince(pace.sampledAt) >= 0,
            now.timeIntervalSince(pace.sampledAt) <= 1200
        else { return nil }
        return pace
    }

    func load(mode: HistoryMode, revision: Int, previewSnapshots: [ProviderUsageSnapshot]? = nil) async {
        let request = UUID()
        generation = request
        isLoading = true
        loadFailed = false
        let now = Date()
        let interval = Self.interval(mode: mode, offset: offset, now: now)
        let first = Self.dayKey(interval.start)
        let last = Self.dayKey(interval.end.addingTimeInterval(-1))
        if cacheRevision != revision {
            cachedReads.removeAll(keepingCapacity: true)
            cacheOrder.removeAll(keepingCapacity: true)
            cacheRevision = revision
        }
        let cacheKey = first + ":" + last
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
                    quotas: [], first: rows.map(\.day).min())
            } else {
                result = try await Task.detached(priority: .utility) {
                    let tokens = try UsageHistoryStore.tokenRows(since: first, through: last)
                    let efforts = try UsageHistoryStore.effortRows(since: first, through: last)
                    return ReadResult(
                        days: Self.makeDays(interval: interval, tokens: tokens, efforts: efforts),
                        quotas: try UsageHistoryStore.quotaRows(since: now.addingTimeInterval(-7200), until: now),
                        first: try UsageHistoryStore.bounds().firstDay)
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
            loadedMode = mode
            var values: [String: QuotaPace] = [:]
            for row in result.quotas where row.durationMinutes == 10080 {
                let key = row.provider.rawValue + ":" + row.windowID
                if values[key] == nil {
                    values[key] = HistoryAnalytics.pace(
                        rows: result.quotas, provider: row.provider, windowID: row.windowID, now: now)
                }
            }
            paces = values
            if !days.contains(where: { $0.id == selectedDayKey }) { selectedDayKey = nil }
            isLoading = false
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            loadFailed = true
            isLoading = false
            paces = [:]
            days = []
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

    nonisolated static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        dayFormatter(calendar: calendar).string(from: date)
    }

    nonisolated private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    nonisolated static func makeDays(
        interval: DateInterval, tokens: [HistoryTokenRow], efforts: [HistoryEffortRow], calendar: Calendar = .current
    ) -> [HistoryCalendarDay] {
        let tokenDays = Dictionary(grouping: tokens, by: \.day)
        let effortDays = Dictionary(grouping: efforts, by: \.day)
        let formatter = dayFormatter(calendar: calendar)
        var date = interval.start
        var result: [HistoryCalendarDay] = []
        while date < interval.end {
            let key = formatter.string(from: date)
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

    nonisolated private static func sum(_ values: [Int]) -> Int {
        values.reduce(0) { partial, value in
            let addition = partial.addingReportingOverflow(value)
            return addition.overflow ? Int.max : addition.partialValue
        }
    }

    private struct ReadResult: Sendable {
        let days: [HistoryCalendarDay]
        let quotas: [HistoryQuotaRow]
        let first: String?
    }
}
