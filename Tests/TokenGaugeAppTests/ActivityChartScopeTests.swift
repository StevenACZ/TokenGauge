import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ActivityChartScopeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
    }

    func testHiddenProviderCannotAffectScaleOrSummary() {
        for provider in UsageProvider.allCases {
            let other: UsageProvider = provider == .claude ? .codex : .claude
            let small = snapshot(provider, tokens: 50)
            let huge = snapshot(other, tokens: 9_000_000)
            let data = ActivityChartData(
                claude: provider == .claude ? small : huge,
                codex: provider == .codex ? small : huge,
                providers: [provider], now: today, calendar: calendar)
            XCTAssertEqual(data.providers, [provider])
            XCTAssertEqual(data.maximumTokens, 50)
            let day = data.days.last!
            let summary = data.summary(for: day, locale: Locale(identifier: "en_US"))
            XCTAssertTrue(summary.contains(provider == .claude ? "Claude" : "Codex"))
            XCTAssertFalse(summary.contains(provider == .claude ? "Codex" : "Claude"))
            XCTAssertTrue(summary.contains("50"))
            XCTAssertFalse(summary.contains("9M"))
            XCTAssertEqual(Double(day.tokens(for: provider)) / Double(data.maximumTokens), 1)
        }
    }

    func testUnifiedIncludesBothAndDeduplicatesDaysAndProviders() {
        let data = ActivityChartData(
            claude: snapshot(.claude, tokens: 50, duplicateTokens: 25),
            codex: snapshot(.codex, tokens: 100), providers: [.claude, .codex, .claude],
            now: today, calendar: calendar)
        XCTAssertEqual(data.providers, [.claude, .codex])
        XCTAssertEqual(data.days.count, 7)
        XCTAssertEqual(Set(data.days.map(\.id)).count, 7)
        XCTAssertEqual(data.days.first?.id, "2026-09-01")
        XCTAssertEqual(data.days.last?.id, "2026-09-07")
        XCTAssertEqual(data.maximumTokens, 100)
        let day = data.days.last!
        XCTAssertEqual(Double(day.claudeTokens) / Double(data.maximumTokens), 0.5)
        let summary = data.summary(for: day, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(summary.contains("Claude 50"))
        XCTAssertTrue(summary.contains("Codex 100"))
    }

    func testSelectionSurvivesInputChangeAndFallsBackWhenDayLeavesWindow() {
        let first = ActivityChartData(claude: nil, codex: nil, now: today, calendar: calendar)
        let selectedKey = first.days.first!.id
        let changed = ActivityChartData(
            claude: snapshot(.claude, tokens: 10), codex: nil, providers: [.claude],
            now: today, calendar: calendar)
        XCTAssertEqual(changed.selectedDay(key: selectedKey)?.id, selectedKey)
        let tomorrow = ActivityChartData(
            claude: nil, codex: nil, now: calendar.date(byAdding: .day, value: 1, to: today)!, calendar: calendar)
        XCTAssertEqual(tomorrow.selectedDay(key: selectedKey)?.id, "2026-09-08")
        XCTAssertEqual(tomorrow.selectedDay(key: "2026-09-07")?.id, "2026-09-07")
        XCTAssertEqual(tomorrow.maximumTokens, 1)
        XCTAssertEqual(tomorrow.providers, [.claude, .codex])
    }

    private func snapshot(
        _ provider: UsageProvider, tokens: Int, duplicateTokens: Int? = nil
    ) -> ProviderUsageSnapshot {
        var daily = [DailyTokenUsage(day: "2026-09-07", tokens: tokens)]
        if let duplicateTokens { daily.append(DailyTokenUsage(day: "2026-09-07", tokens: duplicateTokens)) }
        return ProviderUsageSnapshot(
            provider: provider, windows: [], dailyUsage: daily, summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: today)
    }
}
