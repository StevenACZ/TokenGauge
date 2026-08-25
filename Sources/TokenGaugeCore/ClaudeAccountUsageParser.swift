import Foundation

public struct ClaudeAccountSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let windows: [QuotaWindow]

    public init(capturedAt: Date, windows: [QuotaWindow]) {
        self.capturedAt = capturedAt
        self.windows = windows
    }
}

public enum ClaudeAccountUsageParser {
    public static func parse(_ data: Data) throws -> [QuotaWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageDataError.invalidPayload
        }
        let windows = JSONValue.array(root["limits"]).map(limits(from:)) ?? []
        guard !windows.isEmpty else { throw UsageDataError.invalidPayload }
        return windows.sorted { left, right in
            let leftDuration = left.durationMinutes ?? Int.max
            let rightDuration = right.durationMinutes ?? Int.max
            if leftDuration != rightDuration { return leftDuration < rightDuration }
            return left.id < right.id
        }
    }

    private static func limits(from entries: [Any]) -> [QuotaWindow] {
        entries.compactMap { entry in
            guard
                let limit = JSONValue.dictionary(entry),
                let kind = JSONValue.string(limit["kind"]),
                let percent = JSONValue.double(limit["percent"])
            else { return nil }

            let model = JSONValue.string(
                JSONValue.dictionary(JSONValue.dictionary(limit["scope"])?["model"])?["display_name"]
            )
            let resets = JSONValue.string(limit["resets_at"]).flatMap(date(from:))

            switch kind {
            case "session":
                return QuotaWindow(
                    id: "five_hour",
                    usedPercentage: percent,
                    resetsAt: resets,
                    durationMinutes: 300,
                    displayName: nil
                )
            case "weekly_all":
                return QuotaWindow(
                    id: "seven_day",
                    usedPercentage: percent,
                    resetsAt: resets,
                    durationMinutes: 10_080,
                    displayName: nil
                )
            case "weekly_scoped":
                guard let model, !model.isEmpty else { return nil }
                return QuotaWindow(
                    id: "seven_day_\(model.lowercased())",
                    usedPercentage: percent,
                    resetsAt: resets,
                    durationMinutes: 10_080,
                    displayName: model
                )
            default:
                return nil
            }
        }
    }

    private static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
