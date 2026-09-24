import AppKit
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class MenuBarMultiWindowTests: XCTestCase {
    private let appearance = NSAppearance(named: .aqua)!

    func testSelectedClaudeWindowsAppearInCanonicalOrderWithShortLabels() {
        let presentation = MenuBarPresentation(
            providers: [.claude], state: state, appearance: appearance,
            selection: [.claude: [.modelWeekly, .session, .weekly]])
        XCTAssertEqual(presentation.segments.map(\.label), ["5h", "7d", "Fable"])
        XCTAssertEqual(presentation.segments.map(\.text), ["36%", "69%", "100%"])
        XCTAssertEqual(presentation.attributedTitle().string, " 5h\u{2009}36% 7d\u{2009}69% Fable\u{2009}100%")
        XCTAssertEqual(presentation.accessibilityLabel.components(separatedBy: "\n").count, 3)
    }

    func testOneSelectedWindowKeepsTheUnlabelledTitle() {
        let presentation = MenuBarPresentation(
            providers: [.claude], state: state, appearance: appearance, selection: [.claude: [.weekly]])
        XCTAssertEqual(presentation.segments.map(\.label), [nil])
        XCTAssertEqual(presentation.attributedTitle().string, " 69%")
    }

    func testMissingSelectedWindowsAreSkippedWithoutSubstitution() {
        let presentation = MenuBarPresentation(
            providers: [.claude], state: sessionOnly, appearance: appearance,
            selection: [.claude: [.session, .modelWeekly]])
        XCTAssertEqual(presentation.segments.map(\.text), ["36%"])
        XCTAssertEqual(presentation.segments.map(\.label), [nil])
    }

    func testUnifiedGroupsWindowsPerProviderWithOneLogoEach() throws {
        for style in QuotaMenuBarStyle.allCases {
            let presentation = MenuBarPresentation(
                providers: [.codex, .claude], state: state, appearance: appearance, style: style,
                selection: [.claude: [.session, .weekly, .modelWeekly]])
            XCTAssertEqual(presentation.segments.map(\.provider), [.codex, .claude, .claude, .claude])
            XCTAssertEqual(presentation.groups.map(\.count), [1, 3])
            let attachments = attachments(in: presentation.attributedTitle())
            switch style {
            case .numbers: XCTAssertEqual(attachments.count, 1)
            case .bars: XCTAssertEqual(attachments.count, 3)
            case .rings: XCTAssertEqual(attachments.count, 3)
            }
        }
    }

    func testStackedBarsAndConcentricRingsKeepTheirIndicatorSize() throws {
        for size in MenuBarSize.allCases {
            let bars = MenuBarPresentation(
                providers: [.claude], state: state, appearance: appearance, size: size, style: .bars,
                selection: [.claude: [.session, .weekly, .modelWeekly]])
            let barImage = try XCTUnwrap(bars.quotaImage(for: bars.segments))
            XCTAssertEqual(barImage.size, NSSize(width: size.iconSize * 1.8, height: size.iconSize))
            let rings = MenuBarPresentation(
                providers: [.claude], state: state, appearance: appearance, size: size, style: .rings,
                selection: [.claude: [.session, .weekly]])
            let ringImage = try XCTUnwrap(rings.quotaImage(for: rings.segments))
            let diameter = min(22, size.iconSize + 5)
            XCTAssertEqual(ringImage.size, NSSize(width: diameter, height: diameter))
            XCTAssertNotEqual(barImage.tiffRepresentation, bars.quotaImage(for: [bars.segments[0]])?.tiffRepresentation)
        }
    }

    func testLegacySingleSourceMigratesToTheNewSelection() throws {
        try withDefaults { defaults in
            defaults.set("modelWeekly", forKey: "claudeMenuBarSource")
            XCTAssertEqual(AppPreferences(defaults: defaults).claudeMenuBarWindows, [.modelWeekly])
            defaults.set("automatic", forKey: "claudeMenuBarSource")
            XCTAssertEqual(AppPreferences(defaults: defaults).claudeMenuBarWindows, [])
            let store = UsageStore(defaults: defaults, historyReadsEnabled: false)
            store.toggleMenuBarWindow(.weekly, for: .claude)
            store.toggleMenuBarWindow(.session, for: .claude)
            XCTAssertEqual(defaults.stringArray(forKey: "claudeMenuBarWindows"), ["session", "weekly"])
            store.toggleMenuBarWindow(.weekly, for: .claude)
            store.toggleMenuBarWindow(.session, for: .claude)
            XCTAssertEqual(UsageStore(defaults: defaults, historyReadsEnabled: false).claudeMenuBarWindows, [])
        }
    }

    func testCodexSelectionUsesItsOwnWindowsAndFallsBackWhenMissing() {
        let reset = Date().addingTimeInterval(86_400)
        let snapshot = Fixture.snapshot(
            .codex,
            windows: [
                Fixture.window(id: "codex.primary", usedPercentage: 40, resetsAt: reset, durationMinutes: 300),
                Fixture.window(id: "codex.secondary", usedPercentage: 90, resetsAt: reset, durationMinutes: 10_080),
                Fixture.window(
                    id: "base_model_inference.secondary", usedPercentage: 5, resetsAt: reset, durationMinutes: 10_080),
            ])
        let codex: (UsageProvider) -> ProviderViewState = { _ in
            ProviderViewState(snapshot: snapshot, status: .ready, isRefreshing: false)
        }
        XCTAssertEqual(ProviderStateResolver.menuBarKinds(snapshot: snapshot, provider: .codex), [.session, .weekly])
        XCTAssertEqual(ProviderStateResolver.menuBarKinds(snapshot: nil, provider: .codex), [.weekly])
        XCTAssertEqual(ProviderStateResolver.menuBarKinds(snapshot: nil, provider: .claude), QuotaWindowKind.allCases)
        let both = MenuBarPresentation(
            providers: [.codex], state: codex, appearance: appearance, selection: [.codex: [.weekly, .session]])
        XCTAssertEqual(both.segments.map(\.label), ["5h", "7d"])
        XCTAssertEqual(both.segments.map(\.text), ["60%", "10%"])
        let missing = MenuBarPresentation(
            providers: [.codex], state: codex, appearance: appearance, selection: [.codex: [.modelWeekly]])
        XCTAssertEqual(missing.segments.map(\.text), ["10%"])
        let automatic = MenuBarPresentation(providers: [.codex], state: codex, appearance: appearance)
        XCTAssertEqual(automatic.segments.map(\.text), ["10%"])
    }

    func testStoreKeepsOneProviderVisibleAndPersistsCodexSelection() throws {
        try withDefaults { defaults in
            let store = UsageStore(defaults: defaults, historyReadsEnabled: false)
            store.displayMode = .unified
            store.setInMenuBar(false, provider: .codex)
            XCTAssertEqual(store.displayMode, .claude)
            store.setInMenuBar(false, provider: .claude)
            XCTAssertEqual(store.displayMode, .claude)
            store.setInMenuBar(true, provider: .codex)
            XCTAssertEqual(store.displayMode, .unified)
            store.toggleMenuBarWindow(.session, for: .codex)
            XCTAssertEqual(defaults.stringArray(forKey: "codexMenuBarWindows"), ["session"])
            XCTAssertEqual(store.menuBarSelections, [.codex: [.session], .claude: []])
            XCTAssertEqual(UsageStore(defaults: defaults, historyReadsEnabled: false).codexMenuBarWindows, [.session])
        }
    }

    private func attachments(in title: NSAttributedString) -> [NSTextAttachment] {
        var result = [NSTextAttachment]()
        title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { result.append(attachment) }
        }
        return result
    }

    private func state(_ provider: UsageProvider) -> ProviderViewState {
        let reset = Date().addingTimeInterval(86_400)
        let windows =
            provider == .codex
            ? [Fixture.window(id: "codex.primary", usedPercentage: 90, resetsAt: reset, durationMinutes: 10_080)]
            : [
                Fixture.window(id: "five_hour", usedPercentage: 64, resetsAt: reset, durationMinutes: 300),
                Fixture.window(id: "seven_day", usedPercentage: 31, resetsAt: reset, durationMinutes: 10_080),
                Fixture.window(
                    id: "seven_day_fable", usedPercentage: 0, resetsAt: reset, durationMinutes: 10_080,
                    displayName: "Fable"),
            ]
        return ProviderViewState(
            snapshot: Fixture.snapshot(provider, windows: windows), status: .ready, isRefreshing: false)
    }

    private func sessionOnly(_ provider: UsageProvider) -> ProviderViewState {
        let window = Fixture.window(
            id: "five_hour", usedPercentage: 64, resetsAt: Date().addingTimeInterval(3_600), durationMinutes: 300)
        return ProviderViewState(
            snapshot: Fixture.snapshot(provider, windows: [window]), status: .ready, isRefreshing: false)
    }
}
