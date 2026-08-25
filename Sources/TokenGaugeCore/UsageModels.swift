import Foundation

public enum UsageProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let usedPercentage: Double
    public let resetsAt: Date?
    public let durationMinutes: Int?
    public let displayName: String?

    public init(
        id: String,
        usedPercentage: Double,
        resetsAt: Date?,
        durationMinutes: Int?,
        displayName: String?
    ) {
        self.id = id
        self.usedPercentage = min(max(usedPercentage, 0), 100)
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
        self.displayName = displayName
    }

    public var remainingPercentage: Double {
        100 - usedPercentage
    }
}

public struct DailyTokenUsage: Codable, Equatable, Identifiable, Sendable {
    public let day: String
    public let tokens: Int

    public init(day: String, tokens: Int) {
        self.day = day
        self.tokens = max(tokens, 0)
    }

    public var id: String { day }
}

public struct UsageSummary: Codable, Equatable, Sendable {
    public let lifetimeTokens: Int?
    public let peakDailyTokens: Int?
    public let longestRunningTurnSeconds: Int?
    public let currentStreakDays: Int?
    public let longestStreakDays: Int?

    public init(
        lifetimeTokens: Int? = nil,
        peakDailyTokens: Int? = nil,
        longestRunningTurnSeconds: Int? = nil,
        currentStreakDays: Int? = nil,
        longestStreakDays: Int? = nil
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSeconds = longestRunningTurnSeconds
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }
}

public struct ProviderUsageSnapshot: Codable, Equatable, Sendable {
    public let provider: UsageProvider
    public let windows: [QuotaWindow]
    public let dailyUsage: [DailyTokenUsage]
    public let summary: UsageSummary?
    public let availableResetCredits: Int?
    public let creditBalance: Double?
    public let capturedAt: Date?

    public init(
        provider: UsageProvider,
        windows: [QuotaWindow],
        dailyUsage: [DailyTokenUsage],
        summary: UsageSummary?,
        availableResetCredits: Int?,
        creditBalance: Double?,
        capturedAt: Date?
    ) {
        self.provider = provider
        self.windows = windows
        self.dailyUsage = dailyUsage
        self.summary = summary
        self.availableResetCredits = availableResetCredits
        self.creditBalance = creditBalance
        self.capturedAt = capturedAt
    }

    public var longestWindow: QuotaWindow? {
        windows.max { left, right in
            let leftDuration = left.durationMinutes ?? 0
            let rightDuration = right.durationMinutes ?? 0
            if leftDuration != rightDuration { return leftDuration < rightDuration }
            return left.usedPercentage < right.usedPercentage
        }
    }
}

public enum UsageDataError: Error, Equatable, Sendable {
    case invalidPayload
    case missingResponse(String)
    case executableNotFound
    case processFailed(String)
    case timedOut
}
