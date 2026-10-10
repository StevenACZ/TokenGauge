import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ClaudeAccountsStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let window = QuotaWindow(
        id: "five_hour", usedPercentage: 20, resetsAt: nil, durationMinutes: 300, displayName: nil)

    func testReadyReadingSchedulesTheNextReadAndClearsFailures() {
        var previous = ClaudeAccountState()
        previous.failures = 3
        let state = ClaudeAccountsStore.apply(.windows([window]), to: previous, at: now)
        XCTAssertEqual(state.status, .ready)
        XCTAssertEqual(state.failures, 0)
        XCTAssertEqual(state.nextRead, now.addingTimeInterval(ClaudeAccountsStore.interval))
    }

    func testRateLimitKeepsTheLastReadingAndBacksOff() {
        let ready = ClaudeAccountsStore.apply(.windows([window]), to: ClaudeAccountState(), at: now)
        let first = ClaudeAccountsStore.apply(.rateLimited(retryAfter: nil), to: ready, at: now)
        XCTAssertEqual(first.status, .ready)
        XCTAssertEqual(first.windows, [window])
        XCTAssertEqual(first.nextRead, now.addingTimeInterval(300))
        var state = first
        for _ in 0..<5 { state = ClaudeAccountsStore.apply(.rateLimited(retryAfter: nil), to: state, at: now) }
        XCTAssertEqual(state.nextRead, now.addingTimeInterval(1800))
        XCTAssertEqual(
            ClaudeAccountsStore.apply(.rateLimited(retryAfter: nil), to: ClaudeAccountState(), at: now).status,
            .rateLimited)
    }

    func testRateLimitWaitsAtLeastWhatTheServerAsks() {
        let first = ClaudeAccountsStore.apply(.rateLimited(retryAfter: 1206), to: ClaudeAccountState(), at: now)
        XCTAssertEqual(first.nextRead, now.addingTimeInterval(1206))
        let short = ClaudeAccountsStore.apply(.rateLimited(retryAfter: 30), to: first, at: now)
        XCTAssertEqual(short.nextRead, now.addingTimeInterval(600))
    }

    func testOpeningThePanelReadsEarlyOnlyWhenNotRateLimited() {
        let ready = ClaudeAccountsStore.apply(.windows([window]), to: ClaudeAccountState(), at: now)
        let panelOpen = now.addingTimeInterval(ClaudeAccountsStore.minimumGap)
        XCTAssertFalse(ClaudeAccountsStore.isDue(ready, at: panelOpen, force: false))
        XCTAssertTrue(ClaudeAccountsStore.isDue(ready, at: panelOpen, force: true))
        let limited = ClaudeAccountsStore.apply(.rateLimited(retryAfter: nil), to: ready, at: now)
        XCTAssertEqual(limited.status, .ready)
        XCTAssertFalse(ClaudeAccountsStore.isDue(limited, at: limited.nextRead.addingTimeInterval(-1), force: true))
        XCTAssertTrue(ClaudeAccountsStore.isDue(limited, at: limited.nextRead, force: true))
    }

    func testFailuresDropTheReadingAndNameTheCause() {
        let ready = ClaudeAccountsStore.apply(.windows([window]), to: ClaudeAccountState(), at: now)
        XCTAssertEqual(ClaudeAccountsStore.apply(.status(401), to: ready, at: now).status, .signedOut)
        XCTAssertEqual(ClaudeAccountsStore.apply(.status(403), to: ready, at: now).status, .noAccess)
        let expired = ClaudeAccountsStore.apply(.expired, to: ready, at: now)
        XCTAssertEqual(expired.status, .expired)
        XCTAssertTrue(expired.windows.isEmpty)
        let lost = ClaudeAccountsStore.apply(.unreachable, to: ready, at: now)
        XCTAssertEqual(lost.status, .unreachable)
        XCTAssertTrue(lost.windows.isEmpty)
    }

    func testAccountsPersistAndStayOffUntilEnabled() async {
        let suite = temporaryDefaultsSuite()
        let defaults = UserDefaults(suiteName: suite)!
        let reads = ReadCounter()
        let store = ClaudeAccountsStore(defaults: defaults) { _ in
            await reads.bump()
            return .windows([])
        }
        XCTAssertFalse(store.enabled)
        store.add()
        var account = store.accounts[0]
        account.name = "Side"
        account.location = "~/.claude-side"
        account.tint = .violet
        store.update(account)
        await store.refresh(account.id, force: true)
        let blocked = await reads.count
        XCTAssertEqual(blocked, 0)

        let reloaded = ClaudeAccountsStore(defaults: defaults) { _ in .windows([]) }
        XCTAssertEqual(reloaded.accounts, [account])
        XCTAssertFalse(reloaded.isShowing)
    }

    func testInvalidLocationNeverRunsAProcess() async {
        let defaults = UserDefaults(suiteName: temporaryDefaultsSuite())!
        defaults.set(true, forKey: ClaudeAccountsStore.enabledKey)
        let reads = ReadCounter()
        let store = ClaudeAccountsStore(defaults: defaults) { _ in
            await reads.bump()
            return .windows([])
        }
        store.add()
        var account = store.accounts[0]
        account.location = "-oProxyCommand=x:~/.claude"
        store.update(account)
        await store.refresh(account.id, force: true)
        XCTAssertEqual(store.state(for: account).status, .invalidLocation)
        let count = await reads.count
        XCTAssertEqual(count, 0)
    }

    func testTheSessionAndTheTightestWeeklyFillTheRow() {
        let weekly = QuotaWindow(
            id: "seven_day", usedPercentage: 10, resetsAt: nil, durationMinutes: 10_080, displayName: nil)
        let fable = QuotaWindow(
            id: "seven_day_fable", usedPercentage: 60, resetsAt: nil, durationMinutes: 10_080, displayName: "Fable")
        XCTAssertEqual(ClaudeAccountRow.columns([weekly, fable, window]).map(\.id), ["five_hour", "seven_day_fable"])
    }
}

private actor ReadCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}
