import Darwin
import Foundation
import TokenGaugeCore
import os

struct CodexAppServerClient: Sendable {
    let homeDirectory: URL

    private static let log = Logger(subsystem: "com.stevenacz.TokenGauge", category: "codex")

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetch() throws -> ProviderUsageSnapshot {
        let capturedAt = Date()
        guard let executable = resolveExecutable() else { throw UsageDataError.executableNotFound }
        let input = """
            {"method":"initialize","id":1,"params":{"clientInfo":{"name":"token_gauge","title":"TokenGauge","version":"1.1.0"}}}
            {"method":"initialized"}
            {"method":"account/read","id":2,"params":{}}
            {"method":"account/rateLimits/read","id":3,"params":{}}
            {"method":"account/usage/read","id":4,"params":{}}

            """
        let result = try ProcessRunner.run(
            executable: executable,
            arguments: ["app-server", "--stdio"],
            input: Data(input.utf8),
            requiredResponseIDs: [2, 3, 4],
            timeout: 8,
            workingDirectory: UsagePaths.recoveryWorkingDirectory(homeDirectory: homeDirectory)
        )
        guard result.exitCode == 0 else {
            throw UsageDataError.processFailed("Codex app-server exited with status \(result.exitCode)")
        }
        let snapshot = try CodexUsageParser.parse(result.standardOutput, capturedAt: capturedAt)
        let cache = UsagePaths.codexCache(homeDirectory: homeDirectory)
        do {
            try SecureMetricStore.write(snapshot, to: cache)
        } catch {
            Self.log.error("Could not write the Codex cache at \(cache.path, privacy: .public)")
        }
        return snapshot
    }

    func cached() -> ProviderUsageSnapshot? {
        try? SecureMetricStore.read(
            ProviderUsageSnapshot.self,
            from: UsagePaths.codexCache(homeDirectory: homeDirectory)
        )
    }

    func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configuredPath: String? = UserDefaults.standard.string(forKey: "codexExecutablePath")
    ) -> URL? {
        let candidates = executableCandidates(environment: environment, configuredPath: configuredPath)
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func executableCandidates(environment: [String: String], configuredPath: String? = nil) -> [URL] {
        let known = [
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
            homeDirectory.appending(path: ".local/bin/codex"),
        ]
        let inherited = (environment["PATH"] ?? "").split(separator: ":").compactMap { entry -> URL? in
            guard entry.hasPrefix("/") else { return nil }
            return URL(filePath: String(entry)).appendingPathComponent("codex")
        }
        let configured = configuredPath.flatMap { value in
            value.hasPrefix("/") ? URL(filePath: value) : nil
        }
        return [configured].compactMap { $0 } + known + inherited
    }
}

struct ProcessResult: Sendable {
    let standardOutput: Data
    let exitCode: Int32
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        input: Data,
        requiredResponseIDs: Set<Int>,
        timeout: TimeInterval,
        workingDirectory: URL
    ) throws -> ProcessResult {
        try FileManager.default.createDirectory(
            at: workingDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + inheritedPath
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        defer {
            try? inputPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForReading.close()
            stop(process)
        }
        try inputPipe.fileHandleForWriting.write(contentsOf: input)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        var responseIDs: Set<Int> = []
        var scanned = 0
        var inputClosed = false
        var outputClosed = false
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let outputHandle = outputPipe.fileHandleForReading

        while ProcessInfo.processInfo.systemUptime < deadline {
            if requiredResponseIDs.isSubset(of: responseIDs), !inputClosed {
                try inputPipe.fileHandleForWriting.close()
                inputClosed = true
            }
            if outputClosed {
                if !process.isRunning { break }
                usleep(10_000)
                continue
            }
            var descriptor = pollfd(fd: outputHandle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            guard ready >= 0 else {
                if errno == EINTR { continue }
                throw UsageDataError.processFailed("Could not read Codex app-server output")
            }
            guard ready > 0 else { continue }
            if let chunk = readAvailableData(from: outputHandle.fileDescriptor, into: &buffer) {
                if chunk.isEmpty {
                    outputClosed = true
                    responseIDs.formUnion(responseIdentifiers(in: output, from: &scanned, includingTail: true))
                } else {
                    guard output.count + chunk.count <= 4 * 1024 * 1024 else {
                        throw UsageDataError.processFailed("Codex app-server response exceeded the size limit")
                    }
                    output.append(chunk)
                    responseIDs.formUnion(responseIdentifiers(in: output, from: &scanned))
                }
            }
        }

        guard !process.isRunning else { throw UsageDataError.timedOut }
        guard requiredResponseIDs.isSubset(of: responseIDs) else {
            if process.terminationStatus != 0 {
                throw UsageDataError.processFailed("Codex app-server exited with status \(process.terminationStatus)")
            }
            throw UsageDataError.invalidPayload
        }
        return ProcessResult(
            standardOutput: output,
            exitCode: process.terminationStatus
        )
    }

    static func responseIdentifiers(in data: Data, from offset: inout Int, includingTail: Bool = false) -> Set<Int> {
        let start = data.startIndex + offset
        let end = includingTail ? data.endIndex : data[start...].lastIndex(of: 0x0A).map { $0 + 1 } ?? start
        guard end > start else { return [] }
        let lines = data[start..<end]
        offset = end - data.startIndex
        return Set(
            lines.split(separator: 0x0A).compactMap { line in
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                    let id = object["id"] as? NSNumber
                else { return nil }
                return id.intValue
            })
    }

    private static func readAvailableData(from descriptor: Int32, into buffer: inout [UInt8]) -> Data? {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        guard count >= 0 else { return nil }
        return Data(buffer.prefix(count))
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            usleep(10_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}
