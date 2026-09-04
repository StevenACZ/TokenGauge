import Combine
import Foundation
import TokenGaugeCore

enum ProviderStatus: Sendable, Equatable {
    case loading
    case ready
    case waiting
    case stale
    case unavailable
    case authenticationRequired
    case accessDenied
    case cancelled
}

struct ProviderViewState: Equatable, Sendable {
    var snapshot: ProviderUsageSnapshot?
    var status: ProviderStatus
    var isRefreshing: Bool

    static let loading = ProviderViewState(snapshot: nil, status: .loading, isRefreshing: true)
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var claude: ProviderViewState = .loading
    @Published private(set) var codex: ProviderViewState = .loading
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published var primaryProvider: UsageProvider {
        didSet { defaults.set(primaryProvider.rawValue, forKey: "primaryProvider") }
    }
    @Published private(set) var claudeCancelledAt: Date?

    private let defaults: UserDefaults

    private let claudeClient: ClaudeUsageClient
    private let codexClient: CodexAppServerClient
    private var timer: Timer?
    private var resetTimer: Timer?

    init(
        claudeClient: ClaudeUsageClient = ClaudeUsageClient(),
        codexClient: CodexAppServerClient = CodexAppServerClient(),
        defaults: UserDefaults = .standard
    ) {
        self.claudeClient = claudeClient
        self.codexClient = codexClient
        self.defaults = defaults
        primaryProvider = UsageProvider(rawValue: defaults.string(forKey: "primaryProvider") ?? "") ?? .codex
        claudeCancelledAt = defaults.object(forKey: "claudeCancelledAt") as? Date
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
                try? claudeClient.fetch()
            }.value
            async let codexOutcome = Task.detached(priority: .utility) {
                Self.fetchCodex(client: codexClient)
            }.value

            let outcomes = await (claudeOutcome, codexOutcome)
            if ProviderStateResolver.shouldResumeClaude(result: outcomes.0, cancelledAt: claudeCancelledAt) {
                claudeCancelledAt = nil
                defaults.removeObject(forKey: "claudeCancelledAt")
            }
            claude = ProviderStateResolver.claudeState(result: outcomes.0, cancelled: claudeCancelledAt != nil)
            codex = outcomes.1
            lastRefresh = Date()
            isRefreshing = false
            scheduleResetRefresh()
            let snapshots = [claude.snapshot, codex.snapshot].compactMap { $0 }
            Task.detached(priority: .background) { Self.archive(snapshots) }
        }
    }

    private func scheduleResetRefresh() {
        resetTimer?.invalidate()
        let now = Date()
        let nextReset = [claude.snapshot, codex.snapshot]
            .compactMap { $0 }
            .flatMap(\.windows)
            .compactMap(\.resetsAt)
            .filter { $0 > now }
            .min()
        guard let nextReset else { return }
        let delay = max(nextReset.timeIntervalSince(now) + 5, 1)
        resetTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: true)
            }
        }
    }

    private nonisolated static func archive(_ snapshots: [ProviderUsageSnapshot]) {
        for snapshot in snapshots {
            try? UsageHistoryStore.record(snapshot)
        }
    }

    var orderedProviders: [UsageProvider] {
        [primaryProvider, primaryProvider == .codex ? .claude : .codex]
    }

    func state(for provider: UsageProvider) -> ProviderViewState {
        provider == .codex ? codex : claude
    }

    func setClaudeCancelled(_ cancelled: Bool) {
        claudeCancelledAt = cancelled ? Date() : nil
        if let claudeCancelledAt {
            defaults.set(claudeCancelledAt, forKey: "claudeCancelledAt")
            claude.status = .cancelled
        } else {
            defaults.removeObject(forKey: "claudeCancelledAt")
            claude.status = .loading
            refresh(force: true)
        }
    }

    var menuBarWindow: QuotaWindow? {
        ProviderStateResolver.menuBarWindow(state: state(for: primaryProvider))
    }

    private nonisolated static func fetchCodex(client: CodexAppServerClient) -> ProviderViewState {
        do {
            let snapshot = try client.fetch()
            return ProviderViewState(
                snapshot: snapshot,
                status: ProviderStateResolver.codexStatus(snapshot: snapshot),
                isRefreshing: false
            )
        } catch {
            let cached = client.cached()
            return ProviderViewState(
                snapshot: cached, status: cached == nil ? .unavailable : .stale, isRefreshing: false)
        }
    }
}

enum ProviderStateResolver {
    static func shouldResumeClaude(result: ClaudeUsageResult?, cancelledAt: Date?) -> Bool {
        guard let result, let cancelledAt, result.access == .live,
            !result.snapshot.windows.isEmpty, let activityAt = result.lastActivityAt
        else { return false }
        return activityAt > cancelledAt
    }

    static func claudeState(result: ClaudeUsageResult?, cancelled: Bool) -> ProviderViewState {
        let status: ProviderStatus
        if cancelled {
            status = .cancelled
        } else if let result {
            switch result.access {
            case .live: status = claudeStatus(snapshot: result.snapshot, now: Date())
            case .cached: status = .stale
            case .authenticationRequired: status = .authenticationRequired
            case .accessDenied: status = .accessDenied
            case .unavailable: status = .unavailable
            }
        } else {
            status = .unavailable
        }
        return ProviderViewState(snapshot: result?.snapshot, status: status, isRefreshing: false)
    }

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
        guard state.status == .ready, let snapshot = state.snapshot else { return nil }
        let windows = WindowVisibility.visible(snapshot.windows, provider: snapshot.provider)
            .filter { ($0.resetsAt ?? .distantFuture) > Date() }
        let weekly = windows.filter { $0.durationMinutes == 10_080 }
        if snapshot.provider == .codex {
            return weekly.first { $0.id.hasPrefix("codex.") }
                ?? windows.first { $0.id.hasPrefix("codex.") }
        }
        let scoped = weekly.filter { ($0.displayName ?? "").isEmpty == false }
        if let tightest = scoped.min(by: { $0.remainingPercentage < $1.remainingPercentage }) {
            return tightest
        }
        return weekly.first ?? windows.min { $0.remainingPercentage < $1.remainingPercentage }
    }
}
