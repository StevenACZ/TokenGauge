import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ProviderCancellationTests: XCTestCase {
    func testManualCancellationIsIndependentAndPreservesProviderAndHistory() {
        withDefaults { defaults in
            let store = UsageStore(defaults: defaults, initialSnapshots: UsageProvider.allCases.map { snapshot($0) })
            for provider in UsageProvider.allCases {
                store.primaryProvider = provider
                store.setCancelled(true, for: provider)
                XCTAssertEqual(store.primaryProvider, provider)
                XCTAssertEqual(store.state(for: provider).status, .cancelled)
                XCTAssertNotNil(store.state(for: provider).snapshot)
                XCTAssertNil(store.menuBarWindow)
                let relaunched = UsageStore(defaults: defaults)
                XCTAssertTrue(relaunched.isCancelled(provider: provider))
                XCTAssertEqual(relaunched.state(for: provider).status, .cancelled)
                XCTAssertEqual(relaunched.primaryProvider, provider)
                if provider == .claude { XCTAssertFalse(store.isCancelled(provider: .codex)) }
            }
            XCTAssertTrue(store.isCancelled(provider: .claude))
            XCTAssertTrue(store.isCancelled(provider: .codex))
        }
    }

    func testBothProvidersRequireBaselineThenNewActivityAndPersistResume() {
        for provider in UsageProvider.allCases {
            withDefaults { defaults in
                let store = UsageStore(defaults: defaults)
                store.primaryProvider = provider
                store.setCancelled(true, for: provider)
                apply(store, provider: provider, tokens: 1_000)
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 1_000)
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 100)
                XCTAssertTrue(store.isCancelled(provider: provider))
                let relaunched = UsageStore(defaults: defaults)
                apply(relaunched, provider: provider, tokens: 1_000)
                XCTAssertTrue(relaunched.isCancelled(provider: provider))
                apply(relaunched, provider: provider, tokens: 1_001)
                XCTAssertFalse(relaunched.isCancelled(provider: provider))
                XCTAssertEqual(relaunched.primaryProvider, provider)
                XCTAssertEqual(relaunched.state(for: provider).status, .ready)
                XCTAssertFalse(UsageStore(defaults: defaults).isCancelled(provider: provider))
                XCTAssertNil(defaults.object(forKey: "\(provider.rawValue)CancellationDailyBaseline"))
                relaunched.setCancelled(true, for: provider)
                apply(relaunched, provider: provider, tokens: 2_000)
                XCTAssertTrue(relaunched.isCancelled(provider: provider))
            }
        }
    }

    func testFailuresCannotInitializeOrTriggerBaselineOrEraseHistory() {
        for provider in UsageProvider.allCases {
            withDefaults { defaults in
                let store = UsageStore(defaults: defaults, initialSnapshots: [snapshot(provider)])
                store.setCancelled(true, for: provider)
                for access in [ClaudeAccessState.cached, .authenticationRequired, .accessDenied, .unavailable] {
                    apply(store, provider: provider, tokens: 50, access: access)
                    XCTAssertNil(defaults.object(forKey: "\(provider.rawValue)CancellationDailyBaseline"))
                    XCTAssertTrue(store.isCancelled(provider: provider))
                }
                apply(store, provider: provider, tokens: 100)
                for access in [ClaudeAccessState.cached, .authenticationRequired, .accessDenied, .unavailable] {
                    apply(store, provider: provider, tokens: 200, access: access)
                    XCTAssertTrue(store.isCancelled(provider: provider))
                }
                store.applyRefreshResults(
                    claudeResult: nil,
                    codexState: ProviderViewState(snapshot: nil, status: .unavailable, isRefreshing: false))
                XCTAssertNotNil(store.state(for: provider).snapshot)
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 100)
                XCTAssertTrue(store.isCancelled(provider: provider))
            }
        }
    }

    func testLegacyCancellationIgnoresOldDaysAndEmptyQuota() {
        for provider in UsageProvider.allCases {
            withDefaults { defaults in
                let cancellation = Date()
                defaults.set(cancellation, forKey: "\(provider.rawValue)CancelledAt")
                let store = UsageStore(defaults: defaults)
                XCTAssertEqual(provider == .claude ? store.claudeCancelledAt : store.codexCancelledAt, cancellation)
                apply(store, provider: provider, tokens: 10, windows: false)
                XCTAssertNil(defaults.object(forKey: "\(provider.rawValue)CancellationDailyBaseline"))
                apply(store, provider: provider, tokens: 10, day: "2000-01-01")
                apply(store, provider: provider, tokens: 100, day: "2000-01-01")
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 1)
                XCTAssertFalse(store.isCancelled(provider: provider))
            }
        }
    }

    func testLiveQuotaWithFailedActivityCannotCreateBaselineOrResumeEitherProvider() {
        for provider in UsageProvider.allCases {
            withDefaults { defaults in
                let store = UsageStore(defaults: defaults)
                store.setCancelled(true, for: provider)
                apply(store, provider: provider, tokens: 0, activityReadSucceeded: false)
                XCTAssertTrue(store.isCancelled(provider: provider))
                XCTAssertNil(defaults.object(forKey: "\(provider.rawValue)CancellationDailyBaseline"))
                apply(store, provider: provider, tokens: 1_000)
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 2_000, activityReadSucceeded: false)
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 1_000)
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 1_001)
                XCTAssertFalse(store.isCancelled(provider: provider))
            }
        }
    }

    func testObservationStartedBeforeCancellationCannotInitializeOrTriggerBaseline() {
        for provider in UsageProvider.allCases {
            withDefaults { defaults in
                let cancellation = Date()
                defaults.set(cancellation, forKey: "\(provider.rawValue)CancelledAt")
                let store = UsageStore(defaults: defaults)
                for capturedAt in [cancellation.addingTimeInterval(-1), cancellation] {
                    apply(store, provider: provider, tokens: 0, capturedAt: capturedAt)
                    XCTAssertNil(defaults.object(forKey: "\(provider.rawValue)CancellationDailyBaseline"))
                }
                apply(store, provider: provider, tokens: 1_000)
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 2_000, capturedAt: cancellation.addingTimeInterval(-1))
                XCTAssertTrue(store.isCancelled(provider: provider))
                apply(store, provider: provider, tokens: 1_001)
                XCTAssertFalse(store.isCancelled(provider: provider))
            }
        }
    }

    private func apply(
        _ store: UsageStore, provider: UsageProvider, tokens: Int,
        access: ClaudeAccessState = .live, day: String? = nil, windows: Bool = true,
        activityReadSucceeded: Bool = true, capturedAt: Date? = nil
    ) {
        let usage = snapshot(
            provider, tokens: tokens, day: day, windows: windows,
            activityReadSucceeded: activityReadSucceeded, capturedAt: capturedAt)
        store.applyRefreshResults(
            claudeResult: provider == .claude
                ? ClaudeUsageResult(snapshot: usage, access: access, lastActivityAt: nil) : nil,
            codexState: ProviderViewState(
                snapshot: provider == .codex ? usage : nil,
                status: access == .live ? (windows ? .ready : .waiting) : .stale,
                isRefreshing: false))
    }

    private func snapshot(
        _ provider: UsageProvider, tokens: Int = 100, day: String? = nil, windows: Bool = true,
        activityReadSucceeded: Bool = true, capturedAt: Date? = nil
    ) -> ProviderUsageSnapshot {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return ProviderUsageSnapshot(
            provider: provider,
            windows: windows
                ? [
                    QuotaWindow(
                        id: "\(provider.rawValue).weekly", usedPercentage: 20,
                        resetsAt: Date().addingTimeInterval(86_400), durationMinutes: 10_080, displayName: nil)
                ] : [],
            dailyUsage: [DailyTokenUsage(day: day ?? formatter.string(from: Date()), tokens: tokens)],
            summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: capturedAt ?? Date(),
            activityReadSucceeded: activityReadSucceeded)
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "TokenGaugeCancellationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
