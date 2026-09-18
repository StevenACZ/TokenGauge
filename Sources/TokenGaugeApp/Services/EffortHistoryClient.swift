import Foundation
import TokenGaugeCore
import os

enum EffortHistoryClient {
    private struct State {
        var collecting = false
        var recordedByCapture = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func markRecorded(by collection: CaptureCollection) {
        state.withLock { $0.recordedByCapture = collection.effortRecords != nil }
    }

    static func collect(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let acquired = state.withLock { state in
            if state.recordedByCapture {
                state.recordedByCapture = false
                return false
            }
            guard !state.collecting else { return false }
            state.collecting = true
            return true
        }
        guard acquired else { return }
        defer { state.withLock { $0.collecting = false } }
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            throw UsageDataError.executableNotFound
        }
        let executable = directory.appending(path: "TokenGaugeCapture")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UsageDataError.executableNotFound
        }
        let result = try ProcessRunner.run(
            executable: executable, arguments: ["--record-effort-history"], input: Data(),
            requiredResponseIDs: [], timeout: 25,
            workingDirectory: UsagePaths.recoveryWorkingDirectory(homeDirectory: homeDirectory))
        guard result.exitCode == 0 else { throw UsageDataError.processFailed("Could not update effort history") }
        let receipt = try JSONDecoder().decode([String: Int].self, from: result.standardOutput)
        guard let records = receipt["records"], records >= 0 else { throw UsageDataError.invalidPayload }
    }
}
