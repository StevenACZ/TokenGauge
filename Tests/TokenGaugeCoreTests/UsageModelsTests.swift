import Foundation
import XCTest

@testable import TokenGaugeCore

final class UsageModelsTests: XCTestCase {
    func testDisplayOrderSortsUnknownDurationsLastAndBreaksTiesByIdentifier() {
        let windows = [
            window(id: "seven_day", duration: 10_080),
            window(id: "unknown", duration: nil),
            window(id: "five_hour", duration: 300),
            window(id: "all_weekly", duration: 10_080),
        ]

        let sorted = windows.sorted(by: QuotaWindow.displayOrder)

        XCTAssertEqual(sorted.map(\.id), ["five_hour", "all_weekly", "seven_day", "unknown"])
        XCTAssertEqual(
            ProviderUsageSnapshot(
                provider: .claude, windows: windows, dailyUsage: [], summary: nil,
                availableResetCredits: nil, creditBalance: nil, capturedAt: nil
            ).longestWindow?.id, "unknown")
    }

    private func window(id: String, duration: Int?) -> QuotaWindow {
        QuotaWindow(id: id, usedPercentage: 10, resetsAt: nil, durationMinutes: duration, displayName: nil)
    }
}
