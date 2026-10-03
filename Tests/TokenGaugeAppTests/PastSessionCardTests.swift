import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class PastSessionCardTests: XCTestCase {
    func testPastSessionsComeFromTheMatchingRowsAndTheCardRendersThemInBothLanguages() throws {
        let now = Date()
        let reset = now.addingTimeInterval(2 * 3600)
        func rows(_ id: String, minutes: Int, resetIn: Double, _ samples: [(Double, Double)]) -> [HistoryQuotaRow] {
            samples.map {
                HistoryQuotaRow(
                    sampledAt: now.addingTimeInterval($0.0 * 3600), provider: .claude, windowID: id,
                    displayName: nil, usedPercentage: $0.1, resetsAt: now.addingTimeInterval(resetIn * 3600),
                    durationMinutes: minutes)
            }
        }
        let records = StatsModel.Records(
            input: StatsSummary.Input(days: [], tokens: [], efforts: []),
            quota: rows("five_hour", minutes: 300, resetIn: -3, [(-7.5, 20), (-7, 55), (-6, 80), (-5, 100)])
                + rows("five_hour", minutes: 300, resetIn: 2, [(-2, 10), (-1, 25)]),
            weeklyQuota: rows("seven_day", minutes: 10_080, resetIn: -24, [(-100, 30), (-30, 70)]))
        let model = StatsModel(preview: records)
        let windows = [
            Fixture.window(id: "five_hour", usedPercentage: 30, resetsAt: reset, durationMinutes: 300),
            Fixture.window(
                id: "seven_day", usedPercentage: 12, resetsAt: now.addingTimeInterval(144 * 3600),
                durationMinutes: 10_080),
        ]
        let forecasts = model.forecasts(for: [(.claude, windows)], accountFingerprint: nil, now: now)
        let session = try XCTUnwrap(forecasts.first { $0.isSession })
        let weekly = try XCTUnwrap(forecasts.first { !$0.isSession })

        let sessions = model.pastSessions(like: session, accountFingerprint: nil)
        XCTAssertEqual(sessions.map(\.ranOut), [true])
        XCTAssertEqual(sessions.first?.callWasRight, true)
        let weeks = model.pastSessions(like: weekly, accountFingerprint: nil)
        XCTAssertEqual(weeks.map(\.forecast.remaining), [30])
        XCTAssertNil(weeks.first?.call)

        let suite = temporaryDefaultsSuite()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let language = LocalizationManager.shared.language
        defer {
            defaults.removePersistentDomain(forName: suite)
            LocalizationManager.shared.language = language
        }
        let store = Fixture.store(
            defaults: defaults,
            snapshots: [Fixture.snapshot(.claude, windows: [windows[0]], capturedAt: now)])
        store.displayMode = .claude
        let width = Theme.Layout.panelWidth - Theme.Layout.panelPadding * 2
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
            let view = StatsView(store: store, model: model, providers: [.claude], scrolls: false, pastIndex: 0)
                .frame(width: width)
            XCTAssertEqual(try render(view, maximumHeight: 2_400).size.width, width)
        }
    }
}
