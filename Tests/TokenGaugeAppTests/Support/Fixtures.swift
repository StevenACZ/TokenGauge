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
        capturedAt: Date? = Date()
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider, windows: windows, dailyUsage: dailyUsage, summary: nil,
            availableResetCredits: availableResetCredits, creditBalance: nil, capturedAt: capturedAt)
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
