import Foundation

public struct EffortUsageRecord: Codable, Equatable, Sendable {
    public let id: String
    public let provider: UsageProvider
    public let recordedAt: Date
    public let day: String
    public let model: String
    public let effort: String
    public let tokens: Int

    public init(
        id: String, provider: UsageProvider, recordedAt: Date, day: String, model: String, effort: String, tokens: Int
    ) {
        self.id = id
        self.provider = provider
        self.recordedAt = recordedAt
        self.day = day
        self.model = model
        self.effort = effort
        self.tokens = tokens
    }

    var isValid: Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let identifier = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let efforts: Set<String> = [
            "unknown", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "none", "auto",
        ]
        guard id.utf8.count == 64, id.unicodeScalars.allSatisfy(hex.contains),
            !model.isEmpty, model.utf8.count <= 128, model.unicodeScalars.allSatisfy(identifier.contains),
            efforts.contains(effort), tokens >= 0,
            recordedAt.timeIntervalSince1970.isFinite,
            (0...253_402_300_799).contains(recordedAt.timeIntervalSince1970),
            day.utf8.count == 10, day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        else { return false }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1970...9999).contains(parts[0]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: date) == components
    }
}

public struct HistoryEffortRow: Equatable, Sendable {
    public let day: String
    public let provider: UsageProvider
    public let model: String
    public let effort: String
    public let tokens: Int

    public init(day: String, provider: UsageProvider, model: String, effort: String, tokens: Int) {
        self.day = day
        self.provider = provider
        self.model = model
        self.effort = effort
        self.tokens = tokens
    }
}
