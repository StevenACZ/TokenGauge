import Darwin
import Foundation
import TokenGaugeCore

struct CodexAppServerClient: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetch() throws -> ProviderUsageSnapshot {
        guard let executable = resolveExecutable() else { throw UsageDataError.executableNotFound }
        let input = """
            {"method":"initialize","id":1,"params":{"clientInfo":{"name":"token_gauge","title":"TokenGauge","version":"0.1.0"}}}
            {"method":"initialized"}
            {"method":"account/read","id":2,"params":{}}
            {"method":"account/rateLimits/read","id":3,"params":{}}
            {"method":"account/usage/read","id":4,"params":{}}

            """
        let result = try ProcessRunner.run(
            executable: executable,
            arguments: ["app-server", "--stdio"],
            input: Data(input.utf8),
            requiredResponseIDs: [3, 4],
            timeout: 8
        )
        guard result.exitCode == 0 else {
            let message = String(decoding: result.standardError.prefix(240), as: UTF8.self)
            throw UsageDataError.processFailed(message)
        }
        let snapshot = try CodexUsageParser.parse(result.standardOutput)
        try? SecureMetricStore.write(snapshot, to: UsagePaths.codexCache(homeDirectory: homeDirectory))
        return snapshot
    }

    func cached() -> ProviderUsageSnapshot? {
        try? SecureMetricStore.read(
            ProviderUsageSnapshot.self,
            from: UsagePaths.codexCache(homeDirectory: homeDirectory)
        )
    }

    private func resolveExecutable() -> URL? {
        let candidates = [
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
            homeDirectory.appending(path: ".local/bin/codex"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private struct ProcessResult: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32
}

private enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        input: Data,
        requiredResponseIDs: Set<Int>,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(input)
        let deadline = Date().addingTimeInterval(timeout)
        var output = Data()
        var responseIDs: Set<Int> = []
        let outputHandle = outputPipe.fileHandleForReading

        while Date() < deadline, process.isRunning, !requiredResponseIDs.isSubset(of: responseIDs) {
            var descriptor = pollfd(fd: outputHandle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            guard ready >= 0 else {
                if errno == EINTR { continue }
                break
            }
            guard ready > 0, let chunk = readAvailableData(from: outputHandle.fileDescriptor), !chunk.isEmpty else {
                continue
            }
            output.append(chunk)
            responseIDs.formUnion(responseIdentifiers(in: output))
        }

        guard requiredResponseIDs.isSubset(of: responseIDs) else {
            try? inputPipe.fileHandleForWriting.close()
            stop(process)
            throw UsageDataError.timedOut
        }

        try inputPipe.fileHandleForWriting.close()
        while process.isRunning, Date() < deadline {
            usleep(10_000)
        }
        if process.isRunning { stop(process) }
        output.append(outputHandle.readDataToEndOfFile())
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            standardOutput: output,
            standardError: error,
            exitCode: process.terminationStatus
        )
    }

    private static func responseIdentifiers(in data: Data) -> Set<Int> {
        Set(
            data.split(separator: 0x0A).compactMap { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                    let id = object["id"] as? NSNumber
                else { return nil }
                return id.intValue
            })
    }

    private static func readAvailableData(from descriptor: Int32) -> Data? {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        guard count > 0 else { return nil }
        return Data(bytes.prefix(count))
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < deadline {
            usleep(10_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}
