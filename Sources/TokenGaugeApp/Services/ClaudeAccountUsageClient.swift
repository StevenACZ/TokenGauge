import Foundation
import TokenGaugeCore

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
        guard let token = ClaudeOAuthTokenReader.read(), !token.isExpired else {
            throw UsageDataError.missingResponse("oauth")
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let outcome: Data
        do {
            outcome = try send(request)
        } catch UsageDataError.processFailed(let detail) where detail.hasSuffix("401") {
            ClaudeOAuthTokenReader.invalidate()
            guard let fresh = ClaudeOAuthTokenReader.read(), !fresh.isExpired, fresh.value != token.value else {
                throw UsageDataError.processFailed(detail)
            }
            request.setValue("Bearer \(fresh.value)", forHTTPHeaderField: "Authorization")
            outcome = try send(request)
        }
        let windows = try ClaudeAccountUsageParser.parse(outcome)
        let snapshot = ClaudeAccountSnapshot(capturedAt: now, windows: windows)
        try? SecureMetricStore.write(snapshot, to: UsagePaths.claudeAccountCache(homeDirectory: homeDirectory))
        return snapshot
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
            throw UsageDataError.timedOut
        }
        guard status == 200, let payload else {
            throw UsageDataError.processFailed("usage endpoint status \(status)")
        }
        return payload
    }
}
