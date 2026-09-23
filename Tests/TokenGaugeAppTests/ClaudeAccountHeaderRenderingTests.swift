import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ClaudeAccountHeaderRenderingTests: XCTestCase {
    private let label = "very.long.account.name.for.layout@example.com"

    func testLongAccountLabelKeepsTheHeaderOnOneRowAndTruncatesOnlyItself() throws {
        try withEachLanguage { _ in
            let plain = try render(card(accountLabel: nil))
            let labelled = try render(card(accountLabel: label))
            let longer = try render(card(accountLabel: label + label))
            XCTAssertEqual(labelled.size.width, Theme.Layout.compactPanelWidth, accuracy: 1)
            XCTAssertEqual(labelled.size.height, plain.size.height, accuracy: 1)
            XCTAssertEqual(longer.size.width, labelled.size.width, accuracy: 1)
            XCTAssertEqual(longer.size.height, labelled.size.height, accuracy: 1)
        }
    }

    func testPreviewStoresExposeTheAccountLabelWithoutReadingTheRealConfiguration() throws {
        try withDefaults { defaults in
            let store = Fixture.store(defaults: defaults, snapshots: [snapshot()])

            XCTAssertNil(store.claudeAccountLabel)
            store.setPreviewAccountLabel(label)
            XCTAssertEqual(store.claudeAccountLabel, label)
            XCTAssertNil(store.claudeAccountFingerprint)
            let size = fittingSize(PopoverView(store: store, showSettings: {}, showAbout: {}))
            XCTAssertLessThanOrEqual(size.height, Theme.Layout.maximumPanelHeight)
        }
    }

    func testPrivacyModeNeverDrawsTheAccountLabel() throws {
        try withEachLanguage { _ in
            let hidden = try render(card(accountLabel: label, hidden: true))
            let otherHidden = try render(card(accountLabel: "someone.else@example.org", hidden: true))
            let shown = try render(card(accountLabel: label))
            XCTAssertEqual(hidden.tiffRepresentation, otherHidden.tiffRepresentation)
            XCTAssertNotEqual(hidden.tiffRepresentation, shown.tiffRepresentation)
            XCTAssertEqual(hidden.size.height, shown.size.height, accuracy: 1)
        }
    }

    private func card(accountLabel: String?, hidden: Bool = false) -> some View {
        ProviderCard(
            provider: .claude, state: ProviderViewState(snapshot: snapshot(), status: .ready, isRefreshing: false),
            showProviderTitle: true, hidesAccountLabel: hidden, accountLabel: accountLabel
        )
        .frame(width: Theme.Layout.compactPanelWidth)
    }

    private func snapshot() -> ProviderUsageSnapshot {
        Fixture.snapshot(
            .claude,
            windows: [
                Fixture.window(
                    id: "seven_day", usedPercentage: 30, resetsAt: Date().addingTimeInterval(86_400),
                    durationMinutes: 10_080)
            ], capturedAt: Date().addingTimeInterval(-600))
    }
}
