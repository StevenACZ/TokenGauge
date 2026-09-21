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
        for kind in ClaudeWindowKind.allCases { store.setClaudeWindow(kind, visible: true) }
        store.showHourlyPace = false
        store.animateChanges = false
        let history = HistoryDashboardModel(previewSnapshots: snapshots, mode: .calendar, now: now)
        try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}, history: history),
            to: output.appendingPathComponent("readme-year.png"))
    }
}
