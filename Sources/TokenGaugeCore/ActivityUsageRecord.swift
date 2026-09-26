import Foundation

public enum HistoryActivityKind: String, Codable, Sendable {
    case skill, turn
}

public struct ActivityUsageRecord: Equatable, Sendable {
    public let id: String
    public let provider: UsageProvider
    public let recordedAt: Date
    public let day: String
    public let kind: HistoryActivityKind
    public let key: String
    public let value: Int

    public init(
        id: String, provider: UsageProvider, recordedAt: Date, day: String, kind: HistoryActivityKind, key: String,
        value: Int
    ) {
        self.id = id
        self.provider = provider
        self.recordedAt = recordedAt
        self.day = day
        self.kind = kind
        self.key = key
        self.value = value
    }

    private static let skillCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._:-")
    private static let skillLeadingCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")

    static func isSkillName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.utf8.count <= 64,
            skillLeadingCharacters.contains(first)
        else { return false }
        return name.unicodeScalars.allSatisfy(skillCharacters.contains)
    }

    var isValid: Bool {
        guard value >= 0 else { return false }
        switch kind {
        case .skill: guard Self.isSkillName(key) else { return false }
        case .turn: guard key.isEmpty else { return false }
        }
        return EffortUsageRecord.isValid(id: id, recordedAt: recordedAt, day: day)
    }
}

public struct HistoryActivityRow: Equatable, Sendable {
    public let day: String
    public let provider: UsageProvider
    public let kind: HistoryActivityKind
    public let key: String
    public let count: Int
    public let total: Int
    public let maximum: Int

    public init(
        day: String, provider: UsageProvider, kind: HistoryActivityKind, key: String, count: Int, total: Int,
        maximum: Int
    ) {
        self.day = day
        self.provider = provider
        self.kind = kind
        self.key = key
        self.count = count
        self.total = total
        self.maximum = maximum
    }
}

public struct HistoryCachedRow: Equatable, Sendable {
    public let day: String
    public let provider: UsageProvider
    public let cachedTokens: Int
    public let tokens: Int

    public init(day: String, provider: UsageProvider, cachedTokens: Int, tokens: Int) {
        self.day = day
        self.provider = provider
        self.cachedTokens = cachedTokens
        self.tokens = tokens
    }
}
