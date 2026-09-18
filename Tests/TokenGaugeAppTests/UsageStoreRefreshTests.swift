import Combine
import Foundation
import TokenGaugeCore
import XCTest
import os

@testable import TokenGaugeApp

@MainActor
final class UsageStoreRefreshTests: XCTestCase {
    func testRefreshPublishesEachProviderOnce() async throws {
        try await withDefaults { defaults in
            let now = Date()
            let claudeSnapshot = snapshot(.claude, now: now)
            let codexSnapshot = snapshot(.codex, now: now)
            let refresher = UsageRefresher(
                homeDirectory: FileManager.default.temporaryDirectory,
                fetchClaude: { _ in ClaudeUsageResult(snapshot: claudeSnapshot, access: .live, lastActivityAt: now) },
                fetchCodex: { ProviderViewState(snapshot: codexSnapshot, status: .ready, isRefreshing: false) })
            let store = UsageStore(
                refresher: refresher, defaults: defaults, initialSnapshots: [claudeSnapshot, codexSnapshot],
                historyReadsEnabled: false)
            var claudePublishes: [ProviderViewState] = []
            var codexPublishes: [ProviderViewState] = []
            let subscriptions = [
                store.$claude.dropFirst().sink { claudePublishes.append($0) },
                store.$codex.dropFirst().sink { codexPublishes.append($0) },
            ]

            store.refresh(force: true)
            try await waitUntilIdle(store)

            XCTAssertEqual(claudePublishes.map(\.isRefreshing), [true, false])
            XCTAssertEqual(codexPublishes.map(\.isRefreshing), [true, false])
            XCTAssertEqual(store.claude.status, .ready)
            XCTAssertEqual(store.codex.status, .ready)
            XCTAssertEqual(store.claude.snapshot, claudeSnapshot)
            XCTAssertEqual(store.codex.snapshot, codexSnapshot)
            XCTAssertNotNil(store.lastRefresh)
            withExtendedLifetime(subscriptions) {}
        }
    }

    func testUnforcedRefreshWaitsAMinuteAndForcedRefreshFetchesAgain() async throws {
        try await withDefaults { defaults in
            let fetches = OSAllocatedUnfairLock(initialState: 0)
            let refresher = UsageRefresher(
                homeDirectory: FileManager.default.temporaryDirectory,
                fetchClaude: { _ in
                    fetches.withLock { $0 += 1 }
                    return nil
                },
                fetchCodex: { ProviderViewState(snapshot: nil, status: .unavailable, isRefreshing: false) })
            let store = UsageStore(refresher: refresher, defaults: defaults, historyReadsEnabled: false)

            store.refresh(force: true)
            try await waitUntilIdle(store)
            XCTAssertEqual(fetches.withLock { $0 }, 1)
            XCTAssertEqual(store.claude.status, .unavailable)

            store.refresh()
            XCTAssertFalse(store.isRefreshing)
            XCTAssertEqual(fetches.withLock { $0 }, 1)

            store.refresh(force: true)
            try await waitUntilIdle(store)
            XCTAssertEqual(fetches.withLock { $0 }, 2)
        }
    }

    func testCodexOutcomeIsPublishedBeforeClaudeResolves() async throws {
        try await withDefaults { defaults in
            let now = Date()
            let claudeSnapshot = snapshot(.claude, now: now)
            let codexSnapshot = snapshot(.codex, now: now)
            let releaseClaude = DispatchSemaphore(value: 0)
            let refresher = UsageRefresher(
                homeDirectory: FileManager.default.temporaryDirectory,
                fetchClaude: { _ in
                    releaseClaude.wait()
                    return ClaudeUsageResult(snapshot: claudeSnapshot, access: .live, lastActivityAt: now)
                },
                fetchCodex: { ProviderViewState(snapshot: codexSnapshot, status: .ready, isRefreshing: false) })
            let store = UsageStore(
                refresher: refresher, defaults: defaults, initialSnapshots: [claudeSnapshot, codexSnapshot],
                historyReadsEnabled: false)
            let codexPublished = expectation(description: "codex result published")
            var claudePublishes: [ProviderViewState] = []
            var codexPublishes: [ProviderViewState] = []
            let subscriptions = [
                store.$claude.dropFirst().sink { claudePublishes.append($0) },
                store.$codex.dropFirst().sink {
                    codexPublishes.append($0)
                    if !$0.isRefreshing { codexPublished.fulfill() }
                },
            ]

            store.refresh(force: true)
            await fulfillment(of: [codexPublished], timeout: 2)

            XCTAssertEqual(codexPublishes.map(\.isRefreshing), [true, false])
            XCTAssertEqual(store.codex.status, .ready)
            XCTAssertEqual(store.codex.snapshot, codexSnapshot)
            XCTAssertEqual(claudePublishes.map(\.isRefreshing), [true])
            XCTAssertTrue(store.claude.isRefreshing)
            XCTAssertTrue(store.isRefreshing)

            releaseClaude.signal()
            try await waitUntilIdle(store)

            XCTAssertEqual(claudePublishes.map(\.isRefreshing), [true, false])
            XCTAssertEqual(codexPublishes.map(\.isRefreshing), [true, false])
            XCTAssertEqual(store.claude.status, .ready)
            XCTAssertNotNil(store.lastRefresh)
            withExtendedLifetime(subscriptions) {}
        }
    }

    func testDayKeyMatchesTheLegacyFormatterAndFollowsTheCalendarTimeZone() {
        let utc = calendar("UTC")
        let tokyo = calendar("Asia/Tokyo")
        let lima = calendar("America/Lima")
        let date = utc.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 23, minute: 30))!

        XCTAssertEqual(UsageStore.dayKey(for: date, calendar: utc), "2026-09-17")
        XCTAssertEqual(UsageStore.dayKey(for: date, calendar: tokyo), "2026-09-18")
        XCTAssertEqual(UsageStore.dayKey(for: date, calendar: lima), "2026-09-17")

        for calendar in [utc, tokyo, lima] {
            let legacy = DateFormatter()
            legacy.locale = Locale(identifier: "en_US_POSIX")
            legacy.calendar = Calendar(identifier: .gregorian)
            legacy.timeZone = calendar.timeZone
            legacy.dateFormat = "yyyy-MM-dd"
            for offset: TimeInterval in [0, 1_800, 86_400 * 100, -86_400 * 400, 86_400 * 3_650] {
                let probe = date.addingTimeInterval(offset)
                XCTAssertEqual(UsageStore.dayKey(for: probe, calendar: calendar), legacy.string(from: probe))
            }
        }
    }

    private func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func waitUntilIdle(_ store: UsageStore) async throws {
        for _ in 0..<400 where store.isRefreshing {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(store.isRefreshing)
    }

    private func snapshot(_ provider: UsageProvider, now: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: [
                QuotaWindow(
                    id: "\(provider.rawValue).weekly", usedPercentage: 20, resetsAt: now.addingTimeInterval(86_400),
                    durationMinutes: 10_080, displayName: nil)
            ],
            dailyUsage: [DailyTokenUsage(day: "2026-09-17", tokens: 100)],
            summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: now,
            activityReadSucceeded: true)
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "TokenGauge.refresh-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }
}
