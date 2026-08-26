import Darwin
import Foundation
import TokenGaugeCore

struct ClaudeUsageClient: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetch(now: Date = Date()) throws -> ProviderUsageSnapshot {
        let buckets = (try? fetchModelBuckets(now: now)) ?? []
        let account = ClaudeAccountUsageClient(homeDirectory: homeDirectory)

        if let live = try? account.fetch(now: now) {
            return snapshot(windows: live.windows, capturedAt: live.capturedAt, modelBuckets: buckets)
        }

        let capture = try? SecureMetricStore.read(
            ClaudeCapturedSnapshot.self,
            from: UsagePaths.claudeCapture(homeDirectory: homeDirectory)
        )
        let cached = account.cached()

        if let cached, cached.capturedAt >= (capture?.capturedAt ?? .distantPast) {
            return snapshot(windows: cached.windows, capturedAt: cached.capturedAt, modelBuckets: buckets)
        }
        if let capture {
            let normalized = ClaudeUsageParser.normalize(capture, modelBuckets: buckets)
            let known = Set(normalized.windows.map(\.id))
            let scoped = cached?.windows.filter { $0.displayName != nil && !known.contains($0.id) } ?? []
            return snapshot(
                windows: normalized.windows + scoped, capturedAt: normalized.capturedAt, modelBuckets: buckets)
        }
        return snapshot(windows: [], capturedAt: nil, modelBuckets: buckets)
    }

    private func snapshot(
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
