import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class DemoDataTests: XCTestCase {
    func testSeededHistoryFeedsEveryView() async throws {
        for minutes in [0.0, 4, 8, 13] {
            try await assertDemoFeedsEveryView(now: Date().addingTimeInterval(-minutes * 60))
        }
    }

    private func assertDemoFeedsEveryView(now: Date) async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "demo-\(UUID().uuidString)/history.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshots = DemoData.snapshots(now: now)
        try DemoData.seed(snapshots: snapshots, at: url, now: now)

        let records = try StatsModel.read(url: url, now: now)
        XCTAssertFalse(records.input.efforts.isEmpty)
        XCTAssertFalse(records.input.activity.isEmpty)
        let model = StatsModel(preview: records)
        for provider in UsageProvider.allCases {
            let summary = try XCTUnwrap(model.summary(for: [provider], codexSummary: nil))
            XCTAssertGreaterThan(summary.today ?? 0, 0)
            let windows = try XCTUnwrap(snapshots.first { $0.provider == provider }).windows
            let forecasts = model.forecasts(for: [(provider, windows)], accountFingerprint: nil, now: now)
            XCTAssertEqual(forecasts.count, windows.filter { [300, 10_080].contains($0.durationMinutes) }.count)
        }

        let history = HistoryDashboardModel(now: now, historyURL: url)
        let keys = snapshots.flatMap { snapshot in
            snapshot.windows.filter { $0.durationMinutes == 10_080 }.map {
                HistoryPaceKey(provider: snapshot.provider, windowID: $0.id)
            }
        }
        await history.load(mode: .calendar, revision: 0, paceKeys: keys)
        XCTAssertFalse(history.loadFailed)
        XCTAssertEqual(history.paces.count, keys.count)
    }

    func testDemoStoreNeverReadsLiveUsage() throws {
        try withDefaults { defaults in
            let store = UsageStore(
                defaults: defaults, initialSnapshots: DemoData.snapshots(now: Date()), historyReadsEnabled: true,
                liveReadsEnabled: false)
            store.start()
            store.refresh(force: true)
            XCTAssertFalse(store.isRefreshing)
            XCTAssertFalse(store.isFetching)
        }
    }
}
