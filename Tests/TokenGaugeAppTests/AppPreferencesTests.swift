import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testPreferenceKeysAreUnchanged() {
        XCTAssertEqual(AppPreferences.Key.primaryProvider, "primaryProvider")
        XCTAssertEqual(AppPreferences.Key.displayMode, "displayMode")
        XCTAssertEqual(AppPreferences.Key.menuBarSize, "menuBarSize")
        XCTAssertEqual(AppPreferences.Key.quotaPanelStyle, "quotaPanelStyle")
        XCTAssertEqual(AppPreferences.Key.quotaMenuBarStyle, "quotaMenuBarStyle")
        XCTAssertEqual(AppPreferences.Key.quotaAnimateChanges, "quotaAnimateChanges")
        XCTAssertEqual(AppPreferences.Key.historyMode, "historyMode")
        XCTAssertEqual(AppPreferences.Key.showHourlyPace, "showHourlyPace")
        XCTAssertEqual(AppPreferences.Key.showLunaReserve, "showLunaReserve")
        XCTAssertEqual(AppPreferences.Key.hiddenClaudeWindows, "hiddenClaudeWindows")
        XCTAssertEqual(AppPreferences.Key.claudeMenuBarSource, "claudeMenuBarSource")
        XCTAssertEqual(AppPreferences.Key.claudeAutomaticRecovery, "claudeAutomaticRecovery")
        XCTAssertEqual(AppPreferences.Key.claudeRecoveryNextAttempt, "claudeRecoveryNextAttempt")
        XCTAssertEqual(AppPreferences.Key.claudeRecoveryFailures, "claudeRecoveryFailures")
        XCTAssertEqual(AppPreferences.Key.appLanguage, "appLanguage")
        XCTAssertEqual(AppPreferences.Key.codexExecutablePath, "codexExecutablePath")
        XCTAssertEqual(AppPreferences.Key.cancelledAt(.claude), "claudeCancelledAt")
        XCTAssertEqual(AppPreferences.Key.cancelledAt(.codex), "codexCancelledAt")
        XCTAssertEqual(AppPreferences.Key.cancellationDailyBaseline(.claude), "claudeCancellationDailyBaseline")
        XCTAssertEqual(AppPreferences.Key.cancellationDailyBaseline(.codex), "codexCancellationDailyBaseline")
    }

    func testLegacyDefaultsAreReadAndWrittenWithTheSameShapes() {
        withDefaults { defaults in
            let cancelledAt = Date(timeIntervalSince1970: 1_800_000_000)
            defaults.set("claude", forKey: "primaryProvider")
            defaults.set("unified", forKey: "displayMode")
            defaults.set("small", forKey: "menuBarSize")
            defaults.set("compact", forKey: "quotaPanelStyle")
            defaults.set("bars", forKey: "quotaMenuBarStyle")
            defaults.set(false, forKey: "quotaAnimateChanges")
            defaults.set("calendar", forKey: "historyMode")
            defaults.set(false, forKey: "showHourlyPace")
            defaults.set(false, forKey: "showLunaReserve")
            defaults.set(["modelWeekly", "session"], forKey: "hiddenClaudeWindows")
            defaults.set("weekly", forKey: "claudeMenuBarSource")
            defaults.set(true, forKey: "claudeAutomaticRecovery")
            defaults.set(cancelledAt, forKey: "codexCancelledAt")
            defaults.set(["2026-09-17": 12], forKey: "codexCancellationDailyBaseline")

            let store = UsageStore(defaults: defaults)
            XCTAssertEqual(store.primaryProvider, .claude)
            XCTAssertEqual(store.displayMode, .unified)
            XCTAssertEqual(store.menuBarSize, .small)
            XCTAssertEqual(store.panelStyle, .compact)
            XCTAssertEqual(store.menuBarStyle, .bars)
            XCTAssertFalse(store.animateChanges)
            XCTAssertEqual(store.historyMode, .calendar)
            XCTAssertFalse(store.showHourlyPace)
            XCTAssertFalse(store.showLunaReserve)
            XCTAssertEqual(store.hiddenClaudeWindows, [.modelWeekly, .session])
            XCTAssertEqual(store.claudeMenuBarWindows, [.weekly])
            XCTAssertTrue(store.claudeAutomaticRecovery)
            XCTAssertEqual(store.codexCancelledAt, cancelledAt)
            XCTAssertEqual(store.codex.status, .cancelled)
            XCTAssertTrue(store.recoveryAuthorization.isAllowed)

            store.menuBarSize = .medium
            store.setClaudeWindow(.session, visible: true)
            store.claudeAutomaticRecovery = false
            store.setCancelled(true, for: .claude)
            XCTAssertEqual(defaults.string(forKey: "menuBarSize"), "medium")
            XCTAssertEqual(defaults.stringArray(forKey: "hiddenClaudeWindows"), ["modelWeekly"])
            XCTAssertFalse(defaults.bool(forKey: "claudeAutomaticRecovery"))
            XCTAssertNotNil(defaults.object(forKey: "claudeCancelledAt") as? Date)
            XCTAssertNil(defaults.object(forKey: "claudeCancellationDailyBaseline"))
            XCTAssertEqual(
                defaults.dictionary(forKey: "codexCancellationDailyBaseline") as? [String: Int], ["2026-09-17": 12])
        }
    }

    func testFreshDefaultsKeepTheShippedFallbacks() {
        withDefaults { defaults in
            let preferences = AppPreferences(defaults: defaults)
            XCTAssertEqual(preferences.primaryProvider, .codex)
            XCTAssertEqual(preferences.displayMode, .codex)
            XCTAssertEqual(preferences.menuBarSize, .large)
            XCTAssertEqual(preferences.panelStyle, .standard)
            XCTAssertEqual(preferences.menuBarStyle, .numbers)
            XCTAssertTrue(preferences.animateChanges)
            XCTAssertEqual(preferences.historyMode, .recent)
            XCTAssertTrue(preferences.showHourlyPace)
            XCTAssertTrue(preferences.showLunaReserve)
            XCTAssertTrue(preferences.hiddenClaudeWindows.isEmpty)
            XCTAssertTrue(preferences.claudeMenuBarWindows.isEmpty)
            XCTAssertFalse(preferences.hideAccountLabel)
            XCTAssertFalse(preferences.claudeAutomaticRecovery)
            XCTAssertFalse(preferences.claudeAutomaticRecoveryDecided)
            XCTAssertNil(preferences.claudeRecoveryNextAttempt)
            XCTAssertEqual(preferences.claudeRecoveryFailures, 0)
            XCTAssertNil(preferences.cancelledAt(.claude))
            XCTAssertNil(preferences.cancellationDailyBaseline(.codex))

            preferences.claudeAutomaticRecovery = false
            XCTAssertTrue(preferences.claudeAutomaticRecoveryDecided)
            preferences.claudeRecoveryNextAttempt = nil
            XCTAssertNil(defaults.object(forKey: "claudeRecoveryNextAttempt"))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "TokenGauge.preferences-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
