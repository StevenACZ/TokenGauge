import Foundation
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

    // Claude Code recreates the keychain item on every token refresh, which drops any ACL grant
    // this app earned. /usr/bin/security is the item creator, so reading through it never prompts.
    public static func read(account: String = NSUserName()) -> ClaudeOAuthToken? {
        cache.withLock { cached in
            if let cached, !cached.isExpired { return cached }
            let fresh = readFromKeychain(account: account)
            if fresh != nil { cached = fresh }
            return fresh
        }
    }

    public static func invalidate() {
        cache.withLock { $0 = nil }
    }

    static func readFromKeychain(account: String) -> ClaudeOAuthToken? {
        guard let data = securityPayload(account: account) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> ClaudeOAuthToken? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = JSONValue.dictionary(root["claudeAiOauth"]),
            let token = JSONValue.string(oauth["accessToken"]),
            !token.isEmpty
        else { return nil }
        let expiry = JSONValue.double(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeOAuthToken(value: token, expiresAt: expiry)
    }

    private static func securityPayload(account: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-a", account, "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return output
    }
}
