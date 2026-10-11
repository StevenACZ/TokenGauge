import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class SettingsRenderingTests: XCTestCase {
    private static let titleBar: CGFloat = 28
    private static let pageInsets: CGFloat = 34

    func testEveryPageFitsTheWindowInBothLanguages() async throws {
        let accounts = try await accountsStore()
        try withDefaults { defaults in
            let store = Fixture.store(defaults: defaults, snapshots: snapshots())
            store.displayMode = .unified
            let launch = LaunchAtLoginManager()
            let navigation = SettingsNavigation()
            let available = SettingsView.height - Self.titleBar - Self.pageInsets
            let tour = MenuBarTourStage.expandedHeight - MenuBarTourStage.collapsedHeight
            withEachLanguage { language in
                let pages: [(SettingsPage, AnyView, CGFloat)] = [
                    (.menuBar, AnyView(MenuBarDesigner(store: store, accounts: accounts)), tour),
                    (.panel, AnyView(SettingsPanelPage(store: store)), 0),
                    (
                        .accounts,
                        AnyView(SettingsAccountsPage(store: store, accounts: accounts).defaultAppStorage(defaults)), 0
                    ),
                    (.general, AnyView(SettingsGeneralPage(store: store, launchAtLogin: launch)), 0),
                ]
                for (page, view, extra) in pages {
                    let height = fittingSize(view.frame(width: SettingsView.contentWidth)).height
                    XCTAssertLessThanOrEqual(height + extra, available, "\(page) \(language)")
                }
                for page in SettingsPage.allCases {
                    navigation.page = page
                    let size = fittingSize(window(store, launch, navigation, accounts, defaults))
                    XCTAssertEqual(size.width, SettingsView.width, "\(page) \(language)")
                    XCTAssertEqual(size.height, SettingsView.height, "\(page) \(language)")
                }
            }
            guard let directory = ProcessInfo.processInfo.environment["TOKENGAUGE_SCREENSHOT_DIR"] else { return }
            let output = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try withEachLanguage { language in
                for page in SettingsPage.allCases {
                    navigation.page = page
                    try render(
                        window(store, launch, navigation, accounts, defaults),
                        to: output.appendingPathComponent("settings-\(page.rawValue)-\(language.rawValue).png"),
                        maximumHeight: SettingsView.height)
                }
            }
        }
    }

    func testTourShowsEveryGestureOnceAndEnds() {
        let animated = MenuBarTourState.script(animated: true)
        let steps = animated.map(\.state.step).reduce(into: [MenuBarTourState.Step]()) { steps, step in
            if steps.last != step { steps.append(step) }
        }
        XCTAssertEqual(steps, MenuBarTourState.Step.allCases)
        XCTAssertEqual(
            animated.filter { $0.state.phase == .open }.map(\.state.mock), [.panel, .panel, .menu, .tooltip])
        XCTAssertTrue(animated.allSatisfy { $0.seconds > 0 })
        XCTAssertLessThan(animated.map(\.seconds).reduce(0, +), 20)
        XCTAssertEqual(
            MenuBarTourState.script(animated: false).map(\.state),
            MenuBarTourState.Step.allCases.map { MenuBarTourState(step: $0, phase: .open) })
        XCTAssertEqual(MenuBarTourState(step: .click, phase: .rest).cursor, .start)
        XCTAssertNil(MenuBarTourState(step: .rightClick, phase: .rest).mock)
        XCTAssertTrue(MenuBarTourState(step: .panel, phase: .open).highlightsPanel)
    }

    func testTourStageKeepsItsHeightInEveryStep() async throws {
        let accounts = try await accountsStore()
        try withDefaults { defaults in
            let store = Fixture.store(defaults: defaults, snapshots: snapshots())
            let presentation = MenuBarPresentation(
                providers: [.codex, .claude], state: { store.state(for: $0) },
                appearance: try XCTUnwrap(NSAppearance(named: .darkAqua)), accounts: accounts.menuBarAccounts)
            XCTAssertEqual(presentation.segments.count, 5)
            @MainActor func stage(_ state: MenuBarTourState?) -> some View {
                MenuBarTourStage(
                    presentation: presentation, mode: .unified, privacy: false, state: state, motion: false
                )
                .frame(width: SettingsView.contentWidth)
            }
            XCTAssertEqual(fittingSize(stage(nil)).height, MenuBarTourStage.collapsedHeight)
            let directory = ProcessInfo.processInfo.environment["TOKENGAUGE_SCREENSHOT_DIR"]
            try withEachLanguage { language in
                for step in MenuBarTourState.Step.allCases {
                    let view = stage(MenuBarTourState(step: step, phase: .open))
                    XCTAssertEqual(fittingSize(view).height, MenuBarTourStage.expandedHeight, "\(step) \(language)")
                    guard let directory else { continue }
                    let output = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    try render(
                        view,
                        to: output.appendingPathComponent("settings-tour-\(step.rawValue)-\(language.rawValue).png"))
                }
            }
        }
    }

    private func window(
        _ store: UsageStore, _ launch: LaunchAtLoginManager, _ navigation: SettingsNavigation,
        _ accounts: ClaudeAccountsStore, _ defaults: UserDefaults
    ) -> some View {
        SettingsView(store: store, launchAtLogin: launch, navigation: navigation, accounts: accounts)
            .defaultAppStorage(defaults)
    }

    private func snapshots() -> [ProviderUsageSnapshot] {
        let resets = Date().addingTimeInterval(3 * 3600)
        return [
            Fixture.snapshot(
                .claude,
                windows: [
                    Fixture.window(id: "five_hour", usedPercentage: 23, resetsAt: resets, durationMinutes: 300),
                    Fixture.window(
                        id: "seven_day", usedPercentage: 30, resetsAt: resets.addingTimeInterval(86_400 * 3),
                        durationMinutes: 10_080),
                    Fixture.window(
                        id: "seven_day_fable", usedPercentage: 4, resetsAt: resets.addingTimeInterval(86_400 * 3),
                        durationMinutes: 10_080, displayName: "Fable"),
                ]),
            Fixture.snapshot(
                .codex,
                windows: [
                    Fixture.window(
                        id: "codex.primary", usedPercentage: 28, resetsAt: resets.addingTimeInterval(86_400 * 4),
                        durationMinutes: 10_080)
                ]),
        ]
    }

    private func accountsStore() async throws -> ClaudeAccountsStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: temporaryDefaultsSuite()))
        defaults.set(true, forKey: ClaudeAccountsStore.enabledKey)
        let resets = Date().addingTimeInterval(2 * 3600)
        let store = ClaudeAccountsStore(
            defaults: defaults,
            read: { location in
                .windows([
                    Fixture.window(
                        id: "five_hour", usedPercentage: location.host == nil ? 25 : 45, resetsAt: resets,
                        durationMinutes: 300),
                    Fixture.window(
                        id: "seven_day", usedPercentage: 8, resetsAt: resets.addingTimeInterval(86_400 * 4),
                        durationMinutes: 10_080),
                ])
            }, currentWeekday: { 3 })
        for (name, location, tint, icon) in [
            ("Side", "~/.claude-side", ClaudeExtraAccount.Tint.teal, ClaudeExtraAccount.Icon.letter),
            ("Team", "~/.claude-team", .pink, .letter), ("Work", "work-mac:~/.claude-work", .violet, .balloon),
        ] {
            store.add()
            var account = try XCTUnwrap(store.accounts.last)
            account.name = name
            account.location = location
            account.tint = tint
            account.icon = icon
            account.showsInMenuBar = true
            if name == "Work" { account.hiddenWeekdays = [1, 7] }
            store.update(account)
            await store.refresh(account.id, force: true)
        }
        return store
    }
}
