import Foundation
import TokenGaugeCore

enum ProviderOutcome: Sendable {
    case claudePreview(ClaudeUsageResult)
    case claude(ClaudeUsageResult?)
    case codex(ProviderViewState)
}

struct UsageRefresher: Sendable {
    typealias ClaudeFetch =
        @Sendable (ClaudeRecoveryAuthorization, Bool, @escaping @Sendable (ClaudeUsageResult) -> Void) async ->
        ClaudeUsageResult?

    let homeDirectory: URL
    private let fetchClaude: ClaudeFetch
    private let fetchCodex: @Sendable () -> ProviderViewState

    init(claudeClient: ClaudeUsageClient, codexClient: CodexAppServerClient) {
        self.init(
            homeDirectory: claudeClient.homeDirectory,
            fetchClaude: { authorization, includeQuota, onQuota in
                await claudeClient.fetch(
                    recoveryAuthorization: authorization, includeQuota: includeQuota, onQuota: onQuota)
            },
            fetchCodex: { Self.codexState(client: codexClient) })
    }

    init(
        homeDirectory: URL,
        fetchClaude: @escaping ClaudeFetch,
        fetchCodex: @escaping @Sendable () -> ProviderViewState
    ) {
        self.homeDirectory = homeDirectory
        self.fetchClaude = fetchClaude
        self.fetchCodex = fetchCodex
    }

    func outcomes(
        recoveryAuthorization: ClaudeRecoveryAuthorization, includeClaudeQuota: Bool = true
    ) -> AsyncStream<ProviderOutcome> {
        let fetchClaude = fetchClaude
        let fetchCodex = fetchCodex
        return AsyncStream { continuation in
            Task.detached(priority: .utility) {
                await withTaskGroup(of: ProviderOutcome.self) { group in
                    group.addTask {
                        .claude(
                            await fetchClaude(recoveryAuthorization, includeClaudeQuota) {
                                continuation.yield(.claudePreview($0))
                            })
                    }
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
