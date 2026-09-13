import Foundation

public struct HistoryPaceKey: Hashable, Sendable, Identifiable {
    public let provider: UsageProvider
    public let windowID: String
    public var id: String { "\(provider.rawValue):\(windowID)" }

    public init(provider: UsageProvider, windowID: String) {
        self.provider = provider
        self.windowID = windowID
    }
}

public struct HistoryPaceRow: Equatable, Sendable {
    public let key: HistoryPaceKey
    public let displayName: String?
    public let pace: QuotaPace
    public let isActive: Bool

    public init(key: HistoryPaceKey, displayName: String?, pace: QuotaPace, isActive: Bool) {
        self.key = key
        self.displayName = displayName
        self.pace = pace
        self.isActive = isActive
    }
}
