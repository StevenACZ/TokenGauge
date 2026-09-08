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
        let store = UsageStore(defaults: defaults, initialSnapshots: [snapshot])
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
            for mode in UsageDisplayMode.allCases {
                store.displayMode = mode
                UpdateManager.shared.handleNotFound()
                assertHeight(store)
                _ = UpdateManager.shared.handleUpdateFound(version: "1.0.1", releasePage: nil, informationOnly: false)
                assertHeight(store)
                UpdateManager.shared.handleDownloadInitiated()
                assertHeight(store)
            }
        }
    }

    private func assertHeight(_ store: UsageStore, file: StaticString = #filePath, line: UInt = #line) {
        let view = NSHostingView(rootView: PopoverView(store: store, showSettings: {}, showAbout: {}))
        XCTAssertEqual(
            view.fittingSize.width, store.displayMode == .unified ? 560 : 300, accuracy: 1, file: file, line: line)
        XCTAssertLessThanOrEqual(view.fittingSize.height, 500, file: file, line: line)
    }
}
