import Foundation
import XCTest

@testable import TokenGaugeApp

@MainActor
final class QuotaAppearanceTests: XCTestCase {
    func testExistingUsersKeepClassicPanelAndNumericMenu() {
        withDefaults { defaults in
            defaults.set("unified", forKey: "displayMode")
            defaults.set("modelWeekly", forKey: "claudeMenuBarSource")
            let store = UsageStore(defaults: defaults)
            XCTAssertEqual(store.panelStyle, .standard)
            XCTAssertEqual(store.menuBarStyle, .numbers)
            XCTAssertTrue(store.animateChanges)
            XCTAssertEqual(store.displayMode, .unified)
        }
    }

    func testPanelAndMenuChoicesAreIndependentAndSurviveRelaunch() {
        withDefaults { defaults in
            for panel in QuotaPanelStyle.allCases {
                for menu in QuotaMenuBarStyle.allCases {
                    let store = UsageStore(defaults: defaults)
                    store.panelStyle = panel
                    store.menuBarStyle = menu
                    store.animateChanges = false
                    store.setClaudeWindow(.weekly, visible: false)
                    store.claudeMenuBarSource = .modelWeekly
                    let reopened = UsageStore(defaults: defaults)
                    XCTAssertEqual(reopened.panelStyle, panel)
                    XCTAssertEqual(reopened.menuBarStyle, menu)
                    XCTAssertFalse(reopened.animateChanges)
                    XCTAssertFalse(reopened.isClaudeWindowVisible(.weekly))
                    XCTAssertEqual(reopened.claudeMenuBarSource, .modelWeekly)
                }
            }
        }
    }

    func testUnknownStoredStylesUseCompatibleDefaults() {
        withDefaults { defaults in
            defaults.set("future-style", forKey: "quotaPanelStyle")
            defaults.set("future-style", forKey: "quotaMenuBarStyle")
            let store = UsageStore(defaults: defaults)
            XCTAssertEqual(store.panelStyle, .standard)
            XCTAssertEqual(store.menuBarStyle, .numbers)
        }
    }

    private func withDefaults(_ action: (UserDefaults) -> Void) {
        let suite = "TokenGauge.appearance-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        action(defaults)
    }
}
