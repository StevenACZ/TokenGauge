import Foundation

public struct EffortUsageRecord: Codable, Equatable, Sendable {
    public let id: String
    public let provider: UsageProvider
    public let recordedAt: Date
    public let day: String
    public let model: String
    public let effort: String
    public let tokens: Int
    public let cachedTokens: Int?

    public init(
        id: String, provider: UsageProvider, recordedAt: Date, day: String, model: String, effort: String, tokens: Int,
        cachedTokens: Int? = nil
    ) {
        self.id = id
        self.provider = provider
        self.recordedAt = recordedAt
        self.day = day
        self.model = model
        self.effort = effort
        self.tokens = tokens
        self.cachedTokens = cachedTokens
    }

    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    private static let identifierCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    private static let efforts: Set<String> = [
        "unknown", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "none", "auto",
    ]
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    var isValid: Bool {
        guard !model.isEmpty, model.utf8.count <= 128,
            model.unicodeScalars.allSatisfy(Self.identifierCharacters.contains),
            Self.efforts.contains(effort), tokens >= 0, (cachedTokens ?? 0) >= 0
        else { return false }
        return Self.isValid(id: id, recordedAt: recordedAt, day: day)
    }

    static func isValid(id: String, recordedAt: Date, day: String) -> Bool {
        guard id.utf8.count == 64, id.unicodeScalars.allSatisfy(hexCharacters.contains),
            recordedAt.timeIntervalSince1970.isFinite,
            (0...253_402_300_799).contains(recordedAt.timeIntervalSince1970),
            isDayFormat(day)
        else { return false }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1970...9999).contains(parts[0]) else { return false }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = utcCalendar.date(from: components) else { return false }
        return utcCalendar.dateComponents([.year, .month, .day], from: date) == components
    }

    private static func isDayFormat(_ day: String) -> Bool {
        let bytes = Array(day.utf8)
        guard bytes.count == 10 else { return false }
        for (index, byte) in bytes.enumerated() {
            let expected: ClosedRange<UInt8> = index == 4 || index == 7 ? 0x2D...0x2D : 0x30...0x39
            guard expected.contains(byte) else { return false }
        }
        return true
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
