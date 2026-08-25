import Darwin
import Foundation
import TokenGaugeCore

struct ClaudeUsageClient: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetch(now: Date = Date()) throws -> ProviderUsageSnapshot {
        let capture = try? SecureMetricStore.read(
            ClaudeCapturedSnapshot.self,
            from: UsagePaths.claudeCapture(homeDirectory: homeDirectory)
        )
        let daily = (try? fetchDailyUsage(now: now)) ?? []
        guard let capture else {
            return ProviderUsageSnapshot(
                provider: .claude,
                windows: [],
                dailyUsage: daily,
                summary: nil,
                availableResetCredits: nil,
                creditBalance: nil,
                capturedAt: nil
            )
        }
        return ClaudeUsageParser.normalize(capture, dailyUsage: daily)
    }

    private func fetchDailyUsage(now: Date) throws -> [DailyTokenUsage] {
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
        return try JSONDecoder().decode([DailyTokenUsage].self, from: data)
    }

    private func resolveCaptureExecutable() -> URL? {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidate = executableDirectory?.appending(path: "TokenGaugeCapture")
        guard let candidate, FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate
    }
}
