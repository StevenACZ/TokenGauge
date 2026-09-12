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
    case credentialExpired
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
        didSet {
            defaults.set(primaryProvider.rawValue, forKey: "primaryProvider")
            let mode = primaryProvider == .codex ? UsageDisplayMode.codex : .claude
            if displayMode != mode { displayMode = mode }
        }
    }
    @Published var displayMode: UsageDisplayMode {
        didSet {
            defaults.set(displayMode.rawValue, forKey: "displayMode")
            if let provider = displayMode.singleProvider, primaryProvider != provider { primaryProvider = provider }
        }
    }
    @Published var menuBarSize: MenuBarSize {
        didSet { defaults.set(menuBarSize.rawValue, forKey: "menuBarSize") }
    }
    @Published var panelStyle: QuotaPanelStyle {
        didSet { defaults.set(panelStyle.rawValue, forKey: "quotaPanelStyle") }
    }
    @Published var menuBarStyle: QuotaMenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: "quotaMenuBarStyle") }
    }
    @Published var animateChanges: Bool {
        didSet { defaults.set(animateChanges, forKey: "quotaAnimateChanges") }
    }
    @Published var showLunaReserve: Bool {
        didSet { defaults.set(showLunaReserve, forKey: "showLunaReserve") }
    }
    @Published private(set) var hiddenClaudeWindows: Set<ClaudeWindowKind> {
        didSet { defaults.set(hiddenClaudeWindows.map(\.rawValue).sorted(), forKey: "hiddenClaudeWindows") }
    }
    @Published var claudeMenuBarSource: ClaudeMenuBarSource {
        didSet { defaults.set(claudeMenuBarSource.rawValue, forKey: "claudeMenuBarSource") }
    }
    @Published var claudeAutomaticRecovery: Bool {
        didSet {
            defaults.set(claudeAutomaticRecovery, forKey: "claudeAutomaticRecovery")
            recoveryAuthorization.setAllowed(claudeAutomaticRecovery && claudeCancelledAt == nil)
        }
    }
    @Published private(set) var claudeCancelledAt: Date?
    @Published private(set) var codexCancelledAt: Date?

    let recoveryAuthorization: ClaudeRecoveryAuthorization
    private let defaults: UserDefaults

    private let claudeClient: ClaudeUsageClient
    private let codexClient: CodexAppServerClient
    private var timer: Timer?
    private var resetTimer: Timer?

    init(
        claudeClient: ClaudeUsageClient = ClaudeUsageClient(),
        codexClient: CodexAppServerClient = CodexAppServerClient(),
        defaults: UserDefaults = .standard,
        initialSnapshots: [ProviderUsageSnapshot] = []
    ) {
        self.claudeClient = claudeClient
        self.codexClient = codexClient
        self.defaults = defaults
        recoveryAuthorization = ClaudeRecoveryAuthorization(
            allowed: defaults.bool(forKey: "claudeAutomaticRecovery")
                && defaults.object(forKey: "claudeCancelledAt") == nil)
        let savedProvider = UsageProvider(rawValue: defaults.string(forKey: "primaryProvider") ?? "") ?? .codex
        let mode =
            UsageDisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? savedProvider.rawValue)
            ?? (savedProvider == .codex ? .codex : .claude)
        primaryProvider = mode.singleProvider ?? savedProvider
        displayMode = mode
        menuBarSize = MenuBarSize(rawValue: defaults.string(forKey: "menuBarSize") ?? "") ?? .large
        panelStyle = QuotaPanelStyle(rawValue: defaults.string(forKey: "quotaPanelStyle") ?? "") ?? .standard
        menuBarStyle = QuotaMenuBarStyle(rawValue: defaults.string(forKey: "quotaMenuBarStyle") ?? "") ?? .numbers
        animateChanges =
            defaults.object(forKey: "quotaAnimateChanges") == nil || defaults.bool(forKey: "quotaAnimateChanges")
        showLunaReserve = defaults.object(forKey: "showLunaReserve") == nil || defaults.bool(forKey: "showLunaReserve")
        hiddenClaudeWindows = ClaudeWindowKind.decode(defaults.stringArray(forKey: "hiddenClaudeWindows"))
        claudeMenuBarSource =
            ClaudeMenuBarSource(rawValue: defaults.string(forKey: "claudeMenuBarSource") ?? "") ?? .automatic
        claudeAutomaticRecovery = defaults.bool(forKey: "claudeAutomaticRecovery")
        claudeCancelledAt = defaults.object(forKey: "claudeCancelledAt") as? Date
        codexCancelledAt = defaults.object(forKey: "codexCancelledAt") as? Date
        for snapshot in initialSnapshots {
            let state = ProviderViewState(
                snapshot: snapshot, status: isCancelled(provider: snapshot.provider) ? .cancelled : .ready,
                isRefreshing: false)
            if snapshot.provider == .claude { claude = state } else { codex = state }
        }
        if claudeCancelledAt != nil { claude.status = .cancelled }
        if codexCancelledAt != nil { codex.status = .cancelled }
    }

    func start() {
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: true)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        resetTimer?.invalidate()
        recoveryAuthorization.setAllowed(false)
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        isRefreshing = true
        claude.isRefreshing = true
        codex.isRefreshing = true
        let claudeClient = self.claudeClient
        let codexClient = self.codexClient
        let recoveryAuthorization = self.recoveryAuthorization

        Task {
            async let claudeOutcome = Task.detached(priority: .utility) {
                try? claudeClient.fetch(recoveryAuthorization: recoveryAuthorization)
            }.value
            async let codexOutcome = Task.detached(priority: .utility) {
                Self.fetchCodex(client: codexClient)
            }.value

            let codexState = await codexOutcome
            applyCodexState(codexState)
            let claudeResult = await claudeOutcome
            applyRefreshResults(claudeResult: claudeResult, codexState: codexState)
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
        displayMode.providers
    }

    func state(for provider: UsageProvider) -> ProviderViewState {
        provider == .codex ? codex : claude
    }

    func isCancelled(provider: UsageProvider) -> Bool {
        (provider == .claude ? claudeCancelledAt : codexCancelledAt) != nil
    }

    func setClaudeCancelled(_ cancelled: Bool) {
        setCancelled(cancelled, for: .claude)
    }

    func isClaudeWindowVisible(_ kind: ClaudeWindowKind) -> Bool {
        !hiddenClaudeWindows.contains(kind)
    }

    func setClaudeWindow(_ kind: ClaudeWindowKind, visible: Bool) {
        var hidden = hiddenClaudeWindows
        if visible { hidden.remove(kind) } else { hidden.insert(kind) }
        guard hidden.count < ClaudeWindowKind.allCases.count else { return }
        hiddenClaudeWindows = hidden
    }

    func setCancelled(_ cancelled: Bool, for provider: UsageProvider) {
        guard isCancelled(provider: provider) != cancelled else { return }
        persistCancellation(cancelled ? Date() : nil, for: provider)
        if provider == .claude {
            claude.status = cancelled ? .cancelled : .loading
        } else {
            codex.status = cancelled ? .cancelled : .loading
        }
        if !cancelled { refresh(force: true) }
    }

    private func persistCancellation(_ date: Date?, for provider: UsageProvider) {
        if provider == .claude {
            claudeCancelledAt = date
            recoveryAuthorization.setAllowed(claudeAutomaticRecovery && date == nil)
        } else {
            codexCancelledAt = date
        }
        let key = "\(provider.rawValue)CancelledAt"
        if let date { defaults.set(date, forKey: key) } else { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: baselineKey(for: provider))
    }

    private func baselineKey(for provider: UsageProvider) -> String {
        "\(provider.rawValue)CancellationDailyBaseline"
    }

    func applyRefreshResults(claudeResult: ClaudeUsageResult?, codexState: ProviderViewState) {
        if ProviderStateResolver.shouldResumeClaude(result: claudeResult, cancelledAt: claudeCancelledAt) {
            persistCancellation(nil, for: .claude)
        } else {
            resumeIfActivityIncreased(
                provider: .claude, snapshot: claudeResult?.snapshot, live: claudeResult?.access == .live)
        }
        resumeIfActivityIncreased(
            provider: .codex, snapshot: codexState.snapshot, live: codexState.status == .ready)
        let previousClaudeSnapshot = claude.snapshot
        claude = ProviderStateResolver.claudeState(result: claudeResult, cancelled: isCancelled(provider: .claude))
        if claude.snapshot == nil { claude.snapshot = previousClaudeSnapshot }
        applyCodexState(codexState)
    }

    private func applyCodexState(_ state: ProviderViewState) {
        let previous = codex.snapshot
        codex = state
        if codex.snapshot == nil { codex.snapshot = previous }
        if isCancelled(provider: .codex) { codex.status = .cancelled }
    }

    private func resumeIfActivityIncreased(provider: UsageProvider, snapshot: ProviderUsageSnapshot?, live: Bool) {
        guard let cancelledAt = provider == .claude ? claudeCancelledAt : codexCancelledAt,
            live, let snapshot, !snapshot.windows.isEmpty, snapshot.activityReadSucceeded,
            let capturedAt = snapshot.capturedAt, capturedAt > cancelledAt
        else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let cancelledDay = formatter.string(from: cancelledAt)
        var totals: [String: Int] = [:]
        for usage in snapshot.dailyUsage {
            guard usage.day >= cancelledDay, let day = formatter.date(from: usage.day),
                formatter.string(from: day) == usage.day
            else { continue }
            totals[usage.day] = max(totals[usage.day, default: 0], usage.tokens)
        }
        let key = baselineKey(for: provider)
        guard let baseline = defaults.dictionary(forKey: key) as? [String: Int] else {
            defaults.set(totals, forKey: key)
            return
        }
        if totals.contains(where: { $0.value > baseline[$0.key, default: 0] }) {
            persistCancellation(nil, for: provider)
        }
    }

    var menuBarWindow: QuotaWindow? {
        ProviderStateResolver.menuBarWindow(state: state(for: primaryProvider), claudeSource: claudeMenuBarSource)
    }

    private nonisolated static func fetchCodex(client: CodexAppServerClient) -> ProviderViewState {
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
            case .credentialExpired: status = .credentialExpired
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

    static func menuBarWindow(state: ProviderViewState, claudeSource: ClaudeMenuBarSource = .automatic)
        -> QuotaWindow?
    {
        guard state.status == .ready, let snapshot = state.snapshot else { return nil }
        let windows = WindowVisibility.visible(snapshot.windows, provider: snapshot.provider, showLunaReserve: false)
            .filter { ($0.resetsAt ?? .distantFuture) > Date() }
        let weekly = windows.filter { $0.durationMinutes == 10_080 }
        if snapshot.provider == .codex {
            return weekly.first { $0.id.hasPrefix("codex.") }
                ?? windows.first { $0.id.hasPrefix("codex.") }
        }
        if let kind = claudeSource.kind {
            return windows.first { ClaudeWindowKind.of($0) == kind }
        }
        let scoped = weekly.filter { ($0.displayName ?? "").isEmpty == false }
        if let tightest = scoped.min(by: { $0.remainingPercentage < $1.remainingPercentage }) {
            return tightest
        }
        return weekly.first ?? windows.min { $0.remainingPercentage < $1.remainingPercentage }
    }
}
