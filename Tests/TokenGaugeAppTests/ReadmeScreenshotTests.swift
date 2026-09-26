import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ReadmeScreenshotTests: XCTestCase {
    func testExportAnnualHero() throws {
        guard let directory = ProcessInfo.processInfo.environment["TOKENGAUGE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TOKENGAUGE_SCREENSHOT_DIR to export the README hero")
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let language = LocalizationManager.shared.language
        let previousIcon = NSApplication.shared.applicationIconImage
        let suite = "TokenGauge.readme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            LocalizationManager.shared.language = language
            NSApplication.shared.applicationIconImage = previousIcon
        }
        LocalizationManager.shared.language = .english
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        NSApplication.shared.applicationIconImage = NSImage(
            contentsOf: root.appendingPathComponent("Resources/AppIcon.icns"))
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let codexReset = calendar.date(byAdding: .day, value: 5, to: today)!.addingTimeInterval(18 * 3600)
        let claudeReset = calendar.date(byAdding: .day, value: 2, to: today)!.addingTimeInterval(10 * 3600)
        let snapshots = UsageProvider.allCases.map { provider in
            let activity = (0..<154).map { index in
                let date = calendar.date(byAdding: .day, value: index - 153, to: today)!
                let base = ((index * 17 + 11) % 43 + 5) * 1_000_000
                let share = (index / 11) % 3 == 0 ? 1 : 2
                let amount = provider == .codex ? base * share : ((index * 29 + 7) % 37 + 4) * 1_000_000
                let tokens = index < 126 && index % 45 == 35 ? 0 : amount
                return DailyTokenUsage(day: HistoryDashboardModel.dayKey(date), tokens: tokens)
            }
            let windows: [QuotaWindow] =
                provider == .codex
                ? [Fixture.window(id: "codex.weekly", usedPercentage: 28, resetsAt: codexReset, durationMinutes: 10080)]
                : [
                    Fixture.window(
                        id: "five_hour", usedPercentage: 16, resetsAt: now.addingTimeInterval(3 * 3600),
                        durationMinutes: 300),
                    Fixture.window(id: "seven_day", usedPercentage: 39, resetsAt: claudeReset, durationMinutes: 10080),
                    Fixture.window(
                        id: "seven_day_fable", usedPercentage: 54, resetsAt: claudeReset, durationMinutes: 10080,
                        displayName: "Fable"),
                ]
            return Fixture.snapshot(provider, windows: windows, dailyUsage: activity, capturedAt: now)
        }
        let store = Fixture.store(defaults: defaults, snapshots: snapshots)
        store.displayMode = .unified
        store.panelStyle = .rings
        store.historyMode = .calendar
        store.showLunaReserve = false
        for kind in QuotaWindowKind.allCases { store.setClaudeWindow(kind, visible: true) }
        store.showHourlyPace = false
        store.animateChanges = false
        let history = HistoryDashboardModel(previewSnapshots: snapshots, mode: .calendar, now: now)
        try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}, history: history),
            to: output.appendingPathComponent("readme-year.png"))
    }

    func testExportStats() throws {
        guard let directory = ProcessInfo.processInfo.environment["TOKENGAUGE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TOKENGAUGE_SCREENSHOT_DIR to export the README stats")
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let language = LocalizationManager.shared.language
        let suite = "TokenGauge.readme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            LocalizationManager.shared.language = language
        }
        LocalizationManager.shared.language = .english
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let weeklyReset = today.addingTimeInterval(2 * 86_400 + 10 * 3600)
        let sessionReset = now.addingTimeInterval(2 * 3600 + 40 * 60)
        var days: [HistoryCalendarDay] = []
        var tokens: [HistoryTokenRow] = []
        var efforts: [HistoryEffortRow] = []
        var activity: [HistoryActivityRow] = []
        var cached: [HistoryCachedRow] = []
        let efforts4 = ["high", "xhigh", "medium", "max"]
        let skills = ["code-review", "release-notes", "test-runner", "docs-writer", "ui-polish"]
        for offset in -64...0 {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let key = HistoryDashboardModel.dayKey(date)
            let index = offset + 64
            let weekend = calendar.isDateInWeekend(date)
            let base = ((index * 37 + 13) % 23 + 8) * (weekend ? 4_000_000 : 11_000_000)
            let total = offset == 0 ? 412_000_000 : base
            let split = [
                ("claude-opus-5-5", total * 62 / 100), ("claude-fable-5-1", total * 24 / 100),
                ("claude-sonnet-5", total * 11 / 100), ("claude-haiku-4-5", total * 3 / 100),
            ]
            let rows = split.map { HistoryTokenRow(day: key, provider: .claude, model: $0.0, tokens: $0.1) }
            let effortRows = efforts4.enumerated().map { position, effort in
                HistoryEffortRow(
                    day: key, provider: .claude, model: "claude-opus-5-5", effort: effort,
                    tokens: total * [40, 27, 21, 12][position] / 100)
            }
            days.append(HistoryCalendarDay(id: key, date: date, totals: [.claude: total], efforts: effortRows))
            tokens += rows
            efforts += effortRows
            cached.append(HistoryCachedRow(day: key, provider: .claude, cachedTokens: total * 93 / 100, tokens: total))
            for (position, skill) in skills.enumerated() where (index + position) % (position + 2) == 0 {
                activity.append(
                    HistoryActivityRow(
                        day: key, provider: .claude, kind: .skill, key: skill, count: 5 - position,
                        total: 5 - position, maximum: 1))
            }
            activity.append(
                HistoryActivityRow(
                    day: key, provider: .claude, kind: .turn, key: "", count: 18,
                    total: (38 + index % 20) * 60_000, maximum: (9 + index % 14) * 60_000))
        }
        func quota(_ id: String, minutes: Int, reset: Date, samples: [(TimeInterval, Double)]) -> [HistoryQuotaRow] {
            samples.map {
                HistoryQuotaRow(
                    sampledAt: now.addingTimeInterval($0.0), provider: .claude, windowID: id, displayName: nil,
                    usedPercentage: $0.1, resetsAt: reset, durationMinutes: minutes, accountFingerprint: nil)
            }
        }
        let weeklyStart = weeklyReset.addingTimeInterval(-7 * 86_400)
        var used = 0.0
        let weeklySamples = stride(from: weeklyStart.timeIntervalSince(now) + 1800, to: 0, by: 1800).map {
            offset -> (TimeInterval, Double) in
            let hour = calendar.component(.hour, from: now.addingTimeInterval(offset))
            used += (10...23).contains(hour) ? 0.36 : 0.02
            return (offset, used)
        }
        let sessionSamples = stride(from: -2.3 * 3600, to: 0, by: 900).map { ($0, (2.3 + $0 / 3600) * 7.4) }
        let records = StatsModel.Records(
            input: StatsSummary.Input(
                days: days, tokens: tokens, efforts: efforts, activity: activity, cached: cached),
            quota: quota("seven_day", minutes: 10_080, reset: weeklyReset, samples: weeklySamples)
                + quota("five_hour", minutes: 300, reset: sessionReset, samples: sessionSamples))
        let windows = [
            Fixture.window(id: "five_hour", usedPercentage: 17, resetsAt: sessionReset, durationMinutes: 300),
            Fixture.window(
                id: "seven_day", usedPercentage: weeklySamples.last?.1 ?? 40, resetsAt: weeklyReset,
                durationMinutes: 10_080),
        ]
        let store = Fixture.store(
            defaults: defaults, snapshots: [Fixture.snapshot(.claude, windows: windows, capturedAt: now)])
        store.displayMode = .claude
        store.animateChanges = false
        for kind in QuotaWindowKind.allCases { store.setClaudeWindow(kind, visible: true) }
        let view = StatsView(store: store, model: StatsModel(preview: records), providers: [.claude], scrolls: false)
            .frame(width: Theme.Layout.panelWidth - Theme.Layout.panelPadding * 2)
            .padding(Theme.Layout.panelPadding)
            .background(Theme.panelBackground)
            .environment(\.quotaAnimationsEnabled, false)
        try render(view, to: output.appendingPathComponent("stats.png"), maximumHeight: 2400)
    }
}
