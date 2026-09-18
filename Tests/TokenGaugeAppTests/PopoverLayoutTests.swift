import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class PopoverLayoutTests: XCTestCase {
    func testLargeProviderListsAndUpdateStatesStayWithinPanelHeight() throws {
        let suite = "TokenGauge.layout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let language = LocalizationManager.shared.language
        defer {
            defaults.removePersistentDomain(forName: suite)
            LocalizationManager.shared.language = language
            UpdateManager.shared.handleNotFound()
        }
        let snapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: (0..<5).map { index in
                QuotaWindow(
                    id: "codex.\(index)", usedPercentage: 25,
                    resetsAt: Date().addingTimeInterval(86400 * 3), durationMinutes: 10080,
                    displayName: index == 0 ? nil : "Model \(index)")
            }, dailyUsage: [], summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
        let store = UsageStore(
            defaults: defaults, initialSnapshots: [snapshot, claudeSnapshot()], historyReadsEnabled: false)
        store.showHourlyPace = true
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
            for mode in UsageDisplayMode.allCases {
                store.displayMode = mode
                for style in QuotaPanelStyle.allCases {
                    store.panelStyle = style
                    UpdateManager.shared.handleNotFound()
                    assertHeight(store)
                    _ = UpdateManager.shared.handleUpdateFound(
                        version: "1.0.1", releasePage: nil, informationOnly: false)
                    assertHeight(store)
                    UpdateManager.shared.handleDownloadInitiated()
                    assertHeight(store)
                }
            }
        }
    }

    func testUnifiedProviderContentFitsEveryStyleWithoutScrolling() throws {
        let suite = "TokenGauge.layout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(
            defaults: defaults, initialSnapshots: [codexSnapshot(), claudeSnapshot()], historyReadsEnabled: false)
        store.showHourlyPace = true
        store.displayMode = .unified
        try withEachLanguage { language in
            for style in QuotaPanelStyle.allCases {
                store.panelStyle = style
                let view = PopoverView(store: store, showSettings: {}, showAbout: {})
                let content = fittingSize(
                    view.providerContent.frame(width: view.panelWidth - Theme.Layout.panelPadding * 2))
                XCTAssertLessThanOrEqual(
                    content.height, view.providerMaxHeight, "\(language.rawValue) / \(style.rawValue)")
                assertHeight(store)
            }
        }
    }

    func testUpdateBannerNeverClipsTheRingProviderCards() throws {
        let suite = "TokenGauge.layout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            UpdateManager.shared.handleNotFound()
        }
        let store = UsageStore(
            defaults: defaults, initialSnapshots: [codexSnapshot(), claudeSnapshot()], historyReadsEnabled: false)
        store.showHourlyPace = true
        store.panelStyle = .rings
        store.displayMode = .unified
        try withEachLanguage { language in
            for banner in [false, true] {
                UpdateManager.shared.handleNotFound()
                if banner {
                    _ = UpdateManager.shared.handleUpdateFound(
                        version: "1.4.1", releasePage: nil, informationOnly: false)
                }
                for downloading in banner ? [false, true] : [false] {
                    if downloading { UpdateManager.shared.handleDownloadInitiated() }
                    let view = PopoverView(store: store, showSettings: {}, showAbout: {})
                    let content = fittingSize(
                        view.providerContent.frame(width: view.panelWidth - Theme.Layout.panelPadding * 2))
                    XCTAssertEqual(view.providerMaxHeight, Theme.Layout.ringProviderMaxHeight)
                    XCTAssertLessThanOrEqual(
                        content.height, view.providerMaxHeight,
                        "\(language.rawValue) / \(UpdateManager.shared.phase)")
                    assertHeight(store)
                }
            }
        }
    }

    private func claudeSnapshot() -> ProviderUsageSnapshot {
        Fixture.snapshot(
            .claude,
            windows: [
                Fixture.window(
                    id: "five_hour", usedPercentage: 2, resetsAt: Date().addingTimeInterval(7_200),
                    durationMinutes: 300),
                Fixture.window(
                    id: "seven_day", usedPercentage: 25, resetsAt: Date().addingTimeInterval(172_800),
                    durationMinutes: 10_080),
                Fixture.window(
                    id: "seven_day_fable", usedPercentage: 88, resetsAt: Date().addingTimeInterval(172_800),
                    durationMinutes: 10_080, displayName: "Fable"),
            ], availableResetCredits: 2, capturedAt: Date().addingTimeInterval(-600),
            modelBuckets: Fixture.modelBuckets([
                ("claude-opus-4-6", 171_600_000), ("claude-fable-1", 67_900_000), ("claude-haiku-4-5", 1_100_000),
            ]))
    }

    private func codexSnapshot() -> ProviderUsageSnapshot {
        Fixture.snapshot(
            .codex,
            windows: [
                Fixture.window(
                    id: "codex.weekly", usedPercentage: 41, resetsAt: Date().addingTimeInterval(172_800),
                    durationMinutes: 10_080),
                Fixture.window(
                    id: "base_model_inference.weekly", usedPercentage: 12,
                    resetsAt: Date().addingTimeInterval(172_800), durationMinutes: 10_080,
                    displayName: "gpt-reserve"),
            ], capturedAt: Date().addingTimeInterval(-600),
            modelBuckets: Fixture.modelBuckets([("gpt-6-astra", 148_300_000)]))
    }

    private func assertHeight(_ store: UsageStore, file: StaticString = #filePath, line: UInt = #line) {
        let view = NSHostingView(rootView: PopoverView(store: store, showSettings: {}, showAbout: {}))
        let budget = Theme.Layout.maximumPanelHeight + UpdateBannerView.height(for: UpdateManager.shared.phase)
        XCTAssertGreaterThanOrEqual(view.fittingSize.width, Theme.Layout.compactPanelWidth, file: file, line: line)
        XCTAssertLessThanOrEqual(view.fittingSize.width, Theme.Layout.unifiedPanelWidth, file: file, line: line)
        XCTAssertLessThanOrEqual(
            view.fittingSize.height, budget,
            "\(LocalizationManager.shared.language.rawValue) / \(store.displayMode.rawValue) / \(store.panelStyle.rawValue) / \(UpdateManager.shared.phase)",
            file: file, line: line)
    }
}
