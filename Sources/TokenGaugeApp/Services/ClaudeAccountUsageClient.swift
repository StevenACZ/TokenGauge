import Foundation
import TokenGaugeCore
import os

enum ClaudeAccountUsageError: Error, Equatable {
    case authenticationRequired
    case credentialExpired
    case accessDenied
    case rateLimited
    case notRequested
    case unavailable

    static func httpStatus(_ status: Int) -> Self {
        switch status {
        case 401: .authenticationRequired
        case 402, 403: .accessDenied
        case 429: .rateLimited
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
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()
    private static let log = Logger(subsystem: "com.stevenacz.TokenGauge", category: "claude-account")

    func fetch(now: Date = Date(), identity: ClaudeAccountIdentity?) async throws -> ClaudeAccountSnapshot {
        let accountUuid = identity?.accountUuid
        guard let token = try await BlockingWork.run({ ClaudeOAuthTokenReader.read(accountUuid: accountUuid) })
        else {
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
            outcome = try await Self.send(request)
        } catch ClaudeAccountUsageError.authenticationRequired {
            ClaudeOAuthTokenReader.invalidate()
            let refreshed = try await BlockingWork.run({ ClaudeOAuthTokenReader.read(accountUuid: accountUuid) })
            guard let fresh = refreshed, !fresh.isExpired, fresh.value != token.value else {
                throw ClaudeAccountUsageError.authenticationRequired
            }
            request.setValue("Bearer \(fresh.value)", forHTTPHeaderField: "Authorization")
            outcome = try await Self.send(request)
        }
        let windows = try Self.parseWindows(outcome)
        let snapshot = ClaudeAccountSnapshot(
            capturedAt: now, windows: windows, accountFingerprint: identity?.fingerprint)
        if !windows.isEmpty {
            let url = UsagePaths.claudeAccountCache(homeDirectory: homeDirectory)
            do {
                try SecureMetricStore.write(snapshot, to: url)
            } catch {
                Self.log.error("Could not write the Claude account cache at \(url.path, privacy: .public)")
            }
        }
        return snapshot
    }

    static func parseWindows(_ data: Data) throws -> [QuotaWindow] {
        do {
            switch try ClaudeAccountUsageParser.parseLimits(data) {
            case .empty: return []
            case .windows(let windows): return windows
            }
        } catch {
            throw ClaudeAccountUsageError.unavailable
        }
    }

    func cached(identity: ClaudeAccountIdentity?) -> ClaudeAccountSnapshot? {
        let snapshot = try? SecureMetricStore.read(
            ClaudeAccountSnapshot.self,
            from: UsagePaths.claudeAccountCache(homeDirectory: homeDirectory)
        )
        guard let snapshot, snapshot.belongs(to: identity?.fingerprint) else { return nil }
        return snapshot
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let payload: Data
        let response: URLResponse
        do {
            (payload, response) = try await session.data(for: request)
        } catch {
            log.error("Claude usage request failed before a response arrived")
            throw ClaudeAccountUsageError.unavailable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            log.error("Claude usage endpoint returned status \(status, privacy: .public)")
            throw ClaudeAccountUsageError.httpStatus(status)
        }
        return payload
    }
}
