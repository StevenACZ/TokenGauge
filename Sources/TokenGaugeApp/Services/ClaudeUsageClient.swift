import Foundation
import TokenGaugeCore

enum ClaudeAccessState: Equatable, Sendable {
    case live
    case cached
    case authenticationRequired
    case credentialExpired
    case accessDenied
    case unavailable
}

struct ClaudeUsageResult: Sendable {
    let snapshot: ProviderUsageSnapshot
    let access: ClaudeAccessState
    let lastActivityAt: Date?
}

struct ClaudeUsageClient: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetch(
        now: Date = Date(), recoveryAuthorization: ClaudeRecoveryAuthorization = ClaudeRecoveryAuthorization()
    ) throws -> ClaudeUsageResult {
        let buckets = try? fetchModelBuckets()
        let account = ClaudeAccountUsageClient(homeDirectory: homeDirectory)
        let outcome = Self.readAccount(
            fetch: { try account.fetch(now: Date()) },
            recover: {
                ClaudeSessionRecovery.shared.attempt(homeDirectory: homeDirectory, authorization: recoveryAuthorization)
            }
        )
        let capture = try? SecureMetricStore.read(
            ClaudeCapturedSnapshot.self,
            from: UsagePaths.claudeCapture(homeDirectory: homeDirectory)
        )
        return Self.resolve(
            account: outcome, cached: account.cached(), capture: capture, modelBuckets: buckets ?? [], now: now,
            activityReadSucceeded: buckets != nil
        )
    }

    static func readAccount(
        fetch: () throws -> ClaudeAccountSnapshot,
        recover: () -> Bool
    ) -> Result<ClaudeAccountSnapshot, Error> {
        do {
            return .success(try fetch())
        } catch ClaudeAccountUsageError.credentialExpired {
            guard recover() else { return .failure(ClaudeAccountUsageError.credentialExpired) }
            ClaudeOAuthTokenReader.invalidate()
            return Result { try fetch() }
        } catch {
            return .failure(error)
        }
    }

    static func resolve(
        account: Result<ClaudeAccountSnapshot, Error>,
        cached: ClaudeAccountSnapshot?,
        capture: ClaudeCapturedSnapshot?,
        modelBuckets: [ModelTokenBucket],
        now: Date,
        activityReadSucceeded: Bool = true
    ) -> ClaudeUsageResult {
        if case .success(let live) = account, !live.windows.isEmpty {
            return ClaudeUsageResult(
                snapshot: snapshot(
                    windows: live.windows, capturedAt: live.capturedAt, modelBuckets: modelBuckets,
                    activityReadSucceeded: activityReadSucceeded),
                access: .live,
                lastActivityAt: capture?.capturedAt
            )
        }
        let fallback = Self.fallback(cached: cached, capture: capture, modelBuckets: modelBuckets, now: now)
        let access: ClaudeAccessState
        switch account {
        case .success:
            access = .unavailable
        case .failure(let error):
            switch error as? ClaudeAccountUsageError {
            case .authenticationRequired: access = .authenticationRequired
            case .credentialExpired: access = .credentialExpired
            case .accessDenied: access = .accessDenied
            default: access = fallback.windows.isEmpty ? .unavailable : .cached
            }
        }
        return ClaudeUsageResult(
            snapshot: snapshot(
                windows: fallback.windows, capturedAt: fallback.capturedAt, modelBuckets: modelBuckets,
                activityReadSucceeded: activityReadSucceeded),
            access: access,
            lastActivityAt: capture?.capturedAt
        )
    }

    static func fallback(
        cached: ClaudeAccountSnapshot?,
        capture: ClaudeCapturedSnapshot?,
        modelBuckets: [ModelTokenBucket],
        now: Date
    ) -> (windows: [QuotaWindow], capturedAt: Date?) {
        let cachedWindows = (cached?.windows ?? []).filter { ($0.resetsAt ?? .distantFuture) > now }
        if let cached, !cachedWindows.isEmpty, cached.capturedAt >= (capture?.capturedAt ?? .distantPast) {
            return (cachedWindows, cached.capturedAt)
        }
        guard let capture else {
            return cachedWindows.isEmpty ? ([], nil) : (cachedWindows, cached?.capturedAt)
        }
        let normalized = ClaudeUsageParser.normalize(capture, modelBuckets: modelBuckets)
        let current = normalized.windows.filter { ($0.resetsAt ?? .distantFuture) > now }
        guard !current.isEmpty else {
            return cachedWindows.isEmpty ? ([], nil) : (cachedWindows, cached?.capturedAt)
        }
        let known = Set(current.map(\.id))
        let scoped = cachedWindows.filter { $0.displayName != nil && !known.contains($0.id) }
        let oldest =
            scoped.isEmpty ? normalized.capturedAt : min(capture.capturedAt, cached?.capturedAt ?? capture.capturedAt)
        return (current + scoped, oldest)
    }

    private static func snapshot(
        windows: [QuotaWindow],
        capturedAt: Date?,
        modelBuckets: [ModelTokenBucket],
        activityReadSucceeded: Bool
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude,
            windows: windows,
            dailyUsage: ModelTokenAggregator.daily(modelBuckets),
            summary: nil,
            availableResetCredits: nil,
            creditBalance: nil,
            capturedAt: capturedAt,
            modelBuckets: modelBuckets,
            activityReadSucceeded: activityReadSucceeded
        )
    }

    private func fetchModelBuckets() throws -> [ModelTokenBucket] {
        guard let executable = resolveCaptureExecutable() else { throw UsageDataError.executableNotFound }
        return try Self.historyBuckets(executable: executable)
    }

    static func historyBuckets(
        executable: URL,
        arguments: [String] = ["--history"],
        timeout: TimeInterval = 20
    ) throws -> [ModelTokenBucket] {
        let result: ProcessResult
        do {
            result = try ProcessRunner.run(
                executable: executable, arguments: arguments, input: Data(), requiredResponseIDs: [], timeout: timeout
            )
        } catch UsageDataError.timedOut {
            throw UsageDataError.timedOut
        } catch {
            throw UsageDataError.processFailed("History helper could not complete")
        }
        guard result.exitCode == 0 else {
            throw UsageDataError.processFailed("History helper exited with status \(result.exitCode)")
        }
        do {
            return try JSONDecoder().decode([ModelTokenBucket].self, from: result.standardOutput)
        } catch {
            throw UsageDataError.invalidPayload
        }
    }

    private func resolveCaptureExecutable() -> URL? {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidate = executableDirectory?.appending(path: "TokenGaugeCapture")
        guard let candidate, FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate
    }
}
