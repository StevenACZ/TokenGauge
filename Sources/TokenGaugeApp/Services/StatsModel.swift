import Combine
import Foundation
import TokenGaugeCore

@MainActor
final class StatsModel: ObservableObject {
    struct Records: Sendable {
        var input: StatsSummary.Input
        var quota: [HistoryQuotaRow]
        var weeklyQuota: [HistoryQuotaRow] = []
    }

    @Published private(set) var records: Records?
    @Published private(set) var loadFailed = false
    @Published private(set) var isLoading = false
    private var loadedRevision: Int?
    private var summaries: [String: StatsSummary] = [:]
    private var pastSessions: [String: [PastQuotaSession]] = [:]
    private let historyURL: URL
    private let preview: Records?

    nonisolated static let quotaLookback: TimeInterval = 8 * 86_400
    nonisolated static let weeklyLookback: TimeInterval = 84 * 86_400

    init(preview: Records? = nil, historyURL: URL = UsagePaths.history()) {
        self.preview = preview
        self.historyURL = historyURL
        records = preview
    }

    func summary(for providers: [UsageProvider], codexSummary: UsageSummary?) -> StatsSummary? {
        guard var records else { return nil }
        let key = providers.map(\.rawValue).joined(separator: "+")
        if let cached = summaries[key] { return cached }
        records.input.codexSummary = codexSummary
        let value = StatsSummary.make(records.input, providers: providers)
        summaries[key] = value
        return value
    }

    func forecasts(for states: [(UsageProvider, [QuotaWindow])], accountFingerprint: String?, now: Date = Date())
        -> [QuotaForecast]
    {
        let rows = records?.quota ?? []
        return states.flatMap { provider, windows in
            windows.filter { [300, 10_080].contains($0.durationMinutes) }.compactMap { window in
                QuotaForecast.make(
                    provider: provider, window: window, rows: rows, now: now,
                    accountFingerprint: provider == .claude ? accountFingerprint : nil)
            }
        }
    }

    func pastSessions(like forecast: QuotaForecast, accountFingerprint: String?) -> [PastQuotaSession] {
        guard let records else { return [] }
        let key = "\(forecast.id)@\(Int(forecast.reset.timeIntervalSince1970 / 3600))"
        if let cached = pastSessions[key] { return cached }
        let value = PastQuotaSession.history(
            like: forecast, rows: forecast.isSession ? records.quota : records.weeklyQuota,
            accountFingerprint: forecast.provider == .claude ? accountFingerprint : nil,
            gradesCalls: forecast.isSession)
        pastSessions[key] = value
        return value
    }

    func load(revision: Int) async {
        guard preview == nil, loadedRevision != revision || records == nil else { return }
        isLoading = true
        let url = historyURL
        let now = Date()
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try Self.read(url: url, now: now)
            }.value
            guard !Task.isCancelled else { return }
            summaries.removeAll()
            pastSessions.removeAll()
            records = loaded
            loadedRevision = revision
            loadFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = records == nil
        }
        isLoading = false
    }

    static func preview(snapshots: [ProviderUsageSnapshot]) -> Records {
        let rows = snapshots.flatMap { snapshot in
            snapshot.dailyUsage.map {
                HistoryTokenRow(day: $0.day, provider: snapshot.provider, model: "all", tokens: $0.tokens)
            }
        }
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -(StatsSummary.recentDays - 1), to: today) ?? today
        let interval = DateInterval(
            start: start, end: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
        return Records(
            input: StatsSummary.Input(
                days: HistoryDashboardModel.makeDays(interval: interval, tokens: rows, efforts: []), tokens: rows,
                efforts: []),
            quota: [])
    }

    nonisolated static func read(url: URL, now: Date) throws -> Records {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tokens = try UsageHistoryStore.tokenRows(at: url)
        let efforts = try UsageHistoryStore.effortRows(at: url)
        let firstKey = try UsageHistoryStore.bounds(at: url).firstDay
        let recentStart = calendar.date(byAdding: .day, value: -(StatsSummary.recentDays - 1), to: today) ?? today
        let first = firstKey.flatMap(date(from:)).map { min($0, recentStart) } ?? recentStart
        let interval = DateInterval(start: first, end: calendar.date(byAdding: .day, value: 1, to: today) ?? now)
        let since = HistoryDashboardModel.dayKey(
            calendar.date(byAdding: .day, value: -StatsSummary.skillDays, to: today) ?? today)
        return Records(
            input: StatsSummary.Input(
                days: HistoryDashboardModel.makeDays(interval: interval, tokens: tokens, efforts: efforts),
                tokens: tokens, efforts: efforts,
                activity: (try? UsageHistoryStore.activityRows(since: since, at: url)) ?? [],
                cached: (try? UsageHistoryStore.cachedTokenRows(since: since, at: url)) ?? []),
            quota: try UsageHistoryStore.quotaRows(since: now.addingTimeInterval(-quotaLookback), until: now, at: url),
            weeklyQuota: (try? UsageHistoryStore.quotaRows(
                since: now.addingTimeInterval(-weeklyLookback), until: now, durationMinutes: 10_080,
                everySeconds: 3600, at: url)) ?? [])
    }

    nonisolated private static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
