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
                QuotaWindow(
                    id: "\(provider.rawValue).primary", usedPercentage: provider == .codex ? 28 : 42,
                    resetsAt: now.addingTimeInterval(4 * 86400), durationMinutes: 10080, displayName: nil)
            ]
            if provider == .codex {
                windows.append(
                    QuotaWindow(
                        id: "base_model_inference.primary", usedPercentage: 0,
                        resetsAt: now.addingTimeInterval(6 * 86400), durationMinutes: 10080, displayName: "gpt-reserve")
                )
            }
            return ProviderUsageSnapshot(
                provider: provider,
                windows: windows,
                dailyUsage: activity.enumerated().map { index, usage in
                    let tokens = provider == .codex ? usage.tokens : (index >= 3 && index <= 5 ? 0 : usage.tokens / 3)
                    return DailyTokenUsage(day: usage.day, tokens: tokens)
                },
                summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: now)
        }
        let store = UsageStore(defaults: defaults, initialSnapshots: snapshots)
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
        let historical = ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                QuotaWindow(
                    id: "five_hour", usedPercentage: 2, resetsAt: now.addingTimeInterval(10_800), durationMinutes: 300,
                    displayName: nil),
                QuotaWindow(
                    id: "seven_day", usedPercentage: 60, resetsAt: now.addingTimeInterval(172_800),
                    durationMinutes: 10_080, displayName: nil),
                QuotaWindow(
                    id: "seven_day_fable", usedPercentage: 88, resetsAt: now.addingTimeInterval(172_800),
                    durationMinutes: 10_080, displayName: "Fable"),
            ], dailyUsage: [], summary: nil, availableResetCredits: nil, creditBalance: nil,
            capturedAt: now.addingTimeInterval(-3600))
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
                    let measured = try render(
                        PopoverView(store: store, showSettings: {}, showAbout: {}),
                        to: output.appendingPathComponent("\(language.rawValue)-\(mode.rawValue)-\(style.rawValue).png")
                    )
                    if mode == .unified && style != .standard {
                        XCTAssertLessThan(measured.height, 480)
                    }
                }
            }
        }

        store.showLunaReserve = false
        store.setClaudeWindow(.weekly, visible: false)
        let fitted = try render(
            PopoverView(store: store, showSettings: {}, showAbout: {}),
            to: output.appendingPathComponent("rings-current.png"))
        XCTAssertEqual(fitted.width, Theme.Layout.minimumRingUnifiedWidth)

    }

    @discardableResult
    private func render(_ content: some View, to output: URL, maximumHeight: CGFloat = 500) throws -> NSSize {
        let application = NSApplication.shared
        let previousAppearance = application.appearance
        application.appearance = NSAppearance(named: .darkAqua)
        defer { application.appearance = previousAppearance }
        let view = NSHostingView(
            rootView: content.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        view.appearance = NSAppearance(named: .darkAqua)
        let size = view.fittingSize
        XCTAssertGreaterThan(size.width, 200)
        XCTAssertLessThanOrEqual(size.height, maximumHeight)
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.appearance?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output)
        window.contentView = nil
        return size
    }
}
