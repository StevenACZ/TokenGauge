import Foundation

public struct ClaudeAccountSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let windows: [QuotaWindow]
    public let accountFingerprint: String?

    public init(capturedAt: Date, windows: [QuotaWindow], accountFingerprint: String? = nil) {
        self.capturedAt = capturedAt
        self.windows = windows
        self.accountFingerprint = accountFingerprint
    }

    public func belongs(to fingerprint: String?) -> Bool {
        ClaudeAccountIdentity.isCompatible(stored: accountFingerprint, current: fingerprint)
    }
}

public enum ClaudeAccountLimits: Equatable, Sendable {
    case empty
    case windows([QuotaWindow])
}

public enum ClaudeAccountUsageParser {
    public static func parse(_ data: Data) throws -> [QuotaWindow] {
        switch try parseLimits(data) {
        case .empty: throw UsageDataError.invalidPayload
        case .windows(let windows): return windows
        }
    }

    public static func parseLimits(_ data: Data) throws -> ClaudeAccountLimits {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = JSONValue.array(root["limits"])
        else {
            throw UsageDataError.invalidPayload
        }
        guard !entries.isEmpty else { return .empty }
        let windows = limits(from: entries)
        guard !windows.isEmpty else { throw UsageDataError.invalidPayload }
        return .windows(
            windows.sorted { left, right in
                let leftDuration = left.durationMinutes ?? Int.max
                let rightDuration = right.durationMinutes ?? Int.max
                if leftDuration != rightDuration { return leftDuration < rightDuration }
                return left.id < right.id
            })
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

    private static let fractionalInstant = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let instant = Date.ISO8601FormatStyle()

    private static func date(from text: String) -> Date? {
        (try? fractionalInstant.parse(text)) ?? (try? instant.parse(text))
    }
}
