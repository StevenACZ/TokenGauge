import Foundation
import TokenGaugeCore

enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TOKENGAUGE_DEMO"] == "1"
            && Bundle.main.object(forInfoDictionaryKey: "TokenGaugeDevelopmentBuild") as? Bool ?? true
    }

    static let accountLabel = "you@example.com"
    static let defaultsSuite = "com.stevenacz.TokenGauge.demo"

    static var historyURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "TokenGauge-demo/usage-history.sqlite")
    }

    private struct Limit {
        let id: String
        let name: String?
        let minutes: Int
        let resetsIn: TimeInterval
        let used: Double
    }

    private static let limits: [UsageProvider: [Limit]] = [
        .claude: [
            Limit(id: "five_hour", name: nil, minutes: 300, resetsIn: 2 * 3600, used: 38),
            Limit(id: "seven_day", name: nil, minutes: 10_080, resetsIn: 57 * 3600, used: 61),
            Limit(id: "seven_day_fable", name: "Fable", minutes: 10_080, resetsIn: 57 * 3600, used: 42),
        ],
        .codex: [
            Limit(id: "codex.primary", name: nil, minutes: 300, resetsIn: 3.5 * 3600, used: 21),
            Limit(id: "codex.secondary", name: nil, minutes: 10_080, resetsIn: 116 * 3600, used: 34),
        ],
    ]

    private static let models: [UsageProvider: [(String, Int)]] = [
        .claude: [("claude-opus-5-5", 58), ("claude-fable-5-1", 25), ("claude-sonnet-5", 13), ("claude-haiku-4-5", 4)],
        .codex: [("gpt-5.3-codex", 78), ("gpt-5.2", 22)],
    ]

    private static let efforts: [UsageProvider: [(String, Int)]] = [
        .claude: [("high", 40), ("xhigh", 27), ("medium", 21), ("max", 12)],
        .codex: [("medium", 46), ("high", 34), ("xhigh", 20)],
    ]

    private static let skills: [UsageProvider: [String]] = [
        .claude: ["code-review", "release-notes", "test-runner", "docs-writer", "ui-polish"],
        .codex: ["code-review", "test-runner", "refactor"],
    ]

    private static let historyDays = 240
    private static let restDays: Set<Int> = [33, 61, 62, 97, 130, 131, 188]

    @MainActor
    static func makeStore(now: Date = Date()) -> UsageStore {
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? UserDefaults.standard
        let snapshots = snapshots(now: now)
        try? seed(snapshots: snapshots, at: historyURL, now: now)
        let store = UsageStore(
            defaults: defaults, initialSnapshots: snapshots, historyReadsEnabled: true, historyURL: historyURL,
            liveReadsEnabled: false)
        store.setPreviewAccountLabel(accountLabel)
        if !defaults.bool(forKey: "demo.prepared") {
            defaults.set(true, forKey: "demo.prepared")
            store.showHourlyPace = true
            for kind in QuotaWindowKind.allCases { store.setClaudeWindow(kind, visible: true) }
        }
        return store
    }

    static func snapshots(now: Date) -> [ProviderUsageSnapshot] {
        UsageProvider.allCases.map { provider in
            ProviderUsageSnapshot(
                provider: provider, windows: windows(provider, at: now, now: now), dailyUsage: [],
                summary: provider == .codex
                    ? UsageSummary(
                        lifetimeTokens: 6_420_000_000, peakDailyTokens: 212_000_000, longestRunningTurnSeconds: 2_140,
                        currentStreakDays: 23, longestStreakDays: 41)
                    : nil,
                availableResetCredits: nil, creditBalance: nil, capturedAt: now)
        }
    }

    static func seed(snapshots: [ProviderUsageSnapshot], at url: URL, now: Date) throws {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for provider in UsageProvider.allCases {
            for sampledAt in sampleTimes(provider, now: now) {
                let windows = windows(provider, at: sampledAt, now: now)
                guard !windows.isEmpty else { continue }
                try UsageHistoryStore.record(
                    ProviderUsageSnapshot(
                        provider: provider, windows: windows, dailyUsage: [], summary: nil, availableResetCredits: nil,
                        creditBalance: nil, capturedAt: sampledAt),
                    at: url, now: sampledAt, recordTokens: false)
            }
            try UsageHistoryStore.record(
                ProviderUsageSnapshot(
                    provider: provider, windows: [], dailyUsage: [], summary: nil, availableResetCredits: nil,
                    creditBalance: nil, capturedAt: now, modelBuckets: buckets(provider, now: now)),
                at: url, now: now, recordQuota: false)
        }
        let (effortRecords, activityRecords) = events(now: now)
        try UsageHistoryStore.recordEffort(effortRecords, activity: activityRecords, at: url)
    }

    private static func resetDate(_ limit: Limit, now: Date) -> Date {
        let reset = now.addingTimeInterval(limit.resetsIn)
        return Date(timeIntervalSince1970: (reset.timeIntervalSince1970 / 3600).rounded(.up) * 3600)
    }

    private static func windows(_ provider: UsageProvider, at time: Date, now: Date) -> [QuotaWindow] {
        (limits[provider] ?? []).compactMap { limit in
            let reset = resetDate(limit, now: now)
            let start = reset.addingTimeInterval(-Double(limit.minutes) * 60)
            guard time > start else { return nil }
            return QuotaWindow(
                id: limit.id, usedPercentage: used(limit, start: start, at: time, now: now), resetsAt: reset,
                durationMinutes: limit.minutes, displayName: limit.name)
        }
    }

    private static func sampleTimes(_ provider: UsageProvider, now: Date) -> [Date] {
        let longest = (limits[provider] ?? []).map {
            resetDate($0, now: now).addingTimeInterval(-Double($0.minutes) * 60)
        }
        guard let first = longest.min() else { return [] }
        return stride(
            from: now.timeIntervalSince1970, to: first.timeIntervalSince1970, by: -UsageHistoryStore.sampleInterval
        )
        .reversed().map(Date.init(timeIntervalSince1970:))
    }

    private static func used(_ limit: Limit, start: Date, at time: Date, now: Date) -> Double {
        let total = effort(limit, from: start, to: now)
        guard total > 0 else { return 0 }
        let value = limit.used * effort(limit, from: start, to: time) / total
        return (value * 100).rounded() / 100
    }

    private static func effort(_ limit: Limit, from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        guard limit.minutes > 300 else { return end.timeIntervalSince(start) }
        let calendar = Calendar.current
        var total = 0.0
        var cursor = start
        while cursor < end {
            let next = min(end, cursor.addingTimeInterval(1800))
            let hour = calendar.component(.hour, from: cursor)
            let day = calendar.ordinality(of: .day, in: .era, for: cursor) ?? 0
            let weight = (9..<23).contains(hour) ? 0.7 + noise(day) * 0.8 : 0.05
            total += weight * next.timeIntervalSince(cursor)
            cursor = next
        }
        return total
    }

    private static func dayTokens(_ provider: UsageProvider, offset: Int, date: Date) -> Int {
        guard !restDays.contains(offset) else { return 0 }
        let weekend = Calendar.current.isDateInWeekend(date)
        let base: Double = provider == .claude ? 190_000_000 : 46_000_000
        let wave = 0.55 + noise(offset * (provider == .claude ? 3 : 7) + 11) * 1.1
        let season = 0.75 + Double(historyDays - offset) / Double(historyDays) * 0.45
        let scale = offset == 0 ? 0.72 : weekend ? 0.3 : 1
        return Int(base * wave * season * scale)
    }

    private static func buckets(_ provider: UsageProvider, now: Date) -> [ModelTokenBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<historyDays).flatMap { offset -> [ModelTokenBucket] in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            let total = dayTokens(provider, offset: offset, date: date)
            let key = HistoryDashboardModel.dayKey(date)
            return (models[provider] ?? []).map { model, share in
                ModelTokenBucket(
                    day: key, hourStart: date.addingTimeInterval(13 * 3600), model: model, tokens: total * share / 100)
            }
        }
    }

    private static func events(now: Date) -> ([EffortUsageRecord], [ActivityUsageRecord]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var counter: UInt64 = 0
        func nextID() -> String {
            counter += 1
            return String(format: "%064llx", counter)
        }
        var effortRecords: [EffortUsageRecord] = []
        var activityRecords: [ActivityUsageRecord] = []
        for provider in UsageProvider.allCases {
            let cacheShare = provider == .claude ? 93 : 78
            for offset in 0..<30 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let key = HistoryDashboardModel.dayKey(date)
                let total = dayTokens(provider, offset: offset, date: date)
                guard total > 0, let (model, share) = models[provider]?.first else { continue }
                let midday = min(now, date.addingTimeInterval(12 * 3600))
                for (effort, part) in efforts[provider] ?? [] {
                    let tokens = total * share / 100 * part / 100
                    effortRecords.append(
                        EffortUsageRecord(
                            id: nextID(), provider: provider, recordedAt: midday, day: key, model: model,
                            effort: effort, tokens: tokens, cachedTokens: tokens * cacheShare / 100))
                }
                for (position, skill) in (skills[provider] ?? []).enumerated()
                where (offset + position) % (position + 2) == 0 {
                    for _ in 0..<(5 - position) {
                        activityRecords.append(
                            ActivityUsageRecord(
                                id: nextID(), provider: provider, recordedAt: midday, day: key, kind: .skill,
                                key: skill, value: 1))
                    }
                }
                let turns = provider == .claude ? 14 + offset % 7 : 6 + offset % 4
                for turn in 0..<turns {
                    let minutes = 2 + noise(offset * 31 + turn) * (offset == 0 && turn == 0 ? 24 : 12)
                    activityRecords.append(
                        ActivityUsageRecord(
                            id: nextID(), provider: provider, recordedAt: midday, day: key, kind: .turn, key: "",
                            value: Int(minutes * 60_000)))
                }
            }
        }
        return (effortRecords, activityRecords)
    }

    private static func noise(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 12.9898) * 43_758.5453
        return value - value.rounded(.down)
    }
}
