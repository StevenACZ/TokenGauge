import Foundation

// The extra accounts' last readings, for a local tool that picks the login with room left. Written
// only while the `claudeAccountsExport` default is on, a switch with no Settings control: the same
// percentages and resets the panel shows, never a token or an account field.
public struct ClaudeAccountsExport: Codable, Equatable, Sendable {
    public struct Account: Codable, Equatable, Sendable {
        public let location: String
        public let status: String
        public let capturedAt: Date?
        public let windows: [QuotaWindow]

        public init(location: String, status: String, capturedAt: Date?, windows: [QuotaWindow]) {
            self.location = location
            self.status = status
            self.capturedAt = capturedAt
            self.windows = windows
        }
    }

    public static let version = 1

    public let version: Int
    public let updatedAt: Date
    public let accounts: [Account]

    public init(updatedAt: Date, accounts: [Account]) {
        version = Self.version
        self.updatedAt = updatedAt
        self.accounts = accounts
    }
}
