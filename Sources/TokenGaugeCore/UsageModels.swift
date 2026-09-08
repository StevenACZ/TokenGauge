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

    public var startsAt: Date? {
        guard let resetsAt, let durationMinutes else { return nil }
        return resetsAt.addingTimeInterval(-Double(durationMinutes) * 60)
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

public struct ModelTokenBucket: Codable, Equatable, Identifiable, Sendable {
    public let day: String
    public let hourStart: Date
    public let model: String
    public let tokens: Int

    public init(day: String, hourStart: Date, model: String, tokens: Int) {
        self.day = day
        self.hourStart = hourStart
        self.model = model
        self.tokens = max(tokens, 0)
    }

    public var id: String { "\(model)-\(hourStart.timeIntervalSince1970)" }
}

public enum ModelTokenAggregator {
    public static func daily(_ buckets: [ModelTokenBucket]) -> [DailyTokenUsage] {
        var totals: [String: Int] = [:]
        for bucket in buckets {
            totals[bucket.day, default: 0] += bucket.tokens
        }
        return totals.map(DailyTokenUsage.init).sorted { $0.day < $1.day }
    }

    public static func byModel(_ buckets: [ModelTokenBucket], since: Date?) -> [(model: String, tokens: Int)] {
        var totals: [String: Int] = [:]
        for bucket in buckets where since == nil || bucket.hourStart >= since! {
            totals[bucket.model, default: 0] += bucket.tokens
        }
        return totals.map { (model: $0.key, tokens: $0.value) }
            .filter { $0.tokens > 0 }
            .sorted { left, right in
                if left.tokens != right.tokens { return left.tokens > right.tokens }
                return left.model < right.model
            }
    }
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
    public let modelBuckets: [ModelTokenBucket]
    public let activityReadSucceeded: Bool

    public init(
        provider: UsageProvider,
        windows: [QuotaWindow],
        dailyUsage: [DailyTokenUsage],
        summary: UsageSummary?,
        availableResetCredits: Int?,
        creditBalance: Double?,
        capturedAt: Date?,
        modelBuckets: [ModelTokenBucket] = [],
        activityReadSucceeded: Bool = true
    ) {
        self.provider = provider
        self.windows = windows
        self.dailyUsage = dailyUsage
        self.summary = summary
        self.availableResetCredits = availableResetCredits
        self.creditBalance = creditBalance
        self.capturedAt = capturedAt
        self.modelBuckets = modelBuckets
        self.activityReadSucceeded = activityReadSucceeded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(UsageProvider.self, forKey: .provider)
        windows = try container.decode([QuotaWindow].self, forKey: .windows)
        dailyUsage = try container.decode([DailyTokenUsage].self, forKey: .dailyUsage)
        summary = try container.decodeIfPresent(UsageSummary.self, forKey: .summary)
        availableResetCredits = try container.decodeIfPresent(Int.self, forKey: .availableResetCredits)
        creditBalance = try container.decodeIfPresent(Double.self, forKey: .creditBalance)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
        modelBuckets = try container.decodeIfPresent([ModelTokenBucket].self, forKey: .modelBuckets) ?? []
        activityReadSucceeded = try container.decodeIfPresent(Bool.self, forKey: .activityReadSucceeded) ?? false
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
