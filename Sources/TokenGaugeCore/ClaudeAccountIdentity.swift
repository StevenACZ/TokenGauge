import CryptoKit
import Foundation
import os

public struct ClaudeAccountIdentity: Equatable, Sendable {
    public let accountUuid: String
    public let emailAddress: String?
    public let displayName: String?
    public let organizationName: String?

    public init(
        accountUuid: String,
        emailAddress: String? = nil,
        displayName: String? = nil,
        organizationName: String? = nil
    ) {
        self.accountUuid = accountUuid
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.organizationName = organizationName
    }

    public var fingerprint: String {
        let hex = Array("0123456789abcdef".utf8)
        return String(
            decoding: SHA256.hash(data: Data(accountUuid.utf8)).flatMap {
                [hex[Int($0 >> 4)], hex[Int($0 & 15)]]
            }, as: UTF8.self)
    }

    public static func isCompatible(stored: String?, current: String?) -> Bool {
        guard let stored, let current else { return true }
        return stored == current
    }

    public var label: String? {
        for candidate in [emailAddress, displayName] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }
}

extension ClaudeAccountIdentity {
    private struct Document: Decodable {
        struct Account: Decodable {
            let accountUuid: String
            let emailAddress: String?
            let displayName: String?
            let organizationName: String?
        }

        let oauthAccount: Account?
    }

    public init?(data: Data) {
        guard let account = (try? JSONDecoder().decode(Document.self, from: data))?.oauthAccount,
            !account.accountUuid.isEmpty
        else { return nil }
        self.init(
            accountUuid: account.accountUuid,
            emailAddress: account.emailAddress,
            displayName: account.displayName,
            organizationName: account.organizationName
        )
    }
}

public enum ClaudeAccountIdentityReader {
    private struct Entry {
        let url: URL
        let modifiedAt: Date?
        let size: Int
        let identity: ClaudeAccountIdentity?
    }

    private static let cache = OSAllocatedUnfairLock<Entry?>(initialState: nil)

    public static func current(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ClaudeAccountIdentity? {
        read(at: UsagePaths.claudeConfig(homeDirectory: homeDirectory))
    }

    public static func read(at url: URL) -> ClaudeAccountIdentity? {
        cache.withLock { entry in
            let previous = entry?.url == url ? entry?.identity : nil
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                return previous
            }
            let modifiedAt = attributes[.modificationDate] as? Date
            let size = attributes[.size] as? Int ?? 0
            if let entry, entry.url == url, entry.modifiedAt == modifiedAt, entry.size == size {
                return entry.identity
            }
            guard let data = try? Data(contentsOf: url) else { return previous }
            let identity = ClaudeAccountIdentity(data: data)
            entry = Entry(url: url, modifiedAt: modifiedAt, size: size, identity: identity)
            return identity
        }
    }

    public static func invalidate() {
        cache.withLock { $0 = nil }
    }
}
