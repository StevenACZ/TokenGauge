import Foundation
import TokenGaugeCore
import os

enum EffortHistoryClient {
    private static let collecting = OSAllocatedUnfairLock(initialState: false)

    static func collect() throws {
        let acquired = collecting.withLock { active in
            guard !active else { return false }
            active = true
            return true
        }
        guard acquired else { return }
        defer { collecting.withLock { $0 = false } }
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            throw UsageDataError.executableNotFound
        }
        let executable = directory.appending(path: "TokenGaugeCapture")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UsageDataError.executableNotFound
        }
        let result = try ProcessRunner.run(
            executable: executable, arguments: ["--record-effort-history"], input: Data(),
            requiredResponseIDs: [], timeout: 25)
        guard result.exitCode == 0 else { throw UsageDataError.processFailed("Could not update effort history") }
        let receipt = try JSONDecoder().decode([String: Int].self, from: result.standardOutput)
        guard let records = receipt["records"], records >= 0 else { throw UsageDataError.invalidPayload }
    }
}
