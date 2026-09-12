import Foundation
import TokenGaugeCore

final class ClaudeSessionRecovery: @unchecked Sendable {
    static let shared = ClaudeSessionRecovery()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var running = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func attempt(homeDirectory: URL, authorization: ClaudeRecoveryAuthorization) -> Bool {
        guard authorization.isAllowed else { return false }
        guard let executable = Self.executable(homeDirectory: homeDirectory) else { return false }
        return attempt(now: Date()) {
            ClaudeRecoveryProcess.run(
                executable: executable, homeDirectory: homeDirectory,
                shouldContinue: { authorization.isAllowed }
            ) {
                ClaudeOAuthTokenReader.invalidate()
                return ClaudeOAuthTokenReader.read().map { !$0.isExpired } ?? false
            }
        }
    }

    func attempt(now: Date, run: () -> Bool) -> Bool {
        lock.lock()
        let nextAttempt = defaults.object(forKey: "claudeRecoveryNextAttempt") as? Date ?? .distantPast
        guard !running, now >= nextAttempt else {
            lock.unlock()
            return false
        }
        running = true
        let failures = min(max(defaults.integer(forKey: "claudeRecoveryFailures"), 0), 2)
        let delay: TimeInterval = [300, 900, 3600][failures]
        defaults.set(now.addingTimeInterval(delay), forKey: "claudeRecoveryNextAttempt")
        lock.unlock()

        let recovered = run()
        lock.lock()
        defaults.set(recovered ? 0 : failures + 1, forKey: "claudeRecoveryFailures")
        running = false
        lock.unlock()
        return recovered
    }

    static func executable(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        [
            homeDirectory.appending(path: ".local/bin/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude"),
        ].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

final class ClaudeRecoveryAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed: Bool

    init(allowed: Bool = false) {
        self.allowed = allowed
    }

    var isAllowed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowed
    }

    func setAllowed(_ value: Bool) {
        lock.lock()
        allowed = value
        lock.unlock()
    }
}
