import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ClaudeWindowPreferencesTests: XCTestCase {
    func testKindsClassifyTheOfficialClaudeWindows() {
        XCTAssertEqual(ClaudeWindowKind.of(session), .session)
        XCTAssertEqual(ClaudeWindowKind.of(weekly), .weekly)
        XCTAssertEqual(ClaudeWindowKind.of(fable), .modelWeekly)
    }

    func testHiddenKindsLeaveThePanelWithoutChangingOrder() {
        let visible = WindowVisibility.visible(
            [session, weekly, fable], provider: .claude, hiddenClaudeWindows: [.session, .weekly])
        XCTAssertEqual(visible.map(\.id), ["seven_day_fable"])
        XCTAssertEqual(WindowVisibility.visible([session, weekly, fable], provider: .claude).count, 3)
    }

    func testExplicitMenuBarSourceOverridesTheTightestWeekly() {
        let state = ProviderViewState(snapshot: snapshot, status: .ready, isRefreshing: false)
        XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: state)?.id, "seven_day_fable")
        XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: state, claudeSource: .session)?.id, "five_hour")
        XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: state, claudeSource: .weekly)?.id, "seven_day")
        XCTAssertEqual(
            ProviderStateResolver.menuBarWindow(state: state, claudeSource: .modelWeekly)?.id, "seven_day_fable")
    }

    func testMissingExplicitSourceFallsBackToAutomatic() {
        let snapshot = ProviderUsageSnapshot(
            provider: .claude, windows: [session, weekly], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
        let state = ProviderViewState(snapshot: snapshot, status: .ready, isRefreshing: false)
        XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: state, claudeSource: .modelWeekly)?.id, "seven_day")
    }

    func testStorePersistsPreferencesAndKeepsOneWindowVisible() {
        withDefaults { defaults in
            let store = UsageStore(defaults: defaults, initialSnapshots: [snapshot])
            store.displayMode = .claude
            XCTAssertEqual(store.menuBarWindow?.id, "seven_day_fable")
            store.claudeMenuBarSource = .session
            XCTAssertEqual(store.menuBarWindow?.id, "five_hour")
            store.setClaudeWindow(.session, visible: false)
            store.setClaudeWindow(.weekly, visible: false)
            store.setClaudeWindow(.modelWeekly, visible: false)
            XCTAssertEqual(store.hiddenClaudeWindows, [.session, .weekly])
            XCTAssertTrue(store.isClaudeWindowVisible(.modelWeekly))
            XCTAssertEqual(store.menuBarWindow?.id, "five_hour")
            let reopened = UsageStore(defaults: defaults)
            XCTAssertEqual(reopened.hiddenClaudeWindows, [.session, .weekly])
            XCTAssertEqual(reopened.claudeMenuBarSource, .session)
            defaults.set(["bogus"], forKey: "hiddenClaudeWindows")
            defaults.set("bogus", forKey: "claudeMenuBarSource")
            XCTAssertEqual(UsageStore(defaults: defaults).hiddenClaudeWindows, [])
            XCTAssertEqual(UsageStore(defaults: defaults).claudeMenuBarSource, .automatic)
        }
    }

    private var session: QuotaWindow { window("five_hour", used: 90, minutes: 300, name: nil) }
    private var weekly: QuotaWindow { window("seven_day", used: 30, minutes: 10_080, name: nil) }
    private var fable: QuotaWindow { window("seven_day_fable", used: 60, minutes: 10_080, name: "Fable") }

    private var snapshot: ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude, windows: [session, weekly, fable], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
    }

    private func window(_ id: String, used: Double, minutes: Int, name: String?) -> QuotaWindow {
        QuotaWindow(
            id: id, usedPercentage: used, resetsAt: Date().addingTimeInterval(86_400), durationMinutes: minutes,
            displayName: name)
    }

    private func withDefaults(_ action: (UserDefaults) -> Void) {
        let name = "TokenGauge.claude-window-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        action(defaults)
    }
}
