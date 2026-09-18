import Foundation
import TokenGaugeCore

enum ProviderOutcome: Sendable {
    case claude(ClaudeUsageResult?)
    case codex(ProviderViewState)
}

struct UsageRefresher: Sendable {
    let homeDirectory: URL
    private let fetchClaude: @Sendable (ClaudeRecoveryAuthorization) async -> ClaudeUsageResult?
    private let fetchCodex: @Sendable () -> ProviderViewState

    init(claudeClient: ClaudeUsageClient, codexClient: CodexAppServerClient) {
        self.init(
            homeDirectory: claudeClient.homeDirectory,
            fetchClaude: { await claudeClient.fetch(recoveryAuthorization: $0) },
            fetchCodex: { Self.codexState(client: codexClient) })
    }

    init(
        homeDirectory: URL,
        fetchClaude: @escaping @Sendable (ClaudeRecoveryAuthorization) async -> ClaudeUsageResult?,
        fetchCodex: @escaping @Sendable () -> ProviderViewState
    ) {
        self.homeDirectory = homeDirectory
        self.fetchClaude = fetchClaude
        self.fetchCodex = fetchCodex
    }

    func outcomes(recoveryAuthorization: ClaudeRecoveryAuthorization) -> AsyncStream<ProviderOutcome> {
        let fetchClaude = fetchClaude
        let fetchCodex = fetchCodex
        return AsyncStream { continuation in
            Task.detached(priority: .utility) {
                await withTaskGroup(of: ProviderOutcome.self) { group in
                    group.addTask { .claude(await fetchClaude(recoveryAuthorization)) }
                    group.addTask { .codex(fetchCodex()) }
                    for await outcome in group { continuation.yield(outcome) }
                }
                continuation.finish()
            }
        }
    }

    private static func codexState(client: CodexAppServerClient) -> ProviderViewState {
        do {
            let snapshot = try client.fetch()
            return ProviderViewState(
                snapshot: snapshot,
                status: ProviderStateResolver.codexStatus(snapshot: snapshot),
                isRefreshing: false
            )
        } catch UsageDataError.authenticationRequired {
            return ProviderViewState(
                snapshot: client.cached(), status: .authenticationRequired, isRefreshing: false)
        } catch {
            let cached = client.cached()
            return ProviderViewState(
                snapshot: cached, status: cached == nil ? .unavailable : .stale, isRefreshing: false)
        }
    }
}
