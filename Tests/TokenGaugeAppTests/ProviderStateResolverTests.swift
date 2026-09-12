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

    func testGeneralCodexQuotaWinsOverReserveRegardlessOfOrderOrPercentage() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reserve = window(
            id: "base_model_inference.primary", used: 0, duration: 10_080,
            reset: now.addingTimeInterval(86_400), displayName: "gpt-reserve")
        let general = window(id: "codex.primary", used: 92, duration: 10_080, reset: now.addingTimeInterval(86_400))
        for windows in [[reserve, general], [general, reserve]] {
            let state = ProviderViewState(
                snapshot: snapshot(provider: .codex, windows: windows, capturedAt: now),
                status: .ready, isRefreshing: false)
            XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: state)?.id, general.id)
            XCTAssertEqual(WindowVisibility.visible(windows, provider: .codex).first?.id, general.id)
        }
        let reserveOnly = ProviderViewState(
            snapshot: snapshot(provider: .codex, windows: [reserve], capturedAt: now),
            status: .ready, isRefreshing: false)
        XCTAssertNil(ProviderStateResolver.menuBarWindow(state: reserveOnly))
    }

    func testUnavailableOrOldQuotaNeverAppearsAsCurrentMenuBarBalance() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let usage = snapshot(
            provider: .claude,
            windows: [
                window(
                    id: "seven_day", used: 88,
                    duration: 10_080, reset: now)
            ], capturedAt: now)
        for status in [
            ProviderStatus.stale, .cancelled, .authenticationRequired, .credentialExpired, .accessDenied, .unavailable,
        ] {
            XCTAssertNil(
                ProviderStateResolver.menuBarWindow(
                    state:
                        ProviderViewState(snapshot: usage, status: status, isRefreshing: false)))
        }
    }

    func testCancellationRequiresBothNewActivityAndRestoredAccessToResume() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let usage = snapshot(
            provider: .claude,
            windows: [
                window(
                    id: "seven_day", used: 10,
                    duration: 10_080, reset: now.addingTimeInterval(86_400))
            ], capturedAt: now)
        for access in [
            ClaudeAccessState.live, .cached, .authenticationRequired, .credentialExpired, .accessDenied, .unavailable,
        ] {
            for activity in [nil, now.addingTimeInterval(-1), now, now.addingTimeInterval(1)] as [Date?] {
                let result = ClaudeUsageResult(snapshot: usage, access: access, lastActivityAt: activity)
                let expected = access == .live && (activity ?? .distantPast) > now
                XCTAssertEqual(ProviderStateResolver.shouldResumeClaude(result: result, cancelledAt: now), expected)
                let state = ProviderStateResolver.claudeState(result: result, cancelled: true)
                XCTAssertEqual(state.status, .cancelled)
                XCTAssertEqual(state.snapshot, usage)
            }
        }
    }

    @MainActor func testProviderChoiceAndCancellationSurviveRelaunch() {
        let suite = "TokenGaugeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UsageStore(defaults: defaults)
        XCTAssertEqual(first.primaryProvider, .codex)
        first.primaryProvider = .claude
        first.setClaudeCancelled(true)
        let relaunched = UsageStore(defaults: defaults)
        XCTAssertEqual(relaunched.primaryProvider, .claude)
        XCTAssertEqual(relaunched.orderedProviders, [.claude])
        XCTAssertEqual(relaunched.displayMode, .claude)
        XCTAssertEqual(relaunched.claudeCancelledAt, first.claudeCancelledAt)
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
