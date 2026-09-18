import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class HistoryDashboardTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        return value
    }

    func testWeekNavigationUsesMondayAcrossTheYearBoundary() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let week = HistoryDashboardModel.interval(mode: .week, offset: 0, now: now, calendar: calendar)
        XCTAssertEqual(HistoryDashboardModel.dayKey(week.start, calendar: calendar), "2025-12-29")
        XCTAssertEqual(HistoryDashboardModel.dayKey(week.end, calendar: calendar), "2026-01-05")
        let previous = HistoryDashboardModel.interval(mode: .week, offset: -1, now: now, calendar: calendar)
        XCTAssertEqual(HistoryDashboardModel.dayKey(previous.start, calendar: calendar), "2025-12-22")
    }

    func testDayKeysMatchTheWriterEvenWithANonGregorianCurrentCalendar() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = .current
        for offset in stride(from: -86_400 * 400, through: 86_400 * 400, by: 86_400 * 37) {
            let date = Date().addingTimeInterval(Double(offset))
            XCTAssertEqual(HistoryDashboardModel.dayKey(date), UsageStore.dayKey(for: date))
            XCTAssertNotEqual(HistoryDashboardModel.dayKey(date, calendar: japanese), UsageStore.dayKey(for: date))
        }
    }

    func testLeapYearIncludesEveryDateButDoesNotInventZeroDays() {
        let now = calendar.date(from: DateComponents(year: 2024, month: 7, day: 1))!
        let year = HistoryDashboardModel.interval(mode: .calendar, offset: 0, now: now, calendar: calendar)
        let days = HistoryDashboardModel.makeDays(interval: year, tokens: [], efforts: [], calendar: calendar)
        XCTAssertEqual(days.count, 366)
        XCTAssertTrue(days.contains { $0.id == "2024-02-29" })
        XCTAssertTrue(days.allSatisfy { $0.total(for: [.codex, .claude]) == nil })
    }

    func testObservedSourcesAreNeverAddedTwiceAndZeroRemainsDistinct() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let interval = HistoryDashboardModel.interval(mode: .recent, offset: 0, now: now, calendar: calendar)
        let days = HistoryDashboardModel.makeDays(
            interval: interval,
            tokens: [
                HistoryTokenRow(day: "2026-09-12", provider: .codex, model: "all", tokens: 100),
                HistoryTokenRow(day: "2026-09-12", provider: .codex, model: "gpt-6-astra", tokens: 60),
                HistoryTokenRow(day: "2026-09-11", provider: .codex, model: "all", tokens: 0),
            ],
            efforts: [
                HistoryEffortRow(
                    day: "2026-09-12", provider: .codex, model: "gpt-6-astra", effort: "medium", tokens: 150)
            ], calendar: calendar)
        XCTAssertEqual(days.last?.tokens(for: .codex), 150)
        XCTAssertEqual(days.first { $0.id == "2026-09-11" }?.tokens(for: .codex), 0)
        XCTAssertNil(days.last?.tokens(for: .claude))
        XCTAssertNil(days.first { $0.id == "2026-09-10" }?.tokens(for: .codex))
    }

    func testHiddenProviderCannotAffectScopedTotalsOrDominance() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let interval = HistoryDashboardModel.interval(mode: .recent, offset: 0, now: now, calendar: calendar)
        let days = HistoryDashboardModel.makeDays(
            interval: interval,
            tokens: [
                HistoryTokenRow(day: "2026-09-07", provider: .claude, model: "all", tokens: 50),
                HistoryTokenRow(day: "2026-09-07", provider: .codex, model: "all", tokens: 9_000_000),
            ], efforts: [], calendar: calendar)
        let day = try XCTUnwrap(days.last)
        XCTAssertEqual(day.id, "2026-09-07")
        XCTAssertEqual(day.total(for: [.claude]), 50)
        XCTAssertEqual(day.total(for: [.codex]), 9_000_000)
        XCTAssertEqual(day.total(for: [.claude, .codex]), 9_000_050)
        XCTAssertEqual(day.dominantProviders(for: [.claude]), [.claude])
        XCTAssertEqual(day.dominantProviders(for: [.codex, .claude]), [.codex])
    }

    func testEffortOnlyHistoryHasAUsableObservedTotal() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let interval = HistoryDashboardModel.interval(mode: .recent, offset: 0, now: now, calendar: calendar)
        let days = HistoryDashboardModel.makeDays(
            interval: interval, tokens: [],
            efforts: [
                HistoryEffortRow(
                    day: "2026-09-12", provider: .claude, model: "claude-fable", effort: "high", tokens: 10),
                HistoryEffortRow(
                    day: "2026-09-12", provider: .claude, model: "claude-fable", effort: "xhigh", tokens: 20),
            ], calendar: calendar)
        XCTAssertEqual(days.last?.tokens(for: .claude), 30)
    }

    func testPaceImmediatelyRejectsResetOrDecreaseBeforeHistoryReloads() {
        let now = Date()
        let reset = now.addingTimeInterval(86400)
        let pace = QuotaPace(
            pointsPerHour: 5, observedMinutes: 40, sampledAt: now,
            resetsAt: reset, lastUsedPercentage: 20)
        func window(_ used: Double, reset: Date) -> QuotaWindow {
            QuotaWindow(
                id: "weekly", usedPercentage: used, resetsAt: reset,
                durationMinutes: 10080, displayName: nil)
        }
        XCTAssertNotNil(
            HistoryDashboardModel.usablePace(pace, for: window(21, reset: reset), capturedAt: now, now: now))
        XCTAssertNotNil(
            HistoryDashboardModel.usablePace(
                pace, for: window(21, reset: reset.addingTimeInterval(0.6)), capturedAt: now, now: now))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(
                pace, for: window(21, reset: reset.addingTimeInterval(2)), capturedAt: now, now: now))
        XCTAssertNil(HistoryDashboardModel.usablePace(pace, for: window(19, reset: reset), capturedAt: now, now: now))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(
                pace, for: window(21, reset: reset.addingTimeInterval(86400)), capturedAt: now, now: now))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(
                pace, for: window(21, reset: reset), capturedAt: now, now: now.addingTimeInterval(1201)))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(
                pace, for: window(21, reset: reset), capturedAt: now.addingTimeInterval(1), now: now))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(pace, for: window(21, reset: reset), capturedAt: nil, now: now))
    }

    func testCurrentCaptureMatchesItsSQLiteTimestampAfterEpochRounding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("history.sqlite")
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000.0000001)
        let reset = now.addingTimeInterval(86400)
        var latest: QuotaWindow!
        for index in 0...2 {
            let capturedAt = now.addingTimeInterval(Double(index - 2) * 900)
            let window = QuotaWindow(
                id: "weekly", usedPercentage: Double(10 + index), resetsAt: reset,
                durationMinutes: 10080, displayName: nil)
            latest = window
            let snapshot = ProviderUsageSnapshot(
                provider: .codex, windows: [window], dailyUsage: [],
                summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: capturedAt)
            try UsageHistoryStore.record(snapshot, at: database, now: capturedAt)
        }
        let persisted = try XCTUnwrap(
            UsageHistoryStore.recentPaces(
                for: [HistoryPaceKey(provider: .codex, windowID: "weekly")],
                matchingLatestQuota: true, at: database
            ).first?.pace)
        XCTAssertNotEqual(persisted.sampledAt, now)
        XCTAssertNotNil(HistoryDashboardModel.usablePace(persisted, for: latest, capturedAt: now, now: now))
        XCTAssertNil(
            HistoryDashboardModel.usablePace(persisted, for: latest, capturedAt: now.addingTimeInterval(1), now: now))
    }

    func testPacePreservesLastActiveValueDuringIdleAndResumesWithNewUsage() {
        let now = Date()
        func reading(_ rate: Double, at date: Date) -> QuotaPace {
            QuotaPace(
                pointsPerHour: rate, observedMinutes: 45, sampledAt: date,
                resetsAt: now.addingTimeInterval(86400), lastUsedPercentage: 20)
        }
        let previous = reading(5, at: now.addingTimeInterval(-86400))
        let waiting = QuotaPaceDisplay(current: nil, previous: previous)
        XCTAssertTrue(waiting.isHistorical)
        XCTAssertEqual(waiting.value?.sampledAt, previous.sampledAt)
        let idle = QuotaPaceDisplay(current: reading(0, at: now), previous: previous)
        XCTAssertTrue(idle.isHistorical)
        XCTAssertEqual(idle.value?.pointsPerHour, 5)
        let resumed = QuotaPaceDisplay(current: reading(3, at: now), previous: previous)
        XCTAssertFalse(resumed.isHistorical)
        XCTAssertEqual(resumed.value?.pointsPerHour, 3)
        XCTAssertEqual(resumed.previous?.sampledAt, previous.sampledAt)
        XCTAssertEqual(QuotaPaceDisplay(current: reading(0, at: now), previous: nil).value?.pointsPerHour, 0)
        XCTAssertNil(QuotaPaceDisplay(current: nil, previous: nil).value)
    }

    func testModeCacheInvalidatesWhenHistoryRevisionChanges() async {
        let day = HistoryDashboardModel.dayKey(Date())
        func snapshots(_ tokens: Int) -> [ProviderUsageSnapshot] {
            [
                ProviderUsageSnapshot(
                    provider: .codex, windows: [],
                    dailyUsage: [DailyTokenUsage(day: day, tokens: tokens)],
                    summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
            ]
        }
        let model = HistoryDashboardModel()
        await model.load(mode: .recent, revision: 1, previewSnapshots: snapshots(10))
        XCTAssertEqual(model.loadedMode, .recent)
        await model.load(mode: .calendar, revision: 1, previewSnapshots: snapshots(10))
        XCTAssertEqual(model.loadedMode, .calendar)
        XCTAssertGreaterThanOrEqual(model.days.count, 365)
        await model.load(mode: .recent, revision: 1, previewSnapshots: snapshots(20))
        XCTAssertEqual(model.days.last?.tokens(for: .codex), 10)
        await model.load(mode: .recent, revision: 2, previewSnapshots: snapshots(20))
        XCTAssertEqual(model.days.last?.tokens(for: .codex), 20)
    }

    func testPinnedDayCardSurvivesHoverAndUnpinsOnTheSameCell() {
        let model = HistoryDashboardModel()
        let bounds = CGRect(x: -20, y: -300, width: 560, height: 700)
        model.showDayCard("2026-09-16", anchor: anchor(x: 10, bounds: bounds))
        XCTAssertEqual(model.daySelection?.dayKey, "2026-09-16")
        XCTAssertEqual(model.daySelection?.isPinned, false)
        model.pinDayCard("2026-09-17", anchor: anchor(x: 20, bounds: bounds))
        XCTAssertEqual(model.daySelection?.isPinned, true)
        XCTAssertEqual(model.daySelection?.anchor?.bounds, bounds)
        model.showDayCard("2026-09-15", anchor: nil)
        model.hideDayCard()
        XCTAssertEqual(model.daySelection?.dayKey, "2026-09-17")
        model.pinDayCard("2026-09-17", anchor: anchor(x: 20, bounds: bounds))
        XCTAssertNil(model.daySelection)
        model.dismissDayCard()
        XCTAssertNil(model.daySelection)
    }

    func testStreakCacheMatchesDirectComputationForEveryScope() async {
        let model = HistoryDashboardModel()
        let keys = (0..<5).map { HistoryDashboardModel.dayKey(Date().addingTimeInterval(-86_400 * Double($0))) }
        await model.load(
            mode: .recent, revision: 1,
            previewSnapshots: [
                ProviderUsageSnapshot(
                    provider: .codex, windows: [],
                    dailyUsage: [DailyTokenUsage(day: keys[1], tokens: 10), DailyTokenUsage(day: keys[2], tokens: 10)],
                    summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date()),
                ProviderUsageSnapshot(
                    provider: .claude, windows: [],
                    dailyUsage: [DailyTokenUsage(day: keys[0], tokens: 5), DailyTokenUsage(day: keys[4], tokens: 5)],
                    summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date()),
            ])
        XCTAssertEqual(model.usageDays.any, model.usageDays.claude.union(model.usageDays.codex))
        for providers in [[UsageProvider.codex], [.claude], [.codex, .claude]] {
            let direct = HistoryAnalytics.streaks(usageDays: model.usageDays.days(for: providers), today: keys[0])
            XCTAssertEqual(model.streak(for: providers).current, direct.current, "\(providers)")
            XCTAssertEqual(model.streak(for: providers).longest, direct.longest, "\(providers)")
        }
        XCTAssertEqual(model.streak(for: [.codex]).current, 2)
        XCTAssertEqual(model.streak(for: [.claude]).current, 1)
        XCTAssertEqual(model.streak(for: [.codex, .claude]).current, 3)
    }

    func testFailedLoadClearsDaysUsageDaysAndStreaks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let model = HistoryDashboardModel(historyURL: blocker.appendingPathComponent("history.sqlite"))
        let today = HistoryDashboardModel.dayKey(Date())
        await model.load(
            mode: .recent, revision: 1,
            previewSnapshots: [
                ProviderUsageSnapshot(
                    provider: .codex, windows: [], dailyUsage: [DailyTokenUsage(day: today, tokens: 10)],
                    summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
            ])
        XCTAssertEqual(model.streak(for: [.codex]).current, 1)
        XCTAssertFalse(model.usageDays.codex.isEmpty)
        await model.load(mode: .recent, revision: 2)
        XCTAssertTrue(model.loadFailed)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.days.isEmpty)
        XCTAssertTrue(model.paces.isEmpty)
        XCTAssertEqual(model.usageDays, HistoryUsageDays())
        XCTAssertEqual(model.streaks, HistoryStreaks())
        XCTAssertEqual(model.streak(for: [.codex]), HistoryStreak())
    }

    private func anchor(x: CGFloat, bounds: CGRect) -> HistoryDayCardAnchor {
        HistoryDayCardAnchor(cell: CGRect(x: x, y: 10, width: 9, height: 9), bounds: bounds)
    }

    func testStreakFollowsTheDisplayedProviders() async {
        let model = HistoryDashboardModel()
        let today = HistoryDashboardModel.dayKey(Date())
        let yesterday = HistoryDashboardModel.dayKey(Date().addingTimeInterval(-86_400))
        await model.load(
            mode: .recent, revision: 1,
            previewSnapshots: [
                ProviderUsageSnapshot(
                    provider: .codex, windows: [],
                    dailyUsage: [DailyTokenUsage(day: today, tokens: 10), DailyTokenUsage(day: yesterday, tokens: 10)],
                    summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date()),
                ProviderUsageSnapshot(
                    provider: .claude, windows: [],
                    dailyUsage: [DailyTokenUsage(day: today, tokens: 5)],
                    summary: nil, availableResetCredits: nil, creditBalance: nil, capturedAt: Date()),
            ])
        XCTAssertEqual(model.streak(for: [.codex]).current, 2)
        XCTAssertEqual(model.streak(for: [.claude]).current, 1)
        XCTAssertEqual(model.streak(for: [.codex, .claude]).current, 2)
        XCTAssertEqual(model.streak(for: [.codex, .claude]).longest, 2)
    }

    func testCalendarDominanceUsesOnlyVisibleRecordedProviders() {
        func day(_ totals: [UsageProvider: Int]) -> HistoryCalendarDay {
            HistoryCalendarDay(id: "2026-09-12", date: Date(), totals: totals, efforts: [])
        }
        XCTAssertEqual(day([.codex: 90, .claude: 10]).dominantProviders(for: [.codex, .claude]), [.codex])
        XCTAssertEqual(day([.codex: 10, .claude: 90]).dominantProviders(for: [.codex, .claude]), [.claude])
        XCTAssertEqual(day([.codex: 10, .claude: 90]).dominantProviders(for: [.codex]), [.codex])
        XCTAssertEqual(day([.codex: 50, .claude: 50]).dominantProviders(for: [.codex, .claude]), [.codex, .claude])
        XCTAssertEqual(day([.claude: 10]).dominantProviders(for: [.codex, .claude]), [.claude])
        XCTAssertTrue(day([.codex: 0, .claude: 0]).dominantProviders(for: [.codex, .claude]).isEmpty)
        XCTAssertTrue(day([:]).dominantProviders(for: [.codex, .claude]).isEmpty)
    }

    func testSecondLoadWithTheSameInputsServesTheCacheWithoutReadingTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = HistoryDashboardModel(historyURL: directory.appending(path: "usage-history.sqlite"))
        await model.load(mode: .recent, revision: 1)
        XCTAssertFalse(model.loadFailed)
        let reads = UsageHistoryStore.entryCount
        XCTAssertGreaterThan(reads, 0)

        await model.load(mode: .recent, revision: 1)
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(UsageHistoryStore.entryCount, reads)

        await model.load(mode: .recent, revision: 2)
        XCTAssertGreaterThan(UsageHistoryStore.entryCount, reads)
    }

    func testClosingThePopoverDropsTheDaySelection() {
        let model = HistoryDashboardModel()
        model.selectedDayKey = "2026-09-15"
        model.pinDayCard("2026-09-17", anchor: anchor(x: 20, bounds: CGRect(x: 0, y: 0, width: 300, height: 200)))
        XCTAssertEqual(model.daySelection?.isPinned, true)

        model.popoverDidClose()
        XCTAssertNil(model.daySelection)
        XCTAssertNil(model.selectedDayKey)
    }

    func testDayKeyMatchesTheFormatterAcrossTimeZones() {
        for seconds in [-5 * 3600, 13 * 3600] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: seconds)!
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let probes = [
                DateComponents(year: 2026, month: 1, day: 1, hour: 0),
                DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59),
                DateComponents(year: 2024, month: 2, day: 29, hour: 12),
                DateComponents(year: 2026, month: 3, day: 7, hour: 3),
                DateComponents(year: 2026, month: 9, day: 18, hour: 17),
                DateComponents(year: 2026, month: 10, day: 31, hour: 23),
                DateComponents(year: 2026, month: 12, day: 31, hour: 22, minute: 30),
                DateComponents(year: 1999, month: 7, day: 4, hour: 6),
                DateComponents(year: 2000, month: 2, day: 28, hour: 1),
                DateComponents(year: 2035, month: 11, day: 9, hour: 15),
            ]
            for components in probes {
                let date = calendar.date(from: components)!
                XCTAssertEqual(
                    HistoryDashboardModel.dayKey(date, calendar: calendar), formatter.string(from: date),
                    "\(components) @ \(seconds)")
            }
        }
    }

    func testPreviewStoresDoNotReadOrCollectLiveHistory() {
        let name = "TokenGauge.history-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(UsageStore(defaults: defaults).historyReadsEnabled)
        let store = UsageStore(defaults: defaults)
        store.historyMode = .calendar
        store.showHourlyPace = false
        let reopened = UsageStore(defaults: defaults)
        XCTAssertEqual(reopened.historyMode, .calendar)
        XCTAssertFalse(reopened.showHourlyPace)
    }
}
