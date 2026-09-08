import Darwin
import Foundation
import TokenGaugeCore

struct CodexAppServerClient: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func fetch() throws -> ProviderUsageSnapshot {
        let capturedAt = Date()
        guard let executable = resolveExecutable() else { throw UsageDataError.executableNotFound }
        let input = """
            {"method":"initialize","id":1,"params":{"clientInfo":{"name":"token_gauge","title":"TokenGauge","version":"1.0.0"}}}
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
            throw UsageDataError.processFailed("Codex app-server exited with status \(result.exitCode)")
        }
        let snapshot = try CodexUsageParser.parse(result.standardOutput, capturedAt: capturedAt)
        try? SecureMetricStore.write(snapshot, to: UsagePaths.codexCache(homeDirectory: homeDirectory))
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
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
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
        var inputClosed = false
        var outputClosed = false
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
            if let chunk = readAvailableData(from: outputHandle.fileDescriptor) {
                if chunk.isEmpty {
                    outputClosed = true
                } else {
                    guard output.count + chunk.count <= 4 * 1024 * 1024 else {
                        throw UsageDataError.processFailed("Codex app-server response exceeded the size limit")
                    }
                    output.append(chunk)
                    responseIDs.formUnion(responseIdentifiers(in: output))
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
        guard count >= 0 else { return nil }
        return Data(bytes.prefix(count))
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
