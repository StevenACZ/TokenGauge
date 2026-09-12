import Foundation
import TokenGaugeCore

enum ClaudeAccountUsageError: Error, Equatable {
    case authenticationRequired
    case credentialExpired
    case accessDenied
    case unavailable

    static func httpStatus(_ status: Int) -> Self {
        switch status {
        case 401: .authenticationRequired
        case 402, 403: .accessDenied
        default: .unavailable
        }
    }
}

struct ClaudeAccountUsageClient: Sendable {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    func fetch(now: Date = Date()) throws -> ClaudeAccountSnapshot {
        guard let token = ClaudeOAuthTokenReader.read() else {
            throw ClaudeAccountUsageError.authenticationRequired
        }
        guard !token.isExpired else { throw ClaudeAccountUsageError.credentialExpired }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let outcome: Data
        do {
            outcome = try send(request)
        } catch ClaudeAccountUsageError.authenticationRequired {
            ClaudeOAuthTokenReader.invalidate()
            guard let fresh = ClaudeOAuthTokenReader.read(), !fresh.isExpired, fresh.value != token.value else {
                throw ClaudeAccountUsageError.authenticationRequired
            }
            request.setValue("Bearer \(fresh.value)", forHTTPHeaderField: "Authorization")
            outcome = try send(request)
        }
        let windows = try Self.parseWindows(outcome)
        let snapshot = ClaudeAccountSnapshot(capturedAt: now, windows: windows)
        if !windows.isEmpty {
            try? SecureMetricStore.write(snapshot, to: UsagePaths.claudeAccountCache(homeDirectory: homeDirectory))
        }
        return snapshot
    }

    static func parseWindows(_ data: Data) throws -> [QuotaWindow] {
        do {
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let limits = root["limits"] as? [Any], limits.isEmpty
            {
                return []
            }
            return try ClaudeAccountUsageParser.parse(data)
        } catch {
            throw ClaudeAccountUsageError.unavailable
        }
    }

    func cached() -> ClaudeAccountSnapshot? {
        try? SecureMetricStore.read(
            ClaudeAccountSnapshot.self,
            from: UsagePaths.claudeAccountCache(homeDirectory: homeDirectory)
        )
    }

    private func send(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var payload: Data?
        nonisolated(unsafe) var status = 0
        let task = Self.session.dataTask(with: request) { data, response, _ in
            payload = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 12) == .success else {
            task.cancel()
            throw ClaudeAccountUsageError.unavailable
        }
        guard status == 200 else {
            throw ClaudeAccountUsageError.httpStatus(status)
        }
        guard let payload else {
            throw ClaudeAccountUsageError.unavailable
        }
        return payload
    }
}
