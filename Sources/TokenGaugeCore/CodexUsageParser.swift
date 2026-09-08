import Foundation

public enum CodexUsageParser {
    public static func parse(_ data: Data, capturedAt: Date = Date()) throws -> ProviderUsageSnapshot {
        var responses: [Int: [String: Any]] = [:]
        for rawLine in data.split(separator: 0x0A) where !rawLine.isEmpty {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(rawLine)),
                let dictionary = object as? [String: Any],
                let id = JSONValue.int(dictionary["id"])
            else { continue }
            responses[id] = dictionary
        }

        if let accountResult = responses[2].flatMap({ JSONValue.dictionary($0["result"]) }),
            accountResult["account"] is NSNull, accountResult["requiresOpenaiAuth"] as? Bool == true
        {
            throw UsageDataError.authenticationRequired
        }

        guard let rateResponse = responses[3], let rateResult = JSONValue.dictionary(rateResponse["result"]) else {
            throw UsageDataError.missingResponse("account/rateLimits/read")
        }
        let usageResult = responses[4].flatMap { JSONValue.dictionary($0["result"]) } ?? [:]

        let windows = parseWindows(rateResult)
        let dailyUsage = parseDailyUsage(usageResult)
        let summary = parseSummary(usageResult)
        let resetCredits = JSONValue.int(
            JSONValue.dictionary(rateResult["rateLimitResetCredits"])?["availableCount"]
        )
        let creditBalance = parseCreditBalance(rateResult)

        return ProviderUsageSnapshot(
            provider: .codex,
            windows: windows,
            dailyUsage: dailyUsage ?? [],
            summary: summary,
            availableResetCredits: resetCredits,
            creditBalance: creditBalance,
            capturedAt: capturedAt,
            activityReadSucceeded: dailyUsage != nil
        )
    }

    private static func parseWindows(_ result: [String: Any]) -> [QuotaWindow] {
        var candidates: [QuotaWindow] = []
        if let legacy = JSONValue.dictionary(result["rateLimits"]) {
            candidates.append(contentsOf: windows(from: legacy, bucketID: "codex"))
        }
        if let buckets = JSONValue.dictionary(result["rateLimitsByLimitId"]) {
            for (bucketID, value) in buckets {
                guard let bucket = JSONValue.dictionary(value) else { continue }
                candidates.append(contentsOf: windows(from: bucket, bucketID: bucketID))
            }
        }

        var unique: [String: QuotaWindow] = [:]
        for window in candidates {
            if unique[window.id] == nil || unique[window.id]?.displayName == nil {
                unique[window.id] = window
            }
        }
        return unique.values.sorted { left, right in
            let leftDuration = left.durationMinutes ?? Int.max
            let rightDuration = right.durationMinutes ?? Int.max
            if leftDuration != rightDuration { return leftDuration < rightDuration }
            return left.id < right.id
        }
    }

    private static func windows(from bucket: [String: Any], bucketID: String) -> [QuotaWindow] {
        let displayName = JSONValue.string(bucket["limitName"])
        return ["primary", "secondary"].compactMap { slot in
            guard let value = JSONValue.dictionary(bucket[slot]), let used = JSONValue.double(value["usedPercent"])
            else {
                return nil
            }
            let reset = JSONValue.double(value["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
            let duration = JSONValue.int(value["windowDurationMins"])
            return QuotaWindow(
                id: "\(bucketID).\(slot)",
                usedPercentage: used,
                resetsAt: reset,
                durationMinutes: duration,
                displayName: displayName
            )
        }
    }

    private static func parseDailyUsage(_ result: [String: Any]) -> [DailyTokenUsage]? {
        guard let buckets = JSONValue.array(result["dailyUsageBuckets"]) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        var usage: [DailyTokenUsage] = []
        for value in buckets {
            guard
                let bucket = JSONValue.dictionary(value),
                let day = JSONValue.string(bucket["startDate"]),
                let date = formatter.date(from: day), formatter.string(from: date) == day,
                let tokens = JSONValue.double(bucket["tokens"]), tokens.isFinite,
                tokens >= 0, tokens < Double(Int.max), tokens.rounded(.towardZero) == tokens
            else { return nil }
            if let number = bucket["tokens"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            usage.append(DailyTokenUsage(day: day, tokens: Int(tokens)))
        }
        return usage.sorted { $0.day < $1.day }
    }

    private static func parseSummary(_ result: [String: Any]) -> UsageSummary? {
        guard let summary = JSONValue.dictionary(result["summary"]) else { return nil }
        return UsageSummary(
            lifetimeTokens: JSONValue.int(summary["lifetimeTokens"]),
            peakDailyTokens: JSONValue.int(summary["peakDailyTokens"]),
            longestRunningTurnSeconds: JSONValue.int(summary["longestRunningTurnSec"]),
            currentStreakDays: JSONValue.int(summary["currentStreakDays"]),
            longestStreakDays: JSONValue.int(summary["longestStreakDays"])
        )
    }

    private static func parseCreditBalance(_ result: [String: Any]) -> Double? {
        let containers = [
            JSONValue.dictionary(result["credits"]),
            JSONValue.dictionary(JSONValue.dictionary(result["rateLimits"])?["credits"]),
        ]
        for container in containers {
            guard let container else { continue }
            for key in ["balance", "remaining", "creditsRemaining"] {
                if let value = JSONValue.double(container[key]) {
                    return value
                }
            }
        }
        return nil
    }
}
