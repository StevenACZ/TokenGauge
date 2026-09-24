import Foundation
import TokenGaugeCore

enum ClaudeAccessState: Equatable, Sendable {
    case live
    case cached
    case authenticationRequired
    case credentialExpired
    case accessDenied
    case rateLimited
    case notRequested
    case unavailable
}

struct ClaudeUsageResult: Sendable {
    let snapshot: ProviderUsageSnapshot
    let access: ClaudeAccessState
    let lastActivityAt: Date?
    let accountFingerprint: String?
    let accountLabel: String?

    init(
        snapshot: ProviderUsageSnapshot, access: ClaudeAccessState, lastActivityAt: Date?,
        accountFingerprint: String? = nil, accountLabel: String? = nil
    ) {
        self.snapshot = snapshot
        self.access = access
        self.lastActivityAt = lastActivityAt
        self.accountFingerprint = accountFingerprint
        self.accountLabel = accountLabel
    }
}

struct ClaudeUsageClient: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetch(
        now: Date = Date(), recoveryAuthorization: ClaudeRecoveryAuthorization = ClaudeRecoveryAuthorization(),
        includeQuota: Bool = true, onQuota: (@Sendable (ClaudeUsageResult) -> Void)? = nil
    ) async -> ClaudeUsageResult {
        let homeDirectory = homeDirectory
        let identity = ClaudeAccountIdentityReader.current(homeDirectory: homeDirectory)
        let account = ClaudeAccountUsageClient(homeDirectory: homeDirectory)
        return await Self.fetch(
            history: { try? await BlockingWork.run { try self.fetchModelBuckets() } },
            account: {
                guard includeQuota else { return .failure(ClaudeAccountUsageError.notRequested) }
                return await Self.readAccount(
                    fetch: { try await account.fetch(now: Date(), identity: identity) },
                    recover: {
                        (try? await BlockingWork.run {
                            ClaudeSessionRecovery.shared.attempt(
                                homeDirectory: homeDirectory, authorization: recoveryAuthorization)
                        }) ?? false
                    }
                )
            },
            cached: { account.cached(identity: identity) },
            capture: {
                Self.capture(
                    at: UsagePaths.claudeCapture(homeDirectory: homeDirectory),
                    accountFingerprint: identity?.fingerprint)
            },
            now: now, accountFingerprint: identity?.fingerprint, accountLabel: identity?.label, onQuota: onQuota
        )
    }

    static func fetch(
        history: @escaping @Sendable () async -> [ModelTokenBucket]?,
        account: @escaping @Sendable () async -> Result<ClaudeAccountSnapshot, Error>,
        cached: @escaping @Sendable () -> ClaudeAccountSnapshot?,
        capture: @escaping @Sendable () -> ClaudeCapturedSnapshot?,
        now: Date,
        accountFingerprint: String? = nil,
        accountLabel: String? = nil,
        onQuota: (@Sendable (ClaudeUsageResult) -> Void)? = nil
    ) async -> ClaudeUsageResult {
        async let buckets = history()
        let resolved = await account()
        if let onQuota, case .success(let live) = resolved, !live.windows.isEmpty {
            onQuota(
                resolve(
                    account: resolved, cached: nil, capture: nil, modelBuckets: [], now: now,
                    activityReadSucceeded: false, accountFingerprint: accountFingerprint, accountLabel: accountLabel))
        }
        let modelBuckets = await buckets
        return resolve(
            account: resolved, cached: cached(), capture: capture(), modelBuckets: modelBuckets ?? [], now: now,
            activityReadSucceeded: modelBuckets != nil, accountFingerprint: accountFingerprint,
            accountLabel: accountLabel
        )
    }

    static func capture(at url: URL, accountFingerprint: String?) -> ClaudeCapturedSnapshot? {
        guard let snapshot = try? SecureMetricStore.read(ClaudeCapturedSnapshot.self, from: url),
            snapshot.belongs(to: accountFingerprint)
        else { return nil }
        return snapshot
    }

    static func readAccount(
        fetch: () async throws -> ClaudeAccountSnapshot,
        recover: () async -> Bool
    ) async -> Result<ClaudeAccountSnapshot, Error> {
        do {
            return .success(try await fetch())
        } catch ClaudeAccountUsageError.credentialExpired {
            guard await recover() else { return .failure(ClaudeAccountUsageError.credentialExpired) }
            ClaudeOAuthTokenReader.invalidate()
            do {
                return .success(try await fetch())
            } catch {
                return .failure(error)
            }
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
        activityReadSucceeded: Bool = true,
        accountFingerprint: String? = nil,
        accountLabel: String? = nil
    ) -> ClaudeUsageResult {
        if case .success(let live) = account, !live.windows.isEmpty {
            return ClaudeUsageResult(
                snapshot: snapshot(
                    windows: live.windows, capturedAt: live.capturedAt, modelBuckets: modelBuckets,
                    activityReadSucceeded: activityReadSucceeded),
                access: .live,
                lastActivityAt: capture?.capturedAt,
                accountFingerprint: accountFingerprint,
                accountLabel: accountLabel
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
            case .rateLimited: access = .rateLimited
            case .notRequested: access = .notRequested
            default: access = fallback.windows.isEmpty ? .unavailable : .cached
            }
        }
        return ClaudeUsageResult(
            snapshot: snapshot(
                windows: fallback.windows, capturedAt: fallback.capturedAt, modelBuckets: modelBuckets,
                activityReadSucceeded: activityReadSucceeded),
            access: access,
            lastActivityAt: capture?.capturedAt,
            accountFingerprint: accountFingerprint,
            accountLabel: accountLabel
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
        return try Self.historyBuckets(
            executable: executable,
            workingDirectory: UsagePaths.recoveryWorkingDirectory(homeDirectory: homeDirectory))
    }

    static func historyBuckets(
        executable: URL,
        arguments: [String] = ["--collect"],
        timeout: TimeInterval = 45,
        workingDirectory: URL
    ) throws -> [ModelTokenBucket] {
        let result: ProcessResult
        do {
            result = try ProcessRunner.run(
                executable: executable, arguments: arguments, input: Data(), requiredResponseIDs: [],
                timeout: timeout, workingDirectory: workingDirectory
            )
        } catch UsageDataError.timedOut {
            throw UsageDataError.timedOut
        } catch {
            throw UsageDataError.processFailed("History helper could not complete")
        }
        guard result.exitCode == 0 else {
            throw UsageDataError.processFailed("History helper exited with status \(result.exitCode)")
        }
        let collection: CaptureCollection
        do {
            collection = try JSONDecoder().decode(CaptureCollection.self, from: result.standardOutput)
        } catch {
            throw UsageDataError.invalidPayload
        }
        EffortHistoryClient.markRecorded(by: collection)
        return collection.buckets
    }

    private func resolveCaptureExecutable() -> URL? {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidate = executableDirectory?.appending(path: "TokenGaugeCapture")
        guard let candidate, FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate
    }
}
