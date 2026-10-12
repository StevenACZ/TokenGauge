import Foundation
import TokenGaugeCore

struct ClaudeAccountState: Equatable {
    enum Status: Equatable {
        case loading, ready, signedOut, expired, noAccess, rateLimited, unreachable, invalidLocation
    }

    var status: Status = .loading
    var windows: [QuotaWindow] = []
    var capturedAt: Date?
    var nextRead = Date.distantPast
    var failures = 0
}

// Other Claude Code logins, opt-in: each one is read every few minutes through the
// same usage endpoint, by a shell that runs on the Mac where that login lives.
@MainActor
final class ClaudeAccountsStore: ObservableObject {
    static let shared = ClaudeAccountsStore(
        defaults: DemoData.isEnabled ? UserDefaults(suiteName: DemoData.defaultsSuite) ?? .standard : .standard)

    static let enabledKey = "claudeExtraAccountsEnabled"
    static let accountsKey = "claudeExtraAccounts"
    static let primaryKey = "claudePrimaryAccount"
    static let interval: TimeInterval = 300
    static let minimumGap: TimeInterval = 120

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            enabled ? start() : stop()
        }
    }
    @Published private(set) var accounts: [ClaudeExtraAccount]
    @Published private(set) var states: [UUID: ClaudeAccountState] = [:]
    @Published private(set) var primaryID: UUID?
    @Published private(set) var weekday: Int

    private let defaults: UserDefaults
    private let read: @Sendable (ClaudeAccountLocation) async -> ClaudeExtraAccountResult
    private let currentWeekday: () -> Int
    private var timer: Timer?
    private var inFlight: Set<UUID> = []
    private var pendingEdits: [UUID: Task<Void, Never>] = [:]

    init(
        defaults: UserDefaults = .standard,
        read: @escaping @Sendable (ClaudeAccountLocation) async -> ClaudeExtraAccountResult = ClaudeAccountsStore.fetch,
        currentWeekday: @escaping () -> Int = { Calendar.current.component(.weekday, from: Date()) }
    ) {
        self.defaults = defaults
        self.read = read
        self.currentWeekday = currentWeekday
        weekday = currentWeekday()
        enabled = defaults.bool(forKey: Self.enabledKey)
        accounts =
            defaults.data(forKey: Self.accountsKey).flatMap {
                try? JSONDecoder().decode([ClaudeExtraAccount].self, from: $0)
            }
            ?? []
        primaryID = defaults.string(forKey: Self.primaryKey).flatMap(UUID.init(uuidString:))
        if enabled { start() }
    }

    var primaryAccount: ClaudeExtraAccount? {
        guard enabled, let primaryID else { return nil }
        return accounts.first { $0.id == primaryID && $0.isVisible(onWeekday: weekday) }
    }

    var visibleAccounts: [ClaudeExtraAccount] {
        let primary = primaryAccount?.id
        return accounts.filter { $0.id != primary && $0.isVisible(onWeekday: weekday) }
    }

    var primary: ClaudePrimaryAccount? {
        primaryAccount.map { ClaudePrimaryAccount(name: $0.name, state: Self.viewState(state(for: $0))) }
    }

    func setPrimary(_ id: UUID?) {
        primaryID = id
        defaults.set(id?.uuidString, forKey: Self.primaryKey)
        guard let id, var account = accounts.first(where: { $0.id == id }) else { return }
        if account.hidden {
            account.hidden = false
            update(account)
        } else {
            Task { await refresh(id, force: true) }
        }
    }

    var isShowing: Bool { enabled && !visibleAccounts.isEmpty }

    func state(for account: ClaudeExtraAccount) -> ClaudeAccountState {
        states[account.id] ?? ClaudeAccountState()
    }

    var menuBarAccounts: [MenuBarPresentation.Account] {
        guard enabled else { return [] }
        return visibleAccounts.filter(\.showsInMenuBar).map { account in
            let session = state(for: account).windows.first { $0.durationMinutes == 300 }
            return MenuBarPresentation.Account(
                id: account.id, name: account.name, tint: account.tint, icon: account.icon,
                letter: account.initial, remaining: session?.remainingPercentage)
        }
    }

    func add() {
        accounts.append(ClaudeExtraAccount(name: "", location: ""))
        save()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        states[id] = nil
        if primaryID == id { setPrimary(nil) }
        save()
    }

    func update(_ account: ClaudeExtraAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let moved = accounts[index].location != account.location
        let appeared = !accounts[index].isVisible(onWeekday: weekday) && account.isVisible(onWeekday: weekday)
        accounts[index] = account
        save()
        if !account.isVisible(onWeekday: weekday) { states[account.id] = nil }
        if appeared, !moved { Task { await refresh(account.id, force: true) } }
        guard moved else { return }
        states[account.id] = nil
        pendingEdits[account.id]?.cancel()
        pendingEdits[account.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.refresh(account.id, force: true)
        }
    }

    func refreshAll(force: Bool = false) {
        guard enabled else { return }
        let today = currentWeekday()
        if today != weekday { weekday = today }
        for account in accounts {
            if account.isVisible(onWeekday: weekday) {
                Task { await refresh(account.id, force: force) }
            } else if states[account.id] != nil {
                states[account.id] = nil
            }
        }
    }

    func refresh(_ id: UUID, force: Bool) async {
        guard enabled, let account = accounts.first(where: { $0.id == id }), account.isVisible(onWeekday: weekday),
            !inFlight.contains(id)
        else { return }
        var state = states[id] ?? ClaudeAccountState()
        guard Self.isDue(state, at: Date(), force: force) else { return }
        guard let location = ClaudeAccountLocation.parse(account.location) else {
            state.status = .invalidLocation
            states[id] = state
            return
        }
        inFlight.insert(id)
        let result = await read(location)
        inFlight.remove(id)
        guard accounts.contains(where: { $0.id == id && $0.location == account.location }) else { return }
        states[id] = Self.apply(result, to: state, at: Date())
    }

    static func isDue(_ state: ClaudeAccountState, at now: Date, force: Bool) -> Bool {
        if now >= state.nextRead { return true }
        return force && state.status == .ready && state.failures == 0
            && now >= state.nextRead.addingTimeInterval(minimumGap - interval)
    }

    static func apply(_ result: ClaudeExtraAccountResult, to previous: ClaudeAccountState, at now: Date)
        -> ClaudeAccountState
    {
        var state = previous
        switch result {
        case .windows(let windows):
            state = ClaudeAccountState(
                status: .ready, windows: windows, capturedAt: now, nextRead: now.addingTimeInterval(interval))
            return state
        case .rateLimited(let retryAfter):
            state.failures += 1
            let backoff = [300.0, 600, 1200, 1800][min(state.failures, 4) - 1]
            state.nextRead = now.addingTimeInterval(max(backoff, retryAfter ?? 0))
            state.status = state.windows.isEmpty ? .rateLimited : state.status
            return state
        case .status(let code):
            state.status = code == 401 ? .signedOut : (code == 402 || code == 403) ? .noAccess : .unreachable
        case .expired:
            state.status = .expired
        case .unreachable:
            state.status = .unreachable
        }
        state.windows = []
        state.capturedAt = nil
        state.nextRead = now.addingTimeInterval(minimumGap)
        return state
    }

    static func viewState(_ state: ClaudeAccountState, now: Date = Date()) -> ProviderViewState {
        let snapshot =
            state.capturedAt == nil
            ? nil
            : ProviderUsageSnapshot(
                provider: .claude, windows: state.windows, dailyUsage: [], summary: nil, availableResetCredits: nil,
                creditBalance: nil, capturedAt: state.capturedAt, activityReadSucceeded: false)
        let status: ProviderStatus
        switch state.status {
        case .loading: status = .loading
        case .ready: status = snapshot.map { ProviderStateResolver.claudeStatus(snapshot: $0, now: now) } ?? .waiting
        case .signedOut, .expired: status = .authenticationRequired
        case .noAccess: status = .accessDenied
        case .rateLimited, .unreachable, .invalidLocation: status = .unavailable
        }
        return ProviderViewState(snapshot: snapshot, status: status, isRefreshing: state.status == .loading)
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        refreshAll()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        states = [:]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) { defaults.set(data, forKey: Self.accountsKey) }
    }

    nonisolated static func fetch(_ location: ClaudeAccountLocation) async -> ClaudeExtraAccountResult {
        let (executable, arguments) = location.processArguments
        let output = try? await BlockingWork.run {
            ClaudeOAuthTokenReader.boundedPayload(
                executable: URL(fileURLWithPath: executable), arguments: arguments, timeout: 25)
        }
        return ClaudeExtraAccountParser.parse(output ?? nil)
    }
}
