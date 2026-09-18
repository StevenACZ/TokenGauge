import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ClaudeAccountHeaderRenderingTests: XCTestCase {
    private let label = "very.long.account.name.for.layout@example.com"

    func testLongAccountLabelKeepsTheHeaderOnOneRowAndTruncatesOnlyItself() throws {
        let language = LocalizationManager.shared.language
        defer { LocalizationManager.shared.language = language }
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
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
        let suite = "TokenGauge.account.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(defaults: defaults, initialSnapshots: [snapshot()], historyReadsEnabled: false)

        XCTAssertNil(store.claudeAccountLabel)
        store.setPreviewAccountLabel(label)
        XCTAssertEqual(store.claudeAccountLabel, label)
        XCTAssertNil(store.claudeAccountFingerprint)
        let view = NSHostingView(rootView: PopoverView(store: store, showSettings: {}, showAbout: {}))
        XCTAssertLessThanOrEqual(view.fittingSize.height, Theme.Layout.maximumPanelHeight)
    }

    private func card(accountLabel: String?) -> some View {
        ProviderCard(
            provider: .claude, state: ProviderViewState(snapshot: snapshot(), status: .ready, isRefreshing: false),
            showProviderTitle: true, accountLabel: accountLabel
        )
        .frame(width: Theme.Layout.compactPanelWidth)
    }

    private func snapshot() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                QuotaWindow(
                    id: "seven_day", usedPercentage: 30, resetsAt: Date().addingTimeInterval(86_400),
                    durationMinutes: 10_080, displayName: nil)
            ], dailyUsage: [], summary: nil, availableResetCredits: nil, creditBalance: nil,
            capturedAt: Date().addingTimeInterval(-600))
    }

    private func render(_ content: some View) throws -> NSBitmapImageRep {
        let view = NSHostingView(rootView: content.environment(\.quotaAnimationsEnabled, false))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
}
