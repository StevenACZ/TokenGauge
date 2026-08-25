import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ProviderStateResolverTests: XCTestCase {
    func testMenuBarPrefersTheTightestModelScopedWeeklyWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let state = ProviderViewState(
            snapshot: snapshot(
                provider: .claude,
                windows: [
                    window(id: "five_hour", used: 98, duration: 300, reset: now.addingTimeInterval(3600)),
                    window(id: "seven_day", used: 20, duration: 10_080, reset: now.addingTimeInterval(86_400)),
                    window(
                        id: "seven_day_fable",
                        used: 56,
                        duration: 10_080,
                        reset: now.addingTimeInterval(86_400),
                        displayName: "Fable"
                    ),
                ],
                capturedAt: now
            ),
            status: .ready,
            isRefreshing: false
        )

        XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: state)?.id, "seven_day_fable")
    }

    func testMenuBarFallsBackToTheAllModelsWeeklyWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let state = ProviderViewState(
            snapshot: snapshot(
                provider: .claude,
                windows: [
                    window(id: "five_hour", used: 98, duration: 300, reset: now.addingTimeInterval(3600)),
                    window(id: "seven_day", used: 20, duration: 10_080, reset: now.addingTimeInterval(86_400)),
                ],
                capturedAt: now
            ),
            status: .ready,
            isRefreshing: false
        )

        XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: state)?.id, "seven_day")
    }

    func testMenuBarStaysEmptyWhileClaudeIsUnavailable() {
        let state = ProviderViewState(snapshot: nil, status: .unavailable, isRefreshing: false)
        XCTAssertNil(ProviderStateResolver.menuBarWindow(state: state))
    }

    func testClaudeIsStaleWhenAnyWindowHasExpired() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let usage = snapshot(
            provider: .claude,
            windows: [
                window(id: "five_hour", used: 50, duration: 300, reset: now.addingTimeInterval(-1)),
                window(id: "seven_day", used: 25, duration: 10_080, reset: now.addingTimeInterval(86_400)),
            ],
            capturedAt: now.addingTimeInterval(-60)
        )

        XCTAssertEqual(ProviderStateResolver.claudeStatus(snapshot: usage, now: now), .stale)
    }

    func testClaudeWaitsWithoutCapturedQuota() {
        let usage = snapshot(provider: .claude, windows: [], capturedAt: nil)
        XCTAssertEqual(ProviderStateResolver.claudeStatus(snapshot: usage, now: Date()), .waiting)
    }

    func testCodexWaitsWhenResponseContainsNoWindows() {
        let usage = snapshot(provider: .codex, windows: [], capturedAt: Date())
        XCTAssertEqual(ProviderStateResolver.codexStatus(snapshot: usage), .waiting)
    }

    private func snapshot(
        provider: UsageProvider,
        windows: [QuotaWindow],
        capturedAt: Date?
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: windows,
            dailyUsage: [],
            summary: nil,
            availableResetCredits: nil,
            creditBalance: nil,
            capturedAt: capturedAt
        )
    }

    private func window(
        id: String,
        used: Double,
        duration: Int,
        reset: Date,
        displayName: String? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            usedPercentage: used,
            resetsAt: reset,
            durationMinutes: duration,
            displayName: displayName
        )
    }
}
