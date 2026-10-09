import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ClaudeAccountsRenderingTests: XCTestCase {
    func testOtherAccountsFitThePanelInEveryStyleAndMode() async throws {
        let accounts = try await accountsStore()
        try withDefaults { defaults in
            let store = Fixture.store(defaults: defaults, snapshots: [claudeSnapshot(), Fixture.snapshot(.codex)])
            for style in QuotaPanelStyle.allCases {
                for mode in [UsageDisplayMode.claude, .unified] {
                    store.panelStyle = style
                    store.displayMode = mode
                    let view = PopoverView(store: store, showSettings: {}, showAbout: {}, accounts: accounts)
                    let size = fittingSize(view)
                    XCTAssertLessThanOrEqual(size.height, Theme.Layout.maximumPanelHeight, "\(style) \(mode)")
                    if let directory = ProcessInfo.processInfo.environment["TOKENGAUGE_SCREENSHOT_DIR"] {
                        let output = URL(fileURLWithPath: directory)
                        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        _ = try render(view, to: output.appendingPathComponent("accounts-\(style)-\(mode).png"))
                    }
                }
            }
            store.displayMode = .codex
            let codexOnly = fittingSize(PopoverView(store: store, showSettings: {}, showAbout: {}, accounts: accounts))
            let withoutAccounts = try withEmptyAccounts { empty in
                fittingSize(PopoverView(store: store, showSettings: {}, showAbout: {}, accounts: empty))
            }
            XCTAssertEqual(codexOnly.height, withoutAccounts.height, accuracy: 1)
        }
    }

    private func accountsStore() async throws -> ClaudeAccountsStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: temporaryDefaultsSuite()))
        defaults.set(true, forKey: ClaudeAccountsStore.enabledKey)
        let resets = Date().addingTimeInterval(3 * 3600)
        let store = ClaudeAccountsStore(defaults: defaults) { location in
            if location.directory.hasSuffix("gone") { return .status(401) }
            return .windows([
                Fixture.window(
                    id: "five_hour", usedPercentage: location.host == nil ? 12 : 57, resetsAt: resets,
                    durationMinutes: 300),
                Fixture.window(
                    id: "seven_day", usedPercentage: 8, resetsAt: resets.addingTimeInterval(86_400 * 4),
                    durationMinutes: 10_080),
            ])
        }
        for (name, location, tint) in [
            ("Side", "~/.claude-side", ClaudeExtraAccount.Tint.claude),
            ("Work", "work-mac:~/.claude-work", .violet), ("Old", "~/.claude-gone", .green),
            ("Spare", "~/.claude-spare", .blue),
        ] {
            store.add()
            var account = try XCTUnwrap(store.accounts.last)
            account.name = name
            account.location = location
            account.tint = tint
            account.icon = name == "Work" ? .balloon : .dot
            store.update(account)
            await store.refresh(account.id, force: true)
        }
        return store
    }

    private func withEmptyAccounts<T>(_ body: (ClaudeAccountsStore) throws -> T) throws -> T {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: temporaryDefaultsSuite()))
        return try body(ClaudeAccountsStore(defaults: defaults) { _ in .windows([]) })
    }

    private func claudeSnapshot() -> ProviderUsageSnapshot {
        Fixture.snapshot(
            .claude,
            windows: [
                Fixture.window(id: "five_hour", usedPercentage: 16, durationMinutes: 300),
                Fixture.window(id: "seven_day", usedPercentage: 30, durationMinutes: 10_080),
                Fixture.window(id: "seven_day_fable", usedPercentage: 0, durationMinutes: 10_080, displayName: "Fable"),
            ])
    }
}
