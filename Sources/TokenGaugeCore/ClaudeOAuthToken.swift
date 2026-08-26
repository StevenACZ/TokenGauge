import Foundation
import Security
import os

public struct ClaudeOAuthToken: Sendable {
    public let value: String
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum ClaudeOAuthTokenReader {
    public static let service = "Claude Code-credentials"

    private static let cache = OSAllocatedUnfairLock<ClaudeOAuthToken?>(initialState: nil)

    // Every keychain read of an item owned by another app triggers the macOS consent dialog,
    // so the token is read once per launch and only re-read after it expires.
    public static func read(account: String = NSUserName()) -> ClaudeOAuthToken? {
        cache.withLock { cached in
            if let cached, !cached.isExpired { return cached }
            let fresh = readFromKeychain(account: account)
            if fresh != nil { cached = fresh }
            return fresh
        }
    }

    static func readFromKeychain(account: String) -> ClaudeOAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = JSONValue.dictionary(root["claudeAiOauth"]),
            let token = JSONValue.string(oauth["accessToken"]),
            !token.isEmpty
        else { return nil }
        let expiry = JSONValue.double(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeOAuthToken(value: token, expiresAt: expiry)
    }
}
