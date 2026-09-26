import Foundation
import TokenGaugeCore

struct StatsSegment: Identifiable, Equatable, Sendable {
    let id: String
    let tokens: Int
    let provider: UsageProvider
    let rank: Int
}

struct StatsDayTotal: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let total: Int?
    let segments: [StatsSegment]
}

struct StatsRankItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: Int
    let provider: UsageProvider?
}

struct StatsPeak: Equatable, Sendable {
    let date: Date
    let tokens: Int
}

struct StatsTurns: Equatable, Sendable {
    let todayMilliseconds: Int
    let todayCount: Int
    let longestMilliseconds: Int
}

enum StatsInsight: Equatable, Sendable {
    case newModel(String)
    case spike(Double)
    case quiet(Double)
    case steady(Double)
}

struct StatsSummary: Equatable, Sendable {
    var today: Int?
    var typicalDay: Int?
    var week = 0
    var previousWeek: Int?
    var month = 0
    var previousMonth: Int?
    var lifetime = 0
    var since: Date?
    var peak: StatsPeak?
    var activeDays = 0
    var streak = HistoryStreak()
    var recent: [StatsDayTotal] = []
    var legend: [StatsSegment] = []
    var models: [StatsRankItem] = []
    var efforts: [StatsRankItem] = []
    var skills: [StatsRankItem] = []
    var turns: StatsTurns?
    var cachedShare: Double?
    var insight: StatsInsight?

    static let recentDays = 14
    static let typicalWindow = 28
    static let rankingDays = 7
    static let skillDays = 30

    var ratio: Double? {
        guard let today, let typicalDay, typicalDay > 0 else { return nil }
        return Double(today) / Double(typicalDay)
    }

    struct Input: Sendable {
        var days: [HistoryCalendarDay]
        var tokens: [HistoryTokenRow]
        var efforts: [HistoryEffortRow]
        var activity: [HistoryActivityRow] = []
        var cached: [HistoryCachedRow] = []
        var codexSummary: UsageSummary?
    }

    @MainActor static func make(
        _ input: Input, providers: [UsageProvider], now: Date = Date(), calendar base: Calendar = .current
    ) -> StatsSummary {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let today = calendar.startOfDay(for: now)
        let todayKey = HistoryDashboardModel.dayKey(today)
        let days = input.days.filter { $0.date <= today }
        let totals = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0.total(for: providers)) })
        func key(_ offset: Int, from date: Date = today) -> String {
            HistoryDashboardModel.dayKey(calendar.date(byAdding: .day, value: offset, to: date) ?? date)
        }
        func sum(_ keys: [String]) -> Int? {
            let values = keys.compactMap { totals[$0] ?? nil }
            return values.isEmpty ? nil : values.reduce(0, &+)
        }

        var summary = StatsSummary()
        summary.today = totals[todayKey] ?? nil

        let previous = (1...typicalWindow).compactMap { totals[key(-$0)] ?? nil }.filter { $0 > 0 }.sorted()
        if previous.count >= 3 { summary.typicalDay = previous[previous.count / 2] }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weekElapsed = (calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0) + 1
        summary.week = sum((0..<weekElapsed).map { key($0, from: weekStart) }) ?? 0
        let coverage = providers.compactMap { provider in days.first { $0.tokens(for: provider) != nil }?.date }
        let covered = coverage.count == providers.count ? coverage.max() : nil
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        if let covered, covered <= lastWeekStart {
            summary.previousWeek = sum((0..<weekElapsed).map { key($0, from: lastWeekStart) })
        }

        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let monthElapsed = (calendar.dateComponents([.day], from: monthStart, to: today).day ?? 0) + 1
        summary.month = sum((0..<monthElapsed).map { key($0, from: monthStart) }) ?? 0
        if let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart), let covered,
            covered <= lastMonthStart
        {
            let lastMonthLength = calendar.range(of: .day, in: .month, for: lastMonthStart)?.count ?? 30
            summary.previousMonth = sum((0..<min(monthElapsed, lastMonthLength)).map { key($0, from: lastMonthStart) })
        }

        let recorded = days.filter { $0.total(for: providers) != nil }
        summary.lifetime = recorded.compactMap { $0.total(for: providers) }.reduce(0, &+)
        summary.since = recorded.first?.date
        if let best = recorded.max(by: { ($0.total(for: providers) ?? 0) < ($1.total(for: providers) ?? 0) }),
            let tokens = best.total(for: providers), tokens > 0
        {
            summary.peak = StatsPeak(date: best.date, tokens: tokens)
        }
        if providers.contains(.codex), let codex = input.codexSummary {
            let local = days.compactMap { $0.tokens(for: .codex) }.reduce(0, &+)
            if let lifetime = codex.lifetimeTokens, lifetime > local { summary.lifetime += lifetime - local }
            if providers == [.codex], let peak = codex.peakDailyTokens, peak > (summary.peak?.tokens ?? 0) {
                summary.peak = StatsPeak(date: summary.peak?.date ?? today, tokens: peak)
            }
        }
        let usageDays = Set(recorded.filter { ($0.total(for: providers) ?? 0) > 0 }.map(\.id))
        summary.activeDays = usageDays.count
        let streak = HistoryAnalytics.streaks(usageDays: usageDays, today: todayKey, calendar: calendar)
        summary.streak = HistoryStreak(current: streak.current, longest: streak.longest)

        let modelRows = modelTokens(input, providers: providers)
        let rankingKeys = Set((0..<rankingDays).map { key(-$0) })
        summary.models = rank(modelRows.filter { rankingKeys.contains($0.day) }, limit: 5)
        summary.efforts = rank(
            input.efforts.filter { providers.contains($0.provider) && rankingKeys.contains($0.day) }.map {
                LabeledTokens(day: $0.day, label: effortLabel($0.effort), provider: nil, tokens: $0.tokens)
            }, limit: 4)

        let recentDates = (0..<recentDays).reversed().map {
            calendar.date(byAdding: .day, value: -$0, to: today) ?? today
        }
        let recentKeys = recentDates.map { HistoryDashboardModel.dayKey($0) }
        let recentSet = Set(recentKeys)
        let segmentRows: [LabeledTokens] =
            providers.count > 1
            ? recentKeys.flatMap { day in
                providers.compactMap { provider in
                    days.first { $0.id == day }?.tokens(for: provider).map {
                        LabeledTokens(day: day, label: provider.rawValue, provider: provider, tokens: $0)
                    }
                }
            }
            : modelRows.filter { recentSet.contains($0.day) }
        let leaders = rank(segmentRows, limit: providers.count > 1 ? 2 : 3)
        let leaderIndex = Dictionary(uniqueKeysWithValues: leaders.enumerated().map { ($1.id, $0) })
        let fallback = providers.first ?? .claude
        summary.legend = leaders.enumerated().map { index, item in
            StatsSegment(id: item.id, tokens: item.value, provider: item.provider ?? fallback, rank: index)
        }
        summary.recent = zip(recentKeys, recentDates).map { day, date in
            let total = totals[day] ?? nil
            var buckets: [String: Int] = [:]
            for row in segmentRows where row.day == day {
                buckets[leaderIndex[row.label] != nil ? row.label : otherLabel, default: 0] += row.tokens
            }
            let assigned = buckets.values.reduce(0, &+)
            if let total, total > assigned { buckets[otherLabel, default: 0] += total - assigned }
            let segments = buckets.filter { $0.value > 0 }.map { label, tokens in
                StatsSegment(
                    id: label, tokens: tokens, provider: leaders.first { $0.id == label }?.provider ?? fallback,
                    rank: leaderIndex[label] ?? leaders.count)
            }.sorted { $0.rank < $1.rank }
            return StatsDayTotal(id: day, date: date, total: total, segments: segments)
        }

        let skillKeys = Set((0..<skillDays).map { key(-$0) })
        summary.skills = rank(
            input.activity.filter { $0.kind == .skill && providers.contains($0.provider) && skillKeys.contains($0.day) }
                .map { LabeledTokens(day: $0.day, label: $0.key, provider: $0.provider, tokens: $0.count) },
            limit: 6)
        let turns = input.activity.filter { $0.kind == .turn && providers.contains($0.provider) }
        let recentTurns = turns.filter { skillKeys.contains($0.day) }
        if !recentTurns.isEmpty {
            let todayTurns = turns.filter { $0.day == todayKey }
            summary.turns = StatsTurns(
                todayMilliseconds: todayTurns.map(\.total).reduce(0, &+),
                todayCount: todayTurns.map(\.count).reduce(0, &+),
                longestMilliseconds: recentTurns.map(\.maximum).max() ?? 0)
        }
        let cached = input.cached.filter { providers.contains($0.provider) && rankingKeys.contains($0.day) }
        let cachedTotal = cached.map(\.tokens).reduce(0, &+)
        if cachedTotal > 0 {
            summary.cachedShare = Double(cached.map(\.cachedTokens).reduce(0, &+)) / Double(cachedTotal)
        }

        summary.insight = insight(
            summary, modelRows: modelRows, todayKey: todayKey, firstDay: recorded.first?.id, now: now,
            calendar: calendar)
        return summary
    }

    static let otherLabel = "other"

    private struct LabeledTokens {
        let day: String
        let label: String
        let provider: UsageProvider?
        let tokens: Int
    }

    @MainActor private static func modelTokens(_ input: Input, providers: [UsageProvider]) -> [LabeledTokens] {
        var rows: [LabeledTokens] = []
        if providers.contains(.claude) {
            rows += input.tokens.filter { $0.provider == .claude && $0.model != "all" && $0.tokens > 0 }.map {
                LabeledTokens(day: $0.day, label: $0.model, provider: .claude, tokens: $0.tokens)
            }
        }
        if providers.contains(.codex) {
            rows += input.efforts.filter { $0.provider == .codex && $0.tokens > 0 }.map {
                LabeledTokens(day: $0.day, label: $0.model, provider: .codex, tokens: $0.tokens)
            }
        }
        return rows.map {
            LabeledTokens(day: $0.day, label: modelLabel($0.label), provider: $0.provider, tokens: $0.tokens)
        }
    }

    private static func rank(_ rows: [LabeledTokens], limit: Int) -> [StatsRankItem] {
        var totals: [String: (Int, UsageProvider?)] = [:]
        for row in rows {
            let current = totals[row.label]
            totals[row.label] = ((current?.0 ?? 0) &+ row.tokens, current?.1 ?? row.provider)
        }
        let items: [StatsRankItem] = totals.compactMap { key, value in
            value.0 > 0 ? StatsRankItem(id: key, label: key, value: value.0, provider: value.1) : nil
        }
        let sorted = items.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.label < rhs.label : lhs.value > rhs.value
        }
        return Array(sorted.prefix(limit))
    }

    private static func insight(
        _ summary: StatsSummary, modelRows: [LabeledTokens], todayKey: String, firstDay: String?, now: Date,
        calendar: Calendar
    ) -> StatsInsight? {
        let firstSeen = Dictionary(grouping: modelRows, by: \.label).compactMapValues { $0.map(\.day).min() }
        let recentCutoff = HistoryDashboardModel.dayKey(calendar.date(byAdding: .day, value: -2, to: now) ?? now)
        let historyCutoff = HistoryDashboardModel.dayKey(calendar.date(byAdding: .day, value: -9, to: now) ?? now)
        if let firstDay, firstDay <= historyCutoff,
            let newest = firstSeen.filter({ $0.value >= recentCutoff && $0.key != otherLabel })
                .max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })
        {
            return .newModel(newest.key)
        }
        guard let ratio = summary.ratio else { return nil }
        if ratio >= 1.8 { return .spike(ratio) }
        if ratio <= 0.4, calendar.component(.hour, from: now) >= 15 { return .quiet(ratio) }
        return .steady(ratio)
    }

    @MainActor private static func modelLabel(_ raw: String) -> String {
        ModelActivity.displayName(raw)
    }

    @MainActor static func effortLabel(_ raw: String) -> String {
        switch raw {
        case "unknown": return "history.effort_unknown".localized
        case "xhigh": return "XHigh"
        default: return raw.capitalized
        }
    }
}
