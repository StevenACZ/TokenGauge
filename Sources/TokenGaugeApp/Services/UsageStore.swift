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
    let historyURL: URL
    let liveReadsEnabled: Bool
    @Published var showLunaReserve: Bool {
        didSet { preferences.showLunaReserve = showLunaReserve }
    }
    @Published private(set) var hiddenClaudeWindows: Set<QuotaWindowKind> {
        didSet { preferences.hiddenClaudeWindows = hiddenClaudeWindows }
    }
    @Published private(set) var collapsedStatsCards: Set<StatsCard> {
        didSet { preferences.collapsedStatsCards = collapsedStatsCards }
    }
    @Published var claudeMenuBarWindows: Set<QuotaWindowKind> {
        didSet { preferences.claudeMenuBarWindows = claudeMenuBarWindows }
    }
    @Published var codexMenuBarWindows: Set<QuotaWindowKind> {
        didSet { preferences.codexMenuBarWindows = codexMenuBarWindows }
    }
    @Published var hideAccountLabel: Bool {
        didSet { preferences.hideAccountLabel = hideAccountLabel }
    }
    @Published var claudeAutomaticRecovery: Bool {
        didSet {
            preferences.claudeAutomaticRecovery = claudeAutomaticRecovery
            recoveryAuthorization.setAllowed(claudeAutomaticRecovery && claudeCancelledAt == nil)
            if claudeAutomaticRecovery, claude.status == .credentialExpired { refresh(force: true) }
        }
    }
    @Published private(set) var claudeAccountLabel: String?
    @Published private(set) var claudeAccountFingerprint: String?
    @Published private(set) var claudeCancelledAt: Date?
    @Published private(set) var codexCancelledAt: Date?

    typealias ArchiveWork = @Sendable (ClaudeUsageResult?, ProviderViewState, URL) async -> Void

    static let liveArchiveWork: ArchiveWork = { claudeResult, codexState, homeDirectory in
        try? await BlockingWork.run {
            archive(
                claudeResult: claudeResult, codexState: codexState,
                accountFingerprint: claudeResult?.accountFingerprint)
            try? EffortHistoryClient.collect(homeDirectory: homeDirectory)
        }
    }

    let recoveryAuthorization: ClaudeRecoveryAuthorization
    private let preferences: AppPreferences
    private let refresher: UsageRefresher
    private let archiveWork: ArchiveWork
    private lazy var scheduler = RefreshScheduler { [weak self] forced in self?.refresh(force: forced) }
    private var refreshQueued = false
    private var lastClaudeQuotaAttempt: Date?
    private var claudeRateLimitStreak = 0
    private var claudeIdentityObserved = false
    private var lastClaudeConfigRefresh: Date?
    private var latestCapture: ClaudeCapturedSnapshot?
    private var monitors: [FileChangeMonitor] = []
    private var pendingRefresh: Task<Void, Never>?
    var eventRefreshDelay: Duration = .milliseconds(1_500)

    convenience init(
        claudeClient: ClaudeUsageClient = ClaudeUsageClient(),
        codexClient: CodexAppServerClient = CodexAppServerClient(),
        defaults: UserDefaults = .standard,
        initialSnapshots: [ProviderUsageSnapshot] = [],
        historyReadsEnabled: Bool? = nil,
        historyURL: URL = UsagePaths.history(),
        liveReadsEnabled: Bool = true
    ) {
        self.init(
            refresher: UsageRefresher(claudeClient: claudeClient, codexClient: codexClient),
            defaults: defaults, initialSnapshots: initialSnapshots, historyReadsEnabled: historyReadsEnabled,
            historyURL: historyURL, liveReadsEnabled: liveReadsEnabled)
    }

    init(
        refresher: UsageRefresher,
        defaults: UserDefaults = .standard,
        initialSnapshots: [ProviderUsageSnapshot] = [],
        historyReadsEnabled: Bool? = nil,
        historyURL: URL = UsagePaths.history(),
        liveReadsEnabled: Bool = true,
        archiveWork: @escaping ArchiveWork = UsageStore.liveArchiveWork
    ) {
        let preferences = AppPreferences(defaults: defaults)
        self.refresher = refresher
        self.archiveWork = archiveWork
        self.preferences = preferences
        self.historyReadsEnabled =
            historyReadsEnabled ?? (defaults === UserDefaults.standard && initialSnapshots.isEmpty)
        self.historyURL = historyURL
        self.liveReadsEnabled = liveReadsEnabled
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
        collapsedStatsCards = preferences.collapsedStatsCards
        claudeMenuBarWindows = preferences.claudeMenuBarWindows
        codexMenuBarWindows = preferences.codexMenuBarWindows
        hideAccountLabel = preferences.hideAccountLabel
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

    var isFetching: Bool {
        claude.isRefreshing || codex.isRefreshing
    }

    func start() {
        guard liveReadsEnabled else { return }
        refresh(force: true)
        scheduler.start()
        startMonitoring()
    }

    func stop() {
        scheduler.stop()
        monitors.forEach { $0.stop() }
        monitors = []
        pendingRefresh?.cancel()
        recoveryAuthorization.setAllowed(false)
    }

    func refresh(force: Bool = false) {
        guard liveReadsEnabled else { return }
        guard !isRefreshing else {
            if force { refreshQueued = true }
            return
        }
        let now = Date()
        if !force, let lastRefresh, now.timeIntervalSince(lastRefresh) < 60 { return }
        let includeClaudeQuota = claudeQuotaDue(force: force, now: now)
        if includeClaudeQuota { lastClaudeQuotaAttempt = now }
        isRefreshing = true
        if !claude.isRefreshing { claude.isRefreshing = true }
        if !codex.isRefreshing { codex.isRefreshing = true }
        let refresher = self.refresher
        let recoveryAuthorization = self.recoveryAuthorization

        Task {
            var claudeResult: ClaudeUsageResult?
            var codexState = ProviderViewState.loading
            for await outcome in refresher.outcomes(
                recoveryAuthorization: recoveryAuthorization, includeClaudeQuota: includeClaudeQuota)
            {
                switch outcome {
                case .claude(let result): claudeResult = result
                case .codex(let state): codexState = state
                case .claudePreview: break
                }
                receive(outcome)
            }
            lastRefresh = Date()
            scheduleResetRefresh()
            if historyReadsEnabled {
                await archiveWork(claudeResult, codexState, refresher.homeDirectory)
                historyRevision &+= 1
            }
            isRefreshing = false
            if refreshQueued {
                refreshQueued = false
                refresh(force: true)
            }
        }
    }

    func refreshSoon(after delay: Duration? = nil, force: Bool = true) {
        pendingRefresh?.cancel()
        let delay = delay ?? eventRefreshDelay
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.refresh(force: force)
        }
    }

    func claudeQuotaDue(force: Bool, now: Date = Date()) -> Bool {
        guard let last = lastClaudeQuotaAttempt else { return true }
        let elapsed = now.timeIntervalSince(last)
        if claudeRateLimitStreak > 0 {
            return elapsed >= min(300 * pow(2, Double(claudeRateLimitStreak - 1)), 1_800)
        }
        guard claude.status == .ready else { return true }
        return elapsed >= (force ? 60 : 270)
    }

    private func receive(_ outcome: ProviderOutcome) {
        switch outcome {
        case .claudePreview(let result):
            guard belongsToCurrentAccount(result) else { return }
            applyClaudePreview(result)
            updateAccount(label: result.accountLabel, fingerprint: result.accountFingerprint)
        case .claude(let result):
            if let result, !belongsToCurrentAccount(result) {
                claude.isRefreshing = false
                return
            }
            applyClaudeResult(result)
            updateAccount(label: result?.accountLabel, fingerprint: result?.accountFingerprint)
        case .codex(let state):
            applyCodexState(state)
            return
        }
        applyCaptureOverlay()
    }

    private func belongsToCurrentAccount(_ result: ClaudeUsageResult) -> Bool {
        !claudeIdentityObserved || result.accountFingerprint == claudeAccountFingerprint
    }

    private func updateAccount(label: String?, fingerprint: String?) {
        guard historyReadsEnabled else { return }
        if claudeAccountLabel != label { claudeAccountLabel = label }
        if claudeAccountFingerprint != fingerprint { claudeAccountFingerprint = fingerprint }
    }

    private func startMonitoring() {
        guard historyReadsEnabled, monitors.isEmpty else { return }
        let home = refresher.homeDirectory
        let captureURL = UsagePaths.claudeCapture(homeDirectory: home)
        let readCapture: @Sendable () -> ClaudeCapturedSnapshot? = {
            try? SecureMetricStore.read(ClaudeCapturedSnapshot.self, from: captureURL)
        }
        monitors = [
            FileChangeMonitor(url: UsagePaths.claudeConfig(homeDirectory: home)) { [weak self] in
                let identity = ClaudeAccountIdentityReader.current(homeDirectory: home)
                Task { @MainActor in self?.claudeConfigChanged(identity) }
            },
            FileChangeMonitor(url: Self.codexHome(home).appending(path: "auth.json")) { [weak self] in
                Task { @MainActor in self?.refreshSoon() }
            },
            FileChangeMonitor(url: captureURL, debounce: 0.2) { [weak self] in
                let capture = readCapture()
                Task { @MainActor in self?.captureChanged(capture) }
            },
        ]
        monitors.forEach { $0.start() }
        Task.detached(priority: .utility) { [weak self] in
            let capture = readCapture()
            await self?.captureChanged(capture)
        }
    }

    nonisolated static func codexHome(
        _ home: URL, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(filePath: $0) : nil }
            ?? home.appending(path: ".codex", directoryHint: .isDirectory)
    }

    func claudeConfigChanged(_ identity: ClaudeAccountIdentity?, now: Date = Date()) {
        let fingerprint = identity?.fingerprint
        let known = claudeIdentityObserved || claudeAccountFingerprint != nil
        claudeIdentityObserved = true
        if known, fingerprint != claudeAccountFingerprint {
            claudeAccountFingerprint = fingerprint
            claudeAccountLabel = identity?.label
            claudeRateLimitStreak = 0
            lastClaudeQuotaAttempt = nil
            ClaudeOAuthTokenReader.invalidate()
            if !isCancelled(provider: .claude) {
                claude = ProviderViewState(snapshot: nil, status: .loading, isRefreshing: true)
            }
            refreshSoon()
            return
        }
        if !known {
            claudeAccountFingerprint = fingerprint
            claudeAccountLabel = identity?.label
        }
        guard ![.ready, .cancelled, .loading].contains(claude.status),
            lastClaudeConfigRefresh.map({ now.timeIntervalSince($0) >= 30 }) ?? true
        else { return }
        lastClaudeConfigRefresh = now
        refreshSoon()
    }

    func captureChanged(_ capture: ClaudeCapturedSnapshot?) {
        latestCapture = capture
        applyCaptureOverlay()
    }

    private func applyCaptureOverlay() {
        guard claude.status == .ready, let snapshot = claude.snapshot,
            let overlaid = ProviderStateResolver.overlay(
                snapshot, capture: latestCapture, accountFingerprint: claudeAccountFingerprint)
        else { return }
        claude.snapshot = overlaid
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

    func isClaudeWindowVisible(_ kind: QuotaWindowKind) -> Bool {
        !hiddenClaudeWindows.contains(kind)
    }

    func setClaudeWindow(_ kind: QuotaWindowKind, visible: Bool) {
        var hidden = hiddenClaudeWindows
        if visible { hidden.remove(kind) } else { hidden.insert(kind) }
        guard hidden.count < QuotaWindowKind.allCases.count else { return }
        hiddenClaudeWindows = hidden
    }

    func toggleStatsCard(_ card: StatsCard) {
        if collapsedStatsCards.contains(card) {
            collapsedStatsCards.remove(card)
        } else {
            collapsedStatsCards.insert(card)
        }
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

    private func applyClaudePreview(_ result: ClaudeUsageResult) {
        guard result.access == .live, !isCancelled(provider: .claude) else { return }
        claudeRateLimitStreak = 0
        let snapshot = result.snapshot.carryingActivity(from: claude.snapshot)
        claude = ProviderViewState(
            snapshot: snapshot, status: ProviderStateResolver.claudeStatus(snapshot: snapshot, now: Date()),
            isRefreshing: true)
    }

    private func keepsCurrentQuota(_ result: ClaudeUsageResult) -> Bool {
        switch result.access {
        case .notRequested:
            return true
        case .rateLimited:
            guard claude.status == .ready, let capturedAt = claude.snapshot?.capturedAt else { return false }
            return Date().timeIntervalSince(capturedAt) <= 900
        default:
            return false
        }
    }

    private func applyClaudeResult(_ result: ClaudeUsageResult?) {
        if result?.access == .rateLimited {
            claudeRateLimitStreak += 1
        } else if let access = result?.access, access != .notRequested {
            claudeRateLimitStreak = 0
        }
        if let result, keepsCurrentQuota(result) {
            var next = claude
            if let current = next.snapshot {
                let merged =
                    result.snapshot.activityReadSucceeded
                    ? current.carryingActivity(from: result.snapshot) : current
                next.snapshot = merged
                if next.status == .ready {
                    next.status = ProviderStateResolver.claudeStatus(snapshot: merged, now: Date())
                }
            }
            next.isRefreshing = false
            claude = next
            return
        }
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
        ProviderStateResolver.menuBarWindow(
            state: state(for: primaryProvider), selection: menuBarSelection(for: primaryProvider))
    }

    var menuBarSelections: [UsageProvider: Set<QuotaWindowKind>] {
        [.claude: claudeMenuBarWindows, .codex: codexMenuBarWindows]
    }

    func menuBarSelection(for provider: UsageProvider) -> Set<QuotaWindowKind> {
        provider == .claude ? claudeMenuBarWindows : codexMenuBarWindows
    }

    func setMenuBarSelection(_ selection: Set<QuotaWindowKind>, for provider: UsageProvider) {
        if provider == .claude { claudeMenuBarWindows = selection } else { codexMenuBarWindows = selection }
    }

    func toggleMenuBarWindow(_ kind: QuotaWindowKind, for provider: UsageProvider) {
        var selection = menuBarSelection(for: provider)
        if selection.contains(kind) { selection.remove(kind) } else { selection.insert(kind) }
        setMenuBarSelection(selection, for: provider)
    }

    func isInMenuBar(_ provider: UsageProvider) -> Bool {
        displayMode.providers.contains(provider)
    }

    func setInMenuBar(_ shown: Bool, provider: UsageProvider) {
        var providers = Set(displayMode.providers)
        if shown { providers.insert(provider) } else { providers.remove(provider) }
        guard let only = providers.first else { return }
        displayMode = providers.count > 1 ? .unified : (only == .claude ? .claude : .codex)
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
            case .rateLimited, .notRequested: status = result.snapshot.windows.isEmpty ? .unavailable : .stale
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

    static func menuBarWindow(state: ProviderViewState, selection: Set<QuotaWindowKind> = []) -> QuotaWindow? {
        menuBarWindows(state: state, selection: selection).first
    }

    static func menuBarCandidates(_ snapshot: ProviderUsageSnapshot, now: Date = Date()) -> [QuotaWindow] {
        let live = snapshot.windows.filter { ($0.resetsAt ?? .distantFuture) > now }
        guard snapshot.provider == .codex else {
            return WindowVisibility.visible(live, provider: snapshot.provider, showLunaReserve: false)
        }
        return live.filter { $0.id.hasPrefix("codex.") && !WindowVisibility.isSpark($0) }
    }

    static func menuBarKinds(snapshot: ProviderUsageSnapshot?, provider: UsageProvider) -> [QuotaWindowKind] {
        let present = Set(
            (snapshot.map { menuBarCandidates($0) } ?? []).compactMap { QuotaWindowKind.of($0, provider: provider) })
        guard present.isEmpty else { return QuotaWindowKind.ordered(present) }
        return provider == .codex ? [.weekly] : QuotaWindowKind.allCases
    }

    static func menuBarWindows(state: ProviderViewState, selection: Set<QuotaWindowKind> = [])
        -> [QuotaWindow]
    {
        guard state.status == .ready, let snapshot = state.snapshot else { return [] }
        let candidates = menuBarCandidates(snapshot)
        if !selection.isEmpty {
            let chosen = QuotaWindowKind.ordered(selection).compactMap { kind in
                candidates.first { QuotaWindowKind.of($0, provider: snapshot.provider) == kind }
            }
            if !chosen.isEmpty || snapshot.provider == .claude { return chosen }
        }
        let windows = WindowVisibility.visible(snapshot.windows, provider: snapshot.provider, showLunaReserve: false)
            .filter { ($0.resetsAt ?? .distantFuture) > Date() }
        let weekly = windows.filter { $0.durationMinutes == 10_080 }
        if snapshot.provider == .codex {
            let general = weekly.first { $0.id.hasPrefix("codex.") } ?? windows.first { $0.id.hasPrefix("codex.") }
            return general.map { [$0] } ?? []
        }
        let scoped = weekly.filter { ($0.displayName ?? "").isEmpty == false }
        let automatic =
            scoped.min(by: { $0.remainingPercentage < $1.remainingPercentage })
            ?? weekly.first ?? windows.min { $0.remainingPercentage < $1.remainingPercentage }
        return automatic.map { [$0] } ?? []
    }

    static func overlay(
        _ snapshot: ProviderUsageSnapshot, capture: ClaudeCapturedSnapshot?, accountFingerprint: String?,
        now: Date = Date()
    ) -> ProviderUsageSnapshot? {
        guard let capture, let accountFingerprint, capture.accountFingerprint == accountFingerprint,
            let capturedAt = snapshot.capturedAt, capture.capturedAt > capturedAt
        else { return nil }
        var changed = false
        let windows = snapshot.windows.map { window -> QuotaWindow in
            guard let captured = capture.windows[window.id], let reset = window.resetsAt, reset > now,
                let capturedReset = captured.resetsAt, abs(capturedReset.timeIntervalSince(reset)) <= 120,
                captured.usedPercentage > window.usedPercentage
            else { return window }
            changed = true
            return QuotaWindow(
                id: window.id, usedPercentage: captured.usedPercentage, resetsAt: window.resetsAt,
                durationMinutes: window.durationMinutes, displayName: window.displayName)
        }
        return changed ? snapshot.replacingWindows(windows) : nil
    }
}

extension ProviderUsageSnapshot {
    func replacingWindows(_ windows: [QuotaWindow]) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider, windows: windows, dailyUsage: dailyUsage, summary: summary,
            availableResetCredits: availableResetCredits, creditBalance: creditBalance, capturedAt: capturedAt,
            modelBuckets: modelBuckets, activityReadSucceeded: activityReadSucceeded)
    }

    func carryingActivity(from other: ProviderUsageSnapshot?) -> ProviderUsageSnapshot {
        guard let other else { return self }
        return ProviderUsageSnapshot(
            provider: provider, windows: windows, dailyUsage: other.dailyUsage, summary: summary,
            availableResetCredits: availableResetCredits, creditBalance: creditBalance, capturedAt: capturedAt,
            modelBuckets: other.modelBuckets, activityReadSucceeded: other.activityReadSucceeded)
    }
}
