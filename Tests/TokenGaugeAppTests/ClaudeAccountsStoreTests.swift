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

    func testHiddenAccountsLeaveThePanelAndAreNotRead() async {
        let defaults = UserDefaults(suiteName: temporaryDefaultsSuite())!
        defaults.set(true, forKey: ClaudeAccountsStore.enabledKey)
        let reads = ReadCounter()
        let weekday = Weekday(7)
        let window = window
        let store = ClaudeAccountsStore(
            defaults: defaults,
            read: { _ in
                await reads.bump()
                return .windows([window])
            }, currentWeekday: { weekday.value })
        store.add()
        var account = store.accounts[0]
        account.name = "Work"
        account.location = "~/.claude-work"
        account.showsInMenuBar = true
        account.hiddenWeekdays = [1, 7]
        store.update(account)
        await store.refresh(account.id, force: true)
        var count = await reads.count
        XCTAssertEqual(count, 0)
        XCTAssertFalse(store.isShowing)
        XCTAssertTrue(store.menuBarAccounts.isEmpty)

        weekday.value = 2
        store.refreshAll()
        XCTAssertEqual(store.visibleAccounts, [account])
        await store.refresh(account.id, force: true)
        count = await reads.count
        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertEqual(store.menuBarAccounts.first?.letter, "W")

        account.hidden = true
        store.update(account)
        XCTAssertFalse(store.isShowing)
        XCTAssertEqual(store.state(for: account), ClaudeAccountState())
    }

    func testAPrimaryAccountReplacesThisMacInTheClaudeCard() async {
        let suite = temporaryDefaultsSuite()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: ClaudeAccountsStore.enabledKey)
        let weekday = Weekday(2)
        let window = window
        let store = ClaudeAccountsStore(
            defaults: defaults, read: { _ in .windows([window]) }, currentWeekday: { weekday.value })
        store.add()
        var account = store.accounts[0]
        account.name = "Main"
        account.location = "~/.claude-main"
        account.showsInMenuBar = true
        account.hidden = true
        store.update(account)

        store.setPrimary(account.id)
        XCTAssertFalse(store.accounts[0].hidden)
        await store.refresh(account.id, force: true)
        XCTAssertEqual(store.primaryAccount?.id, account.id)
        XCTAssertTrue(store.visibleAccounts.isEmpty)
        XCTAssertTrue(store.menuBarAccounts.isEmpty)
        XCTAssertEqual(store.primary?.name, "Main")
        XCTAssertEqual(store.primary?.state.status, .ready)
        XCTAssertEqual(store.primary?.state.snapshot?.windows, [window])

        let usage = UsageStore(defaults: UserDefaults(suiteName: temporaryDefaultsSuite())!, liveReadsEnabled: false)
        usage.setClaudePrimary(store.primary)
        XCTAssertEqual(usage.state(for: .claude).snapshot?.windows, [window])
        XCTAssertEqual(usage.claudeDisplayLabel, "Main")
        XCTAssertFalse(usage.usesLocalHistory(.claude))
        XCTAssertTrue(usage.usesLocalHistory(.codex))

        let reloaded = ClaudeAccountsStore(
            defaults: defaults, read: { _ in .windows([]) }, currentWeekday: { weekday.value })
        XCTAssertEqual(reloaded.primaryID, account.id)

        weekday.value = 1
        account = store.accounts[0]
        account.hiddenWeekdays = [1]
        store.update(account)
        store.refreshAll()
        XCTAssertNil(store.primary)
        usage.setClaudePrimary(store.primary)
        XCTAssertTrue(usage.usesLocalHistory(.claude))

        store.remove(account.id)
        XCTAssertNil(store.primaryID)
        XCTAssertNil(defaults.string(forKey: ClaudeAccountsStore.primaryKey))
    }

    func testAnAccountReadMapsToTheClaudeCardStatus() {
        let ready = ClaudeAccountState(status: .ready, windows: [window], capturedAt: now)
        XCTAssertEqual(ClaudeAccountsStore.viewState(ready, now: now).status, .ready)
        XCTAssertEqual(ClaudeAccountsStore.viewState(ClaudeAccountState(), now: now).status, .loading)
        XCTAssertEqual(
            ClaudeAccountsStore.viewState(ClaudeAccountState(status: .expired), now: now).status,
            .authenticationRequired)
        XCTAssertEqual(
            ClaudeAccountsStore.viewState(ClaudeAccountState(status: .noAccess), now: now).status, .accessDenied)
        let failed = ClaudeAccountsStore.viewState(ClaudeAccountState(status: .unreachable), now: now)
        XCTAssertEqual(failed.status, .unavailable)
        XCTAssertNil(failed.snapshot)
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

    func testTheLimitsHiddenForClaudeLeaveEveryAccountRow() {
        let weekly = QuotaWindow(
            id: "seven_day", usedPercentage: 10, resetsAt: nil, durationMinutes: 10_080, displayName: nil)
        let fable = QuotaWindow(
            id: "seven_day_fable", usedPercentage: 60, resetsAt: nil, durationMinutes: 10_080, displayName: "Fable")
        XCTAssertEqual(ClaudeAccountRow.columns([window, fable], hidden: [.modelWeekly]).map(\.id), ["five_hour"])
        XCTAssertEqual(
            ClaudeAccountRow.columns([weekly, fable, window], hidden: [.modelWeekly]).map(\.id),
            ["five_hour", "seven_day"])
        XCTAssertEqual(
            ClaudeAccountRow.columns([weekly, fable, window], hidden: [.session, .weekly]).map(\.id),
            ["seven_day_fable"])
    }

    func testTheDaysButtonSummarizesTheWeek() {
        var account = ClaudeExtraAccount(name: "Side", location: "~/.claude-side")
        let cases: [(Set<Int>, String, String)] = [
            ([], "Every day", "Todos los días"),
            ([7, 1], "Mon to Fri", "Lun a Vie"),
            ([1], "Mon to Sat", "Lun a Sáb"),
            ([2, 3, 4, 5, 6], "Sat and Sun", "Sáb y Dom"),
            ([2, 3, 4, 5, 6, 7], "Sun", "Dom"),
            ([3, 5, 7, 1], "3 days", "3 días"),
            ([3, 6], "5 days", "5 días"),
            (Set(1...7), "No days", "Ningún día"),
        ]
        withEachLanguage { language in
            account.hidden = false
            for (hidden, english, spanish) in cases {
                account.hiddenWeekdays = hidden
                XCTAssertEqual(AccountSchedule.summary(account), language == .english ? english : spanish)
            }
            account.hidden = true
            XCTAssertEqual(AccountSchedule.summary(account), language == .english ? "Hidden" : "Oculta")
        }
    }
}

extension ClaudeAccountsStoreTests {
    private func renewalStore(
        location: String, optIn: Bool, renewed: ClaudeExtraAccountResult?, renewals: ReadCounter
    ) -> (ClaudeAccountsStore, ClaudeExtraAccount) {
        let defaults = UserDefaults(suiteName: temporaryDefaultsSuite())!
        defaults.set(true, forKey: ClaudeAccountsStore.enabledKey)
        defaults.set(optIn, forKey: "claudeAutomaticRecovery")
        let store = ClaudeAccountsStore(
            defaults: defaults, read: { _ in .expired },
            renew: { _ in
                await renewals.bump()
                return renewed
            })
        store.add()
        var account = store.accounts[0]
        account.location = location
        store.update(account)
        return (store, account)
    }

    func testExpiredLocalLoginIsRenewedThroughTheCLIWhenOptedIn() async {
        let renewals = ReadCounter()
        let (store, account) = renewalStore(
            location: "~/.claude-work", optIn: true, renewed: .windows([window]), renewals: renewals)
        await store.refresh(account.id, force: true)
        let count = await renewals.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.state(for: account).status, .ready)
        XCTAssertEqual(store.state(for: account).windows, [window])
    }

    func testFailedRenewalShowsExpiredAndBacksOff() async {
        let renewals = ReadCounter()
        let (store, account) = renewalStore(
            location: "~/.claude-work", optIn: true, renewed: nil, renewals: renewals)
        await store.refresh(account.id, force: true)
        let state = store.state(for: account)
        XCTAssertEqual(state.status, .expired)
        XCTAssertEqual(state.renewalFailures, 1)
        XCTAssertGreaterThan(state.nextRenewal, Date().addingTimeInterval(290))
        let count = await renewals.count
        XCTAssertEqual(count, 1)
    }

    func testNoRenewalWithoutOptInOrForRemoteLogins() async {
        let renewals = ReadCounter()
        for (location, optIn) in [("~/.claude-work", false), ("other-mac:~/.claude-work", true)] {
            let (store, account) = renewalStore(
                location: location, optIn: optIn, renewed: .windows([window]), renewals: renewals)
            await store.refresh(account.id, force: true)
            XCTAssertEqual(store.state(for: account).status, .expired)
        }
        let count = await renewals.count
        XCTAssertEqual(count, 0)
    }
}

private final class Weekday: @unchecked Sendable {
    var value: Int
    init(_ value: Int) { self.value = value }
}

private actor ReadCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}
