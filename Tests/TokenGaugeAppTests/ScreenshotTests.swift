import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ScreenshotTests: XCTestCase {
    func testExportSyntheticScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["TOKENGAUGE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TOKENGAUGE_SCREENSHOT_DIR to export synthetic documentation images")
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let previousIcon = NSApplication.shared.applicationIconImage
        let icon = output.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
            "Resources/AppIcon.icns")
        NSApplication.shared.applicationIconImage = try XCTUnwrap(NSImage(contentsOf: icon))
        defer { NSApplication.shared.applicationIconImage = previousIcon }
        let suite = "TokenGauge.screenshots.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let language = LocalizationManager.shared.language
        defer { LocalizationManager.shared.language = language }
        LocalizationManager.shared.language = .english
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let activity = (0..<7).map { index in
            DailyTokenUsage(
                day: formatter.string(from: Calendar.current.date(byAdding: .day, value: index - 6, to: now)!),
                tokens: [21, 7, 12, 18, 9, 16, 11][index] * 1_000_000)
        }
        let snapshots = UsageProvider.allCases.map { provider in
            var windows = [
                Fixture.window(
                    id: "\(provider.rawValue).primary", usedPercentage: provider == .codex ? 28 : 42,
                    resetsAt: now.addingTimeInterval(4 * 86400), durationMinutes: 10080)
            ]
            if provider == .codex {
                windows.append(
                    Fixture.window(
                        id: "base_model_inference.primary", usedPercentage: 0,
                        resetsAt: now.addingTimeInterval(6 * 86400), durationMinutes: 10080,
                        displayName: "gpt-reserve")
                )
            }
            return Fixture.snapshot(
                provider,
                windows: windows,
                dailyUsage: activity.enumerated().map { index, usage in
                    let tokens = provider == .codex ? usage.tokens : (index >= 3 && index <= 5 ? 0 : usage.tokens / 3)
                    return DailyTokenUsage(day: usage.day, tokens: tokens)
                }, capturedAt: now)
        }
        let store = Fixture.store(defaults: defaults, snapshots: snapshots)
        try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}), to: output.appendingPathComponent("panel.png"))
        store.displayMode = .claude
        try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}), to: output.appendingPathComponent("claude.png"))
        store.displayMode = .unified
        try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}), to: output.appendingPathComponent("unified.png")
        )
        try render(
            ScrollView {
                SettingsView(store: store, launchAtLogin: LaunchAtLoginManager()).defaultAppStorage(defaults)
            }.frame(width: 600, height: 750),
            to: output.appendingPathComponent("settings.png"), maximumHeight: 750)
        let historical = Fixture.snapshot(
            .claude,
            windows: [
                Fixture.window(
                    id: "five_hour", usedPercentage: 2, resetsAt: now.addingTimeInterval(10_800),
                    durationMinutes: 300),
                Fixture.window(
                    id: "seven_day", usedPercentage: 60, resetsAt: now.addingTimeInterval(172_800),
                    durationMinutes: 10_080),
                Fixture.window(
                    id: "seven_day_fable", usedPercentage: 88, resetsAt: now.addingTimeInterval(172_800),
                    durationMinutes: 10_080, displayName: "Fable"),
            ], capturedAt: now.addingTimeInterval(-3600))
        store.claudeAutomaticRecovery = true
        store.applyRefreshResults(
            claudeResult: ClaudeUsageResult(snapshot: historical, access: .credentialExpired, lastActivityAt: nil),
            codexState: store.codex)
        try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}),
            to: output.appendingPathComponent("recovery.png"))
        LocalizationManager.shared.language = .spanish
        try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}),
            to: output.appendingPathComponent("recovery-es.png"))
        store.applyRefreshResults(
            claudeResult: ClaudeUsageResult(snapshot: historical, access: .live, lastActivityAt: nil),
            codexState: store.codex)
        store.animateChanges = false
        for language in [AppLanguage.english, .spanish] {
            LocalizationManager.shared.language = language
            for mode in UsageDisplayMode.allCases {
                store.displayMode = mode
                for style in QuotaPanelStyle.allCases {
                    store.panelStyle = style
                    try render(
                        PopoverView(store: store, showSettings: {}, showAbout: {}),
                        to: output.appendingPathComponent("\(language.rawValue)-\(mode.rawValue)-\(style.rawValue).png")
                    )
                }
            }
        }

        LocalizationManager.shared.language = .english
        for historyMode in [HistoryMode.week, .calendar] {
            store.historyMode = historyMode
            let efforts = ["medium", "high", "xhigh"].enumerated().map { index, effort in
                HistoryEffortRow(
                    day: formatter.string(from: now), provider: .codex,
                    model: "gpt-6-astra", effort: effort, tokens: (index + 1) * 1_000_000)
            }
            for style in QuotaPanelStyle.allCases {
                store.panelStyle = style
                let history = HistoryDashboardModel(
                    previewSnapshots: snapshots, mode: historyMode,
                    previewEfforts: efforts, now: now)
                try render(
                    PopoverView(store: store, showSettings: {}, showAbout: {}, history: history),
                    to: output.appendingPathComponent("history-\(historyMode.rawValue)-\(style.rawValue).png"))
            }
        }
        let previousPace = QuotaPace(
            pointsPerHour: 4.9, observedMinutes: 45, sampledAt: now.addingTimeInterval(-86400),
            resetsAt: now.addingTimeInterval(86400), lastUsedPercentage: 30)
        let currentPace = QuotaPace(
            pointsPerHour: 3.2, observedMinutes: 40, sampledAt: now,
            resetsAt: now.addingTimeInterval(86400), lastUsedPercentage: 35)
        for (name, display) in [
            ("current", QuotaPaceDisplay(current: currentPace, previous: previousPace)),
            ("saved", QuotaPaceDisplay(current: nil, previous: previousPace)),
            ("waiting", QuotaPaceDisplay(current: nil, previous: nil)),
        ] {
            try render(
                QuotaPaceDetailsView(display: display),
                to: output.appendingPathComponent("pace-info-\(name).png"))
        }
        let year = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now)
        let colorfulDays = HistoryDashboardModel.makeDays(interval: year, tokens: [], efforts: []).enumerated().map {
            index, day in
            let values: [UsageProvider: Int] =
                day.date > now || index % 13 == 0
                ? [:]
                : [
                    .codex: index % 11 == 0 ? 0 : (index % 3 == 0 ? 90 : 20) * (index % 7 + 1) * 1000,
                    .claude: index % 11 == 0 ? 0 : (index % 3 == 1 ? 90 : 20) * (index % 7 + 1) * 1000,
                ]
            return HistoryCalendarDay(id: day.id, date: day.date, totals: values, efforts: [])
        }
        try render(
            HistoryCalendarView(
                days: colorfulDays, providers: [.codex, .claude],
                selectedDayKey: nil, focusID: "colorful"
            ) { _ in }
            .frame(width: 420, height: Theme.Layout.historyCalendarHeight),
            to: output.appendingPathComponent("history-months-colors.png"))
        store.historyMode = .recent
        store.panelStyle = .rings
        store.showLunaReserve = false
        store.setClaudeWindow(.weekly, visible: false)
        let fitted = try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}),
            to: output.appendingPathComponent("rings-current.png"))
        let visibleWindows = { (provider: UsageProvider) -> Int in
            max(
                1,
                WindowVisibility.visible(
                    store.state(for: provider).snapshot?.windows ?? [], provider: provider,
                    showLunaReserve: store.showLunaReserve, hiddenClaudeWindows: store.hiddenClaudeWindows
                ).count)
        }
        XCTAssertEqual(
            fitted.width,
            QuotaRingLayout.unifiedPanelWidth(
                codexCells: visibleWindows(.codex), claudeCells: visibleWindows(.claude)))

    }
}
