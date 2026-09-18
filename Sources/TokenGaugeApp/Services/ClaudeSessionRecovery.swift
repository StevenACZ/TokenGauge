import Foundation
import TokenGaugeCore
import os

final class ClaudeSessionRecovery: Sendable {
    static let shared = ClaudeSessionRecovery()

    private struct State {
        var running = false
        let preferences: AppPreferences
    }

    private let state: OSAllocatedUnfairLock<State>

    init(defaults: UserDefaults = .standard) {
        state = OSAllocatedUnfairLock(uncheckedState: State(preferences: AppPreferences(defaults: defaults)))
    }

    var isRunning: Bool {
        state.withLock { $0.running }
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
                let accountUuid = ClaudeAccountIdentityReader.current(homeDirectory: homeDirectory)?.accountUuid
                return ClaudeOAuthTokenReader.read(accountUuid: accountUuid).map { !$0.isExpired } ?? false
            }
        }
    }

    func attempt(now: Date, run: () -> Bool) -> Bool {
        let failures: Int? = state.withLock { state in
            let nextAttempt = state.preferences.claudeRecoveryNextAttempt ?? .distantPast
            guard !state.running, now >= nextAttempt else { return nil }
            state.running = true
            let failures = min(max(state.preferences.claudeRecoveryFailures, 0), 2)
            let delay: TimeInterval = [300, 900, 3600][failures]
            state.preferences.claudeRecoveryNextAttempt = now.addingTimeInterval(delay)
            return failures
        }
        guard let failures else { return false }

        let recovered = run()
        state.withLock { state in
            state.preferences.claudeRecoveryFailures = recovered ? 0 : failures + 1
            state.running = false
        }
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

final class ClaudeRecoveryAuthorization: Sendable {
    private let allowed: OSAllocatedUnfairLock<Bool>

    init(allowed: Bool = false) {
        self.allowed = OSAllocatedUnfairLock(initialState: allowed)
    }

    var isAllowed: Bool {
        allowed.withLock { $0 }
    }

    func setAllowed(_ value: Bool) {
        allowed.withLock { $0 = value }
    }
}
