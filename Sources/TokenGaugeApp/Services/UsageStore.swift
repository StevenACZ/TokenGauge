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
            preferences.primaryProvider = primaryProvider
            let mode = primaryProvider == .codex ? UsageDisplayMode.codex : .claude
            if displayMode != mode { displayMode = mode }
        }
    }
    @Published var displayMode: UsageDisplayMode {
        didSet {
            preferences.displayMode = displayMode
            if let provider = displayMode.singleProvider, primaryProvider != provider { primaryProvider = provider }
        }
    }
    @Published var menuBarSize: MenuBarSize {
        didSet { preferences.menuBarSize = menuBarSize }
    }
    @Published var panelStyle: QuotaPanelStyle {
        didSet { preferences.panelStyle = panelStyle }
    }
    @Published var menuBarStyle: QuotaMenuBarStyle {
        didSet { preferences.menuBarStyle = menuBarStyle }
    }
    @Published var animateChanges: Bool {
        didSet { preferences.animateChanges = animateChanges }
    }
    @Published var historyMode: HistoryMode {
        didSet { preferences.historyMode = historyMode }
    }
    @Published var showHourlyPace: Bool {
        didSet { preferences.showHourlyPace = showHourlyPace }
    }
    @Published private(set) var historyRevision = 0
    let historyReadsEnabled: Bool
    @Published var showLunaReserve: Bool {
        didSet { preferences.showLunaReserve = showLunaReserve }
    }
    @Published private(set) var hiddenClaudeWindows: Set<ClaudeWindowKind> {
        didSet { preferences.hiddenClaudeWindows = hiddenClaudeWindows }
    }
    @Published var claudeMenuBarSource: ClaudeMenuBarSource {
        didSet { preferences.claudeMenuBarSource = claudeMenuBarSource }
    }
    @Published var claudeAutomaticRecovery: Bool {
        didSet {
            preferences.claudeAutomaticRecovery = claudeAutomaticRecovery
            recoveryAuthorization.setAllowed(claudeAutomaticRecovery && claudeCancelledAt == nil)
        }
    }
    @Published private(set) var claudeAccountLabel: String?
    @Published private(set) var claudeAccountFingerprint: String?
    @Published private(set) var claudeCancelledAt: Date?
    @Published private(set) var codexCancelledAt: Date?

    let recoveryAuthorization: ClaudeRecoveryAuthorization
    private let preferences: AppPreferences
    private let refresher: UsageRefresher
    private lazy var scheduler = RefreshScheduler { [weak self] in self?.refresh(force: true) }

    convenience init(
        claudeClient: ClaudeUsageClient = ClaudeUsageClient(),
        codexClient: CodexAppServerClient = CodexAppServerClient(),
        defaults: UserDefaults = .standard,
        initialSnapshots: [ProviderUsageSnapshot] = [],
        historyReadsEnabled: Bool? = nil
    ) {
        self.init(
            refresher: UsageRefresher(claudeClient: claudeClient, codexClient: codexClient),
            defaults: defaults, initialSnapshots: initialSnapshots, historyReadsEnabled: historyReadsEnabled)
    }

    init(
        refresher: UsageRefresher,
        defaults: UserDefaults = .standard,
        initialSnapshots: [ProviderUsageSnapshot] = [],
        historyReadsEnabled: Bool? = nil
    ) {
        let preferences = AppPreferences(defaults: defaults)
        self.refresher = refresher
        self.preferences = preferences
        self.historyReadsEnabled =
            historyReadsEnabled ?? (defaults === UserDefaults.standard && initialSnapshots.isEmpty)
        let claudeCancelledAt = preferences.cancelledAt(.claude)
        recoveryAuthorization = ClaudeRecoveryAuthorization(
            allowed: preferences.claudeAutomaticRecovery && claudeCancelledAt == nil)
        let mode = preferences.displayMode
        primaryProvider = mode.singleProvider ?? preferences.primaryProvider
        displayMode = mode
        menuBarSize = preferences.menuBarSize
        historyMode = preferences.historyMode
        showHourlyPace = preferences.showHourlyPace
        panelStyle = preferences.panelStyle
        menuBarStyle = preferences.menuBarStyle
        animateChanges = preferences.animateChanges
        showLunaReserve = preferences.showLunaReserve
        hiddenClaudeWindows = preferences.hiddenClaudeWindows
        claudeMenuBarSource = preferences.claudeMenuBarSource
        claudeAutomaticRecovery = preferences.claudeAutomaticRecovery
        self.claudeCancelledAt = claudeCancelledAt
        codexCancelledAt = preferences.cancelledAt(.codex)
        for snapshot in initialSnapshots {
            let state = ProviderViewState(
                snapshot: snapshot, status: isCancelled(provider: snapshot.provider) ? .cancelled : .ready,
                isRefreshing: false)
            if snapshot.provider == .claude { claude = state } else { codex = state }
        }
        if claudeCancelledAt != nil { claude.status = .cancelled }
        if codexCancelledAt != nil { codex.status = .cancelled }
    }

    func setPreviewAccountLabel(_ label: String?) {
        claudeAccountLabel = label
    }

    func start() {
        refresh(force: true)
        scheduler.start()
    }

    func stop() {
        scheduler.stop()
        recoveryAuthorization.setAllowed(false)
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        isRefreshing = true
        if !claude.isRefreshing { claude.isRefreshing = true }
        if !codex.isRefreshing { codex.isRefreshing = true }
        let refresher = self.refresher
        let recoveryAuthorization = self.recoveryAuthorization

        Task {
            var claudeResult: ClaudeUsageResult?
            var codexState = ProviderViewState.loading
            for await outcome in refresher.outcomes(recoveryAuthorization: recoveryAuthorization) {
                switch outcome {
                case .claude(let result): claudeResult = result
                case .codex(let state): codexState = state
                }
                receive(outcome)
            }
            lastRefresh = Date()
            isRefreshing = false
            scheduleResetRefresh()
            guard historyReadsEnabled else { return }
            let archived = (claude: claudeResult, codex: codexState)
            await Task.detached(priority: .background) {
                Self.archive(
                    claudeResult: archived.claude, codexState: archived.codex,
                    accountFingerprint: archived.claude?.accountFingerprint)
                try? EffortHistoryClient.collect(homeDirectory: refresher.homeDirectory)
            }.value
            historyRevision &+= 1
        }
    }

    private func receive(_ outcome: ProviderOutcome) {
        switch outcome {
        case .claude(let result):
            applyClaudeResult(result)
            guard historyReadsEnabled else { return }
            let label = result?.accountLabel
            let fingerprint = result?.accountFingerprint
            if claudeAccountLabel != label { claudeAccountLabel = label }
            if claudeAccountFingerprint != fingerprint { claudeAccountFingerprint = fingerprint }
        case .codex(let state):
            applyCodexState(state)
        }
    }

    private func scheduleResetRefresh() {
        let now = Date()
        let nextReset = [claude.snapshot, codex.snapshot]
            .compactMap { $0 }
            .flatMap(\.windows)
            .compactMap(\.resetsAt)
            .filter { $0 > now }
            .min()
        scheduler.scheduleResetRefresh(at: nextReset, now: now)
    }

    nonisolated static func archive(
        claudeResult: ClaudeUsageResult?, codexState: ProviderViewState,
        at url: URL = UsagePaths.history(), accountFingerprint: String? = nil
    ) {
        if let result = claudeResult {
            try? UsageHistoryStore.record(
                result.snapshot, at: url, recordQuota: result.access == .live,
                accountFingerprint: accountFingerprint)
        }
        if let snapshot = codexState.snapshot {
            try? UsageHistoryStore.record(
                snapshot, at: url, recordQuota: codexState.status == .ready,
                recordTokens: codexState.status == .ready || codexState.status == .waiting)
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
        preferences.setCancelledAt(date, for: provider)
        preferences.setCancellationDailyBaseline(nil, for: provider)
    }

    func applyRefreshResults(claudeResult: ClaudeUsageResult?, codexState: ProviderViewState) {
        applyClaudeResult(claudeResult)
        applyCodexState(codexState)
    }

    private func applyClaudeResult(_ result: ClaudeUsageResult?) {
        if ProviderStateResolver.shouldResumeClaude(result: result, cancelledAt: claudeCancelledAt) {
            persistCancellation(nil, for: .claude)
        } else {
            resumeIfActivityIncreased(provider: .claude, snapshot: result?.snapshot, live: result?.access == .live)
        }
        var next = ProviderStateResolver.claudeState(result: result, cancelled: isCancelled(provider: .claude))
        if next.snapshot == nil { next.snapshot = claude.snapshot }
        claude = next
    }

    private func applyCodexState(_ state: ProviderViewState) {
        resumeIfActivityIncreased(provider: .codex, snapshot: state.snapshot, live: state.status == .ready)
        var next = state
        if next.snapshot == nil { next.snapshot = codex.snapshot }
        if isCancelled(provider: .codex) { next.status = .cancelled }
        codex = next
    }

    private func resumeIfActivityIncreased(provider: UsageProvider, snapshot: ProviderUsageSnapshot?, live: Bool) {
        guard let cancelledAt = provider == .claude ? claudeCancelledAt : codexCancelledAt,
            live, let snapshot, !snapshot.windows.isEmpty, snapshot.activityReadSucceeded,
            let capturedAt = snapshot.capturedAt, capturedAt > cancelledAt
        else { return }
        let calendar = Self.dayCalendar
        let cancelledDay = Self.dayKey(for: cancelledAt, calendar: calendar)
        var totals: [String: Int] = [:]
        for usage in snapshot.dailyUsage {
            guard usage.day >= cancelledDay, let day = Self.date(fromDayKey: usage.day, calendar: calendar),
                Self.dayKey(for: day, calendar: calendar) == usage.day
            else { continue }
            totals[usage.day] = max(totals[usage.day, default: 0], usage.tokens)
        }
        guard let baseline = preferences.cancellationDailyBaseline(provider) else {
            preferences.setCancellationDailyBaseline(totals, for: provider)
            return
        }
        if totals.contains(where: { $0.value > baseline[$0.key, default: 0] }) {
            persistCancellation(nil, for: provider)
        }
    }

    var menuBarWindow: QuotaWindow? {
        ProviderStateResolver.menuBarWindow(state: state(for: primaryProvider), claudeSource: claudeMenuBarSource)
    }

    private nonisolated static var dayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    nonisolated static func dayKey(for date: Date, calendar: Calendar = dayCalendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private nonisolated static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
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
