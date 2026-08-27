import Combine
import Foundation
import TokenGaugeCore

enum ProviderStatus: Sendable, Equatable {
    case loading
    case ready
    case waiting
    case stale
    case unavailable
}

struct ProviderViewState: Equatable {
    var snapshot: ProviderUsageSnapshot?
    var status: ProviderStatus
    var isRefreshing: Bool

    static let loading = ProviderViewState(snapshot: nil, status: .loading, isRefreshing: true)
}

private enum FetchOutcome: Sendable {
    case ready(ProviderUsageSnapshot)
    case waiting(ProviderUsageSnapshot)
    case stale(ProviderUsageSnapshot)
    case unavailable
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var claude: ProviderViewState = .loading
    @Published private(set) var codex: ProviderViewState = .loading
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false

    private let claudeClient: ClaudeUsageClient
    private let codexClient: CodexAppServerClient
    private var timer: Timer?

    init(
        claudeClient: ClaudeUsageClient = ClaudeUsageClient(),
        codexClient: CodexAppServerClient = CodexAppServerClient()
    ) {
        self.claudeClient = claudeClient
        self.codexClient = codexClient
    }

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: true)
            }
        }
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        isRefreshing = true
        claude.isRefreshing = true
        codex.isRefreshing = true
        let claudeClient = self.claudeClient
        let codexClient = self.codexClient

        Task {
            async let claudeOutcome = Task.detached(priority: .utility) {
                Self.fetchClaude(client: claudeClient)
            }.value
            async let codexOutcome = Task.detached(priority: .utility) {
                Self.fetchCodex(client: codexClient)
            }.value

            let outcomes = await (claudeOutcome, codexOutcome)
            claude = Self.state(from: outcomes.0)
            codex = Self.state(from: outcomes.1)
            lastRefresh = Date()
            isRefreshing = false
            let snapshots = [claude.snapshot, codex.snapshot].compactMap { $0 }
            Task.detached(priority: .background) { Self.archive(snapshots) }
        }
    }

    private nonisolated static func archive(_ snapshots: [ProviderUsageSnapshot]) {
        for snapshot in snapshots {
            try? UsageHistoryStore.record(snapshot)
        }
    }

    var menuBarWindow: QuotaWindow? {
        ProviderStateResolver.menuBarWindow(state: claude)
    }

    private nonisolated static func fetchClaude(client: ClaudeUsageClient) -> FetchOutcome {
        do {
            let snapshot = try client.fetch()
            switch ProviderStateResolver.claudeStatus(snapshot: snapshot, now: Date()) {
            case .ready: return .ready(snapshot)
            case .waiting: return .waiting(snapshot)
            case .stale: return .stale(snapshot)
            case .loading, .unavailable: return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    private nonisolated static func fetchCodex(client: CodexAppServerClient) -> FetchOutcome {
        do {
            let snapshot = try client.fetch()
            return ProviderStateResolver.codexStatus(snapshot: snapshot) == .ready
                ? .ready(snapshot)
                : .waiting(snapshot)
        } catch {
            if let cached = client.cached() {
                return .stale(cached)
            }
            return .unavailable
        }
    }

    private static func state(from outcome: FetchOutcome) -> ProviderViewState {
        switch outcome {
        case .ready(let snapshot):
            return ProviderViewState(snapshot: snapshot, status: .ready, isRefreshing: false)
        case .waiting(let snapshot):
            return ProviderViewState(snapshot: snapshot, status: .waiting, isRefreshing: false)
        case .stale(let snapshot):
            return ProviderViewState(snapshot: snapshot, status: .stale, isRefreshing: false)
        case .unavailable:
            return ProviderViewState(snapshot: nil, status: .unavailable, isRefreshing: false)
        }
    }
}

enum ProviderStateResolver {
    static func claudeStatus(snapshot: ProviderUsageSnapshot, now: Date) -> ProviderStatus {
        guard let capturedAt = snapshot.capturedAt, !snapshot.windows.isEmpty else { return .waiting }
        let hasExpiredWindow = snapshot.windows.contains { window in
            guard let reset = window.resetsAt else { return false }
            return reset <= now
        }
        if hasExpiredWindow || now.timeIntervalSince(capturedAt) > 86_400 {
            return .stale
        }
        return .ready
    }

    static func codexStatus(snapshot: ProviderUsageSnapshot) -> ProviderStatus {
        snapshot.windows.isEmpty ? .waiting : .ready
    }

    static func menuBarWindow(state: ProviderViewState) -> QuotaWindow? {
        guard state.status == .ready || state.status == .stale, let snapshot = state.snapshot else { return nil }
        let windows = WindowVisibility.visible(snapshot.windows, provider: snapshot.provider)
        let weekly = windows.filter { $0.durationMinutes == 10_080 }
        let scoped = weekly.filter { ($0.displayName ?? "").isEmpty == false }
        if let tightest = scoped.min(by: { $0.remainingPercentage < $1.remainingPercentage }) {
            return tightest
        }
        return weekly.first ?? windows.min { $0.remainingPercentage < $1.remainingPercentage }
    }
}
