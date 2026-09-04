import Darwin
import Foundation
import TokenGaugeCore

enum ClaudeAccessState: Equatable, Sendable {
    case live
    case cached
    case authenticationRequired
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

    func fetch(now: Date = Date()) throws -> ClaudeUsageResult {
        let buckets = (try? fetchModelBuckets(now: now)) ?? []
        let account = ClaudeAccountUsageClient(homeDirectory: homeDirectory)
        let outcome = Result { try account.fetch(now: now) }
        let capture = try? SecureMetricStore.read(
            ClaudeCapturedSnapshot.self,
            from: UsagePaths.claudeCapture(homeDirectory: homeDirectory)
        )
        return Self.resolve(
            account: outcome, cached: account.cached(), capture: capture, modelBuckets: buckets, now: now
        )
    }

    static func resolve(
        account: Result<ClaudeAccountSnapshot, Error>,
        cached: ClaudeAccountSnapshot?,
        capture: ClaudeCapturedSnapshot?,
        modelBuckets: [ModelTokenBucket],
        now: Date
    ) -> ClaudeUsageResult {
        if case .success(let live) = account, !live.windows.isEmpty {
            return ClaudeUsageResult(
                snapshot: snapshot(windows: live.windows, capturedAt: live.capturedAt, modelBuckets: modelBuckets),
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
            case .accessDenied: access = .accessDenied
            default: access = fallback.windows.isEmpty ? .unavailable : .cached
            }
        }
        return ClaudeUsageResult(
            snapshot: snapshot(windows: fallback.windows, capturedAt: fallback.capturedAt, modelBuckets: modelBuckets),
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
        return (current + scoped, normalized.capturedAt)
    }

    private static func snapshot(
        windows: [QuotaWindow],
        capturedAt: Date?,
        modelBuckets: [ModelTokenBucket]
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .claude,
            windows: windows,
            dailyUsage: ModelTokenAggregator.daily(modelBuckets),
            summary: nil,
            availableResetCredits: nil,
            creditBalance: nil,
            capturedAt: capturedAt,
            modelBuckets: modelBuckets
        )
    }

    private func fetchModelBuckets(now: Date) throws -> [ModelTokenBucket] {
        guard let executable = resolveCaptureExecutable() else {
            return try ClaudeHistoryScanner.scan(
                projectsRoot: UsagePaths.claudeProjects(homeDirectory: homeDirectory),
                now: now
            )
        }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--history"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        let deadline = Date().addingTimeInterval(20)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        guard !process.isRunning else {
            process.terminate()
            usleep(100_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw UsageDataError.timedOut
        }
        guard process.terminationStatus == 0 else {
            let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw UsageDataError.processFailed(String(decoding: error.prefix(240), as: UTF8.self))
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return try JSONDecoder().decode([ModelTokenBucket].self, from: data)
    }

    private func resolveCaptureExecutable() -> URL? {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidate = executableDirectory?.appending(path: "TokenGaugeCapture")
        guard let candidate, FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate
    }
}
