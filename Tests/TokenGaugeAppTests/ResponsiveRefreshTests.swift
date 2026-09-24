import Combine
import Foundation
import TokenGaugeCore
import XCTest
import os

@testable import TokenGaugeApp

@MainActor
final class ResponsiveRefreshTests: XCTestCase {
    private let home = FileManager.default.temporaryDirectory
    private let codexUnavailable: @Sendable () -> ProviderViewState = {
        ProviderViewState(snapshot: nil, status: .unavailable, isRefreshing: false)
    }

    func testLiveQuotaIsPublishedBeforeTheActivityScanFinishes() async throws {
        try await withStoreDefaults { defaults in
            let now = Date()
            let previousBuckets = Fixture.modelBuckets([("claude-fable-5", 100)])
            let newBuckets = Fixture.modelBuckets([("claude-fable-5", 900)])
            let releaseActivity = DispatchSemaphore(value: 0)
            let refresher = UsageRefresher(
                homeDirectory: home,
                fetchClaude: { _, includeQuota, onQuota in
                    XCTAssertTrue(includeQuota)
                    onQuota(Self.result(used: 30, now: now, buckets: [], activity: false))
                    try? await BlockingWork.run { releaseActivity.wait() }
                    return Self.result(used: 30, now: now, buckets: newBuckets)
                }, fetchCodex: codexUnavailable)
            let store = UsageStore(
                refresher: refresher, defaults: defaults,
                initialSnapshots: [
                    Self.snapshot(used: 10, capturedAt: now.addingTimeInterval(-600), buckets: previousBuckets)
                ],
                historyReadsEnabled: false)
            let preview = expectation(description: "quota preview")
            preview.assertForOverFulfill = false
            let subscription = store.$claude.sink { state in
                if state.isRefreshing, state.snapshot?.windows.first?.usedPercentage == 30 { preview.fulfill() }
            }

            store.refresh(force: true)
            await fulfillment(of: [preview], timeout: 2)
            XCTAssertEqual(store.claude.status, .ready)
            XCTAssertEqual(store.claude.snapshot?.modelBuckets, previousBuckets)
            XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: store.claude)?.remainingPercentage, 70)

            releaseActivity.signal()
            try await waitUntilIdle(store)
            XCTAssertEqual(store.claude.snapshot?.modelBuckets, newBuckets)
            XCTAssertFalse(store.claude.isRefreshing)
            withExtendedLifetime(subscription) {}
        }
    }

    func testClaudeQuotaCallsAreBudgetedWhileActivityKeepsRefreshing() async throws {
        try await withStoreDefaults { defaults in
            let now = Date()
            let requests = OSAllocatedUnfairLock(initialState: [Bool]())
            let buckets = Fixture.modelBuckets([("claude-opus-5", 42)])
            let refresher = UsageRefresher(
                homeDirectory: home,
                fetchClaude: { _, includeQuota, _ in
                    requests.withLock { $0.append(includeQuota) }
                    guard includeQuota else {
                        return ClaudeUsageResult(
                            snapshot: Self.snapshot(used: 99, capturedAt: now, buckets: buckets),
                            access: .notRequested, lastActivityAt: nil)
                    }
                    return Self.result(used: 20, now: now, buckets: [])
                }, fetchCodex: codexUnavailable)
            let store = UsageStore(refresher: refresher, defaults: defaults, historyReadsEnabled: false)

            store.refresh(force: true)
            try await waitUntilIdle(store)
            store.refresh(force: true)
            try await waitUntilIdle(store)

            XCTAssertEqual(requests.withLock { $0 }, [true, false])
            XCTAssertEqual(store.claude.status, .ready)
            XCTAssertEqual(store.claude.snapshot?.windows.first?.usedPercentage, 20)
            XCTAssertEqual(store.claude.snapshot?.modelBuckets, buckets)
            let later = Date()
            XCTAssertFalse(store.claudeQuotaDue(force: true, now: later))
            XCTAssertTrue(store.claudeQuotaDue(force: true, now: later.addingTimeInterval(61)))
            XCTAssertFalse(store.claudeQuotaDue(force: false, now: later.addingTimeInterval(61)))
            XCTAssertTrue(store.claudeQuotaDue(force: false, now: later.addingTimeInterval(271)))
        }
    }

    func testRateLimitKeepsARecentLiveReadingAndBacksOff() async throws {
        try await withStoreDefaults { defaults in
            let now = Date()
            let refresher = UsageRefresher(
                homeDirectory: home,
                fetchClaude: { _, _, _ in
                    ClaudeUsageResult(
                        snapshot: Self.snapshot(used: 50, capturedAt: now.addingTimeInterval(-3_000)),
                        access: .rateLimited, lastActivityAt: nil)
                }, fetchCodex: codexUnavailable)
            let store = UsageStore(
                refresher: refresher, defaults: defaults,
                initialSnapshots: [Self.snapshot(used: 25, capturedAt: now.addingTimeInterval(-120))],
                historyReadsEnabled: false)

            store.refresh(force: true)
            try await waitUntilIdle(store)

            XCTAssertEqual(store.claude.status, .ready)
            XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: store.claude)?.remainingPercentage, 75)
            let later = Date()
            XCTAssertFalse(store.claudeQuotaDue(force: true, now: later.addingTimeInterval(120)))
            XCTAssertTrue(store.claudeQuotaDue(force: true, now: later.addingTimeInterval(301)))
        }
    }

    func testRateLimitDegradesAReadingOlderThanFifteenMinutes() async throws {
        try await withStoreDefaults { defaults in
            let now = Date()
            let refresher = UsageRefresher(
                homeDirectory: home,
                fetchClaude: { _, _, _ in
                    ClaudeUsageResult(
                        snapshot: Self.snapshot(used: 25, capturedAt: now.addingTimeInterval(-1_000)),
                        access: .rateLimited, lastActivityAt: nil)
                }, fetchCodex: codexUnavailable)
            let store = UsageStore(
                refresher: refresher, defaults: defaults,
                initialSnapshots: [Self.snapshot(used: 25, capturedAt: now.addingTimeInterval(-1_000))],
                historyReadsEnabled: false)

            store.refresh(force: true)
            try await waitUntilIdle(store)

            XCTAssertEqual(store.claude.status, .stale)
            XCTAssertNil(ProviderStateResolver.menuBarWindow(state: store.claude))
        }
    }

    func testAccountSwitchClearsTheOldQuotaAndRejectsResultsForTheOldAccount() async throws {
        try await withStoreDefaults { defaults in
            let now = Date()
            let first = ClaudeAccountIdentity(accountUuid: "first", emailAddress: "first@example.com")
            let second = ClaudeAccountIdentity(accountUuid: "second", emailAddress: "second@example.com")
            let current = OSAllocatedUnfairLock(initialState: first)
            let refresher = UsageRefresher(
                homeDirectory: home,
                fetchClaude: { _, _, _ in
                    let identity = current.withLock { $0 }
                    return ClaudeUsageResult(
                        snapshot: Self.snapshot(used: identity == first ? 10 : 60, capturedAt: now),
                        access: .live, lastActivityAt: nil, accountFingerprint: identity.fingerprint,
                        accountLabel: identity.label)
                }, fetchCodex: codexUnavailable)
            let store = UsageStore(
                refresher: refresher, defaults: defaults, historyReadsEnabled: true, archiveWork: { _, _, _ in })
            store.eventRefreshDelay = .milliseconds(10)

            store.refresh(force: true)
            try await waitUntilIdle(store)
            XCTAssertEqual(store.claudeAccountLabel, "first@example.com")
            XCTAssertEqual(store.claude.status, .ready)

            store.claudeConfigChanged(second)
            XCTAssertEqual(store.claudeAccountLabel, "second@example.com")
            XCTAssertEqual(store.claude.status, .loading)
            XCTAssertNil(store.claude.snapshot)
            try await Task.sleep(for: .milliseconds(50))
            try await waitUntilIdle(store)
            XCTAssertEqual(store.claude.status, .loading)
            XCTAssertEqual(store.claudeAccountLabel, "second@example.com")

            current.withLock { $0 = second }
            store.refresh(force: true)
            try await waitUntilIdle(store)
            XCTAssertEqual(store.claude.status, .ready)
            XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: store.claude)?.remainingPercentage, 40)
            XCTAssertEqual(store.claudeAccountFingerprint, second.fingerprint)
        }
    }

    func testStatusLineCaptureRaisesUsageOnlyForTheSameAccountAndWindow() {
        let now = Date()
        let session = now.addingTimeInterval(3_600)
        let weekly = now.addingTimeInterval(200_000)
        let snapshot = Fixture.snapshot(
            .claude,
            windows: [
                Fixture.window(id: "five_hour", usedPercentage: 40, resetsAt: session, durationMinutes: 300),
                Fixture.window(id: "seven_day", usedPercentage: 30, resetsAt: weekly, durationMinutes: 10_080),
                Fixture.window(
                    id: "seven_day_fable", usedPercentage: 10, resetsAt: weekly, durationMinutes: 10_080,
                    displayName: "Fable"),
            ], capturedAt: now.addingTimeInterval(-120))
        func capture(
            _ fiveHour: Double, _ sevenDay: Double, capturedAt: TimeInterval = -10, shift: TimeInterval = 1,
            account: String? = "account"
        ) -> ClaudeCapturedSnapshot {
            ClaudeCapturedSnapshot(
                capturedAt: now.addingTimeInterval(capturedAt),
                windows: [
                    "five_hour": ClaudeCapturedWindow(
                        usedPercentage: fiveHour, resetsAt: session.addingTimeInterval(shift)),
                    "seven_day": ClaudeCapturedWindow(usedPercentage: sevenDay, resetsAt: weekly),
                ], accountFingerprint: account)
        }

        let raised = ProviderStateResolver.overlay(
            snapshot, capture: capture(55, 35), accountFingerprint: "account", now: now)
        XCTAssertEqual(raised?.windows.map(\.usedPercentage), [55, 35, 10])
        XCTAssertEqual(raised?.capturedAt, snapshot.capturedAt)

        let partial = ProviderStateResolver.overlay(
            snapshot, capture: capture(55, 20, shift: 600), accountFingerprint: "account", now: now)
        XCTAssertNil(partial)
        for rejected in [
            capture(55, 35, account: "other"), capture(55, 35, account: nil), capture(55, 35, capturedAt: -600),
            capture(30, 20),
        ] {
            XCTAssertNil(
                ProviderStateResolver.overlay(snapshot, capture: rejected, accountFingerprint: "account", now: now))
        }
        XCTAssertNil(
            ProviderStateResolver.overlay(snapshot, capture: capture(55, 35), accountFingerprint: nil, now: now))
    }

    func testStoreAppliesTheCaptureOverlayToTheMenuBarWithoutACall() throws {
        try withDefaults { defaults in
            let now = Date()
            let identity = ClaudeAccountIdentity(accountUuid: "overlay", emailAddress: "overlay@example.com")
            let store = UsageStore(
                defaults: defaults,
                initialSnapshots: [Self.snapshot(used: 20, capturedAt: now.addingTimeInterval(-60))],
                historyReadsEnabled: false)
            store.claudeConfigChanged(identity)
            store.captureChanged(
                ClaudeCapturedSnapshot(
                    capturedAt: now,
                    windows: ["seven_day": ClaudeCapturedWindow(usedPercentage: 45, resetsAt: Self.weeklyReset)],
                    accountFingerprint: identity.fingerprint))
            XCTAssertEqual(ProviderStateResolver.menuBarWindow(state: store.claude)?.remainingPercentage, 55)
            XCTAssertEqual(store.claude.status, .ready)
            XCTAssertFalse(store.isRefreshing)
        }
    }

    func testCodexHomeHonorsAnAbsoluteCodexHome() {
        let home = URL(filePath: "/Users/example")
        XCTAssertEqual(UsageStore.codexHome(home, environment: [:]).path, "/Users/example/.codex")
        XCTAssertEqual(UsageStore.codexHome(home, environment: ["CODEX_HOME": "/tmp/codex"]).path, "/tmp/codex")
        XCTAssertEqual(
            UsageStore.codexHome(home, environment: ["CODEX_HOME": "relative"]).path, "/Users/example/.codex")
    }

    nonisolated private static let weeklyReset = Date().addingTimeInterval(200_000)

    nonisolated private static func snapshot(
        used: Double, capturedAt: Date, buckets: [ModelTokenBucket] = [], activity: Bool = true
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude,
            windows: [
                QuotaWindow(
                    id: "seven_day", usedPercentage: used, resetsAt: weeklyReset, durationMinutes: 10_080,
                    displayName: nil)
            ],
            dailyUsage: ModelTokenAggregator.daily(buckets), summary: nil, availableResetCredits: nil,
            creditBalance: nil, capturedAt: capturedAt, modelBuckets: buckets, activityReadSucceeded: activity)
    }

    nonisolated private static func result(
        used: Double, now: Date, buckets: [ModelTokenBucket], activity: Bool = true
    ) -> ClaudeUsageResult {
        ClaudeUsageResult(
            snapshot: snapshot(used: used, capturedAt: now, buckets: buckets, activity: activity), access: .live,
            lastActivityAt: nil)
    }

    private func waitUntilIdle(_ store: UsageStore) async throws {
        for _ in 0..<400 where store.isRefreshing {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(store.isRefreshing)
    }

    private func withStoreDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "TokenGauge.responsive-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }
}
