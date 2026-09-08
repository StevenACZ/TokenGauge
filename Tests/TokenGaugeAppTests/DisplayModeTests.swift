import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class DisplayModeTests: XCTestCase {
    func testLegacyProviderChoiceMigratesWithoutChangingIt() {
        withDefaults { defaults in
            defaults.set("claude", forKey: "primaryProvider")
            let store = UsageStore(defaults: defaults)
            XCTAssertEqual(store.displayMode, .claude)
            XCTAssertEqual(store.orderedProviders, [.claude])
            store.displayMode = .codex
            XCTAssertEqual(store.primaryProvider, .codex)
            XCTAssertEqual(defaults.string(forKey: "primaryProvider"), "codex")
        }
    }

    func testUnifiedPersistsAndCancellationDoesNotSwitchMode() {
        withDefaults { defaults in
            let store = UsageStore(defaults: defaults)
            store.displayMode = .unified
            store.setCancelled(true, for: .claude)
            store.setCancelled(true, for: .codex)
            let reopened = UsageStore(defaults: defaults)
            XCTAssertEqual(reopened.displayMode, .unified)
            XCTAssertEqual(reopened.orderedProviders, [.codex, .claude])
            XCTAssertTrue(reopened.isCancelled(provider: .claude))
            XCTAssertTrue(reopened.isCancelled(provider: .codex))
        }
    }

    func testMenuBarSizeDefaultsToLargeForMissingOrUnknownPreference() {
        withDefaults { defaults in
            XCTAssertEqual(UsageStore(defaults: defaults).menuBarSize, .large)
            defaults.set("unsupported-size", forKey: "menuBarSize")
            XCTAssertEqual(UsageStore(defaults: defaults).menuBarSize, .large)
        }
    }

    func testEveryMenuBarSizePersistsWithoutChangingDisplayMode() {
        withDefaults { defaults in
            let store = UsageStore(defaults: defaults)
            store.displayMode = .unified
            for size in MenuBarSize.allCases {
                store.menuBarSize = size
                let reopened = UsageStore(defaults: defaults)
                XCTAssertEqual(reopened.menuBarSize, size)
                XCTAssertEqual(reopened.displayMode, .unified)
            }
        }
    }

    func testReserveVisibilityPersistsWithoutChangingGeneralQuota() {
        withDefaults { defaults in
            let general = window("codex.primary", used: 42)
            let reserve = window("base_model_inference.primary", used: 5)
            let snapshot = ProviderUsageSnapshot(
                provider: .codex, windows: [general, reserve], dailyUsage: [], summary: nil,
                availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
            let store = UsageStore(defaults: defaults, initialSnapshots: [snapshot])
            XCTAssertTrue(store.showLunaReserve)
            XCTAssertEqual(store.menuBarWindow, general)
            store.showLunaReserve = false
            XCTAssertEqual(store.menuBarWindow, general)
            XCTAssertFalse(UsageStore(defaults: defaults).showLunaReserve)
            XCTAssertEqual(
                WindowVisibility.visible([general, reserve], provider: .codex, showLunaReserve: false), [general])
            XCTAssertEqual(WindowVisibility.visible([general, reserve], provider: .codex).count, 2)
        }
    }

    func testReserveDoesNotHideGeneralSessionFromMenuBar() {
        let general = window("codex.primary", used: 35, minutes: 300)
        let reserve = window("base_model_inference.primary", used: 0)
        let snapshot = ProviderUsageSnapshot(
            provider: .codex, windows: [general, reserve], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
        XCTAssertEqual(
            ProviderStateResolver.menuBarWindow(state: .init(snapshot: snapshot, status: .ready, isRefreshing: false)),
            general)
    }

    private func window(_ id: String, used: Double, minutes: Int = 10080) -> QuotaWindow {
        QuotaWindow(
            id: id, usedPercentage: used, resetsAt: Date().addingTimeInterval(86400), durationMinutes: minutes,
            displayName: nil)
    }

    private func withDefaults(_ action: (UserDefaults) -> Void) {
        let name = "TokenGauge.display-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        action(defaults)
    }
}
