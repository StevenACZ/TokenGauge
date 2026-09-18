import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

enum Fixture {
    static func window(
        id: String,
        usedPercentage: Double = 10,
        resetsAt: Date? = nil,
        durationMinutes: Int? = nil,
        displayName: String? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            id: id, usedPercentage: usedPercentage, resetsAt: resetsAt, durationMinutes: durationMinutes,
            displayName: displayName)
    }

    static func snapshot(
        _ provider: UsageProvider,
        windows: [QuotaWindow] = [],
        dailyUsage: [DailyTokenUsage] = [],
        availableResetCredits: Int? = nil,
        capturedAt: Date? = Date(),
        modelBuckets: [ModelTokenBucket] = []
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider, windows: windows, dailyUsage: dailyUsage, summary: nil,
            availableResetCredits: availableResetCredits, creditBalance: nil, capturedAt: capturedAt,
            modelBuckets: modelBuckets)
    }

    static func modelBuckets(_ tokens: [(String, Int)], at hourStart: Date = Date().addingTimeInterval(-1_800))
        -> [ModelTokenBucket]
    {
        tokens.map { model, amount in
            ModelTokenBucket(
                day: UsageStore.dayKey(for: hourStart, calendar: .current), hourStart: hourStart, model: model,
                tokens: amount)
        }
    }

    static func pace(_ pointsPerHour: Double, resetsAt: Date?) -> QuotaPace {
        QuotaPace(
            pointsPerHour: pointsPerHour, observedMinutes: 45, sampledAt: Date().addingTimeInterval(-600),
            resetsAt: resetsAt, lastUsedPercentage: 15.6)
    }

    @MainActor
    static func store(defaults: UserDefaults, snapshots: [ProviderUsageSnapshot] = []) -> UsageStore {
        UsageStore(defaults: defaults, initialSnapshots: snapshots, historyReadsEnabled: false)
    }
}

func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "TokenGauge.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

@MainActor
func withEachLanguage(_ body: (AppLanguage) throws -> Void) rethrows {
    try withCurrentLanguage {
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
            try body(language)
        }
    }
}
