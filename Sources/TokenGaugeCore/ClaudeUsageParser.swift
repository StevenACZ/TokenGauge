import Foundation

public struct ClaudeCapturedWindow: Codable, Equatable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = min(max(usedPercentage, 0), 100)
        self.resetsAt = resetsAt
    }
}

public struct ClaudeCapturedSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let windows: [String: ClaudeCapturedWindow]

    public init(capturedAt: Date, windows: [String: ClaudeCapturedWindow]) {
        self.capturedAt = capturedAt
        self.windows = windows
    }
}

public enum ClaudeUsageParser {
    public static func capture(from statusLineData: Data, capturedAt: Date = Date()) throws -> ClaudeCapturedSnapshot {
        guard
            let root = try JSONSerialization.jsonObject(with: statusLineData) as? [String: Any],
            let rateLimits = JSONValue.dictionary(root["rate_limits"])
        else { throw UsageDataError.invalidPayload }

        var windows: [String: ClaudeCapturedWindow] = [:]
        for (key, value) in rateLimits {
            guard let window = JSONValue.dictionary(value), let used = JSONValue.double(window["used_percentage"])
            else {
                continue
            }
            let reset = JSONValue.double(window["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            windows[key] = ClaudeCapturedWindow(usedPercentage: used, resetsAt: reset)
        }
        guard !windows.isEmpty else { throw UsageDataError.invalidPayload }
        return ClaudeCapturedSnapshot(capturedAt: capturedAt, windows: windows)
    }

    public static func normalize(
        _ capture: ClaudeCapturedSnapshot,
        modelBuckets: [ModelTokenBucket]
    ) -> ProviderUsageSnapshot {
        let windows = capture.windows.map { key, value in
            QuotaWindow(
                id: key,
                usedPercentage: value.usedPercentage,
                resetsAt: value.resetsAt,
                durationMinutes: duration(for: key),
                displayName: nil
            )
        }.sorted { left, right in
            let leftDuration = left.durationMinutes ?? Int.max
            let rightDuration = right.durationMinutes ?? Int.max
            if leftDuration != rightDuration { return leftDuration < rightDuration }
            return left.id < right.id
        }
        return ProviderUsageSnapshot(
            provider: .claude,
            windows: windows,
            dailyUsage: ModelTokenAggregator.daily(modelBuckets),
            summary: nil,
            availableResetCredits: nil,
            creditBalance: nil,
            capturedAt: capture.capturedAt,
            modelBuckets: modelBuckets
        )
    }

    private static func duration(for key: String) -> Int? {
        if key == "five_hour" { return 300 }
        if key.hasPrefix("seven_day") { return 10_080 }
        return nil
    }
}
