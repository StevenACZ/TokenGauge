import Darwin
import Foundation
import os

public struct ClaudeOAuthToken: Sendable {
    public let value: String
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum ClaudeOAuthTokenReader {
    public static let service = "Claude Code-credentials"

    private static let cache = OSAllocatedUnfairLock<ClaudeOAuthToken?>(initialState: nil)

    public static func read(account: String = NSUserName()) -> ClaudeOAuthToken? {
        cache.withLock { cached in
            if let cached, !cached.isExpired { return cached }
            let fresh = readFromKeychain(account: account)
            if fresh != nil { cached = fresh }
            return fresh
        }
    }

    public static func invalidate() {
        cache.withLock { $0 = nil }
    }

    static func readFromKeychain(account: String) -> ClaudeOAuthToken? {
        guard let data = securityPayload(account: account) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> ClaudeOAuthToken? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = JSONValue.dictionary(root["claudeAiOauth"]),
            let token = JSONValue.string(oauth["accessToken"]),
            !token.isEmpty
        else { return nil }
        let expiry = JSONValue.double(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeOAuthToken(value: token, expiresAt: expiry)
    }

    private static func securityPayload(account: String) -> Data? {
        boundedPayload(
            executable: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: ["find-generic-password", "-a", account, "-s", service, "-w"],
            timeout: 5
        )
    }

    static func boundedPayload(executable: URL, arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer {
            try? stdout.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
                let deadline = ProcessInfo.processInfo.systemUptime + 0.2
                while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
                    usleep(10_000)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        var outputClosed = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            if outputClosed {
                if !process.isRunning { break }
                usleep(10_000)
                continue
            }
            var descriptor = pollfd(
                fd: stdout.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0
            )
            let ready = poll(&descriptor, 1, 50)
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard ready > 0 else { continue }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 {
                outputClosed = true
            } else {
                guard output.count + count <= 1024 * 1024 else { return nil }
                output.append(contentsOf: bytes.prefix(count))
            }
        }
        guard !process.isRunning, outputClosed, process.terminationStatus == 0 else { return nil }
        return output
    }
}
