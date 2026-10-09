import Foundation
import TokenGaugeCore

struct ClaudeAccountState: Equatable {
    enum Status: Equatable {
        case loading, ready, signedOut, noAccess, rateLimited, unreachable, invalidLocation
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

    private let defaults: UserDefaults
    private let read: @Sendable (ClaudeAccountLocation) async -> ClaudeExtraAccountResult
    private var timer: Timer?
    private var inFlight: Set<UUID> = []
    private var pendingEdits: [UUID: Task<Void, Never>] = [:]

    init(
        defaults: UserDefaults = .standard,
        read: @escaping @Sendable (ClaudeAccountLocation) async -> ClaudeExtraAccountResult = ClaudeAccountsStore.fetch
    ) {
        self.defaults = defaults
        self.read = read
        enabled = defaults.bool(forKey: Self.enabledKey)
        accounts =
            defaults.data(forKey: Self.accountsKey).flatMap {
                try? JSONDecoder().decode([ClaudeExtraAccount].self, from: $0)
            }
            ?? []
        if enabled { start() }
    }

    var isShowing: Bool { enabled && !accounts.isEmpty }

    func state(for account: ClaudeExtraAccount) -> ClaudeAccountState {
        states[account.id] ?? ClaudeAccountState()
    }

    var menuBarAccounts: [MenuBarPresentation.Account] {
        guard enabled else { return [] }
        return accounts.filter(\.showsInMenuBar).map { account in
            let session = state(for: account).windows.first { $0.durationMinutes == 300 }
            return MenuBarPresentation.Account(
                id: account.id, name: account.name, tint: account.tint, icon: account.icon,
                remaining: session?.remainingPercentage)
        }
    }

    func add() {
        accounts.append(ClaudeExtraAccount(name: "", location: ""))
        save()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        states[id] = nil
        save()
    }

    func update(_ account: ClaudeExtraAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let moved = accounts[index].location != account.location
        accounts[index] = account
        save()
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
        for account in accounts {
            Task { await refresh(account.id, force: force) }
        }
    }

    func refresh(_ id: UUID, force: Bool) async {
        guard enabled, let account = accounts.first(where: { $0.id == id }), !inFlight.contains(id) else { return }
        var state = states[id] ?? ClaudeAccountState()
        let now = Date()
        let early =
            force && state.status == .ready
            && now >= state.nextRead.addingTimeInterval(Self.minimumGap - Self.interval)
        guard now >= state.nextRead || early else { return }
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

    static func apply(_ result: ClaudeExtraAccountResult, to previous: ClaudeAccountState, at now: Date)
        -> ClaudeAccountState
    {
        var state = previous
        switch result {
        case .windows(let windows):
            state = ClaudeAccountState(
                status: .ready, windows: windows, capturedAt: now, nextRead: now.addingTimeInterval(interval))
            return state
        case .status(429):
            state.failures += 1
            let backoff = [300.0, 600, 1200, 1800][min(state.failures, 4) - 1]
            state.nextRead = now.addingTimeInterval(backoff)
            state.status = state.windows.isEmpty ? .rateLimited : state.status
            return state
        case .status(let code):
            state.status = code == 401 ? .signedOut : (code == 402 || code == 403) ? .noAccess : .unreachable
        case .unreachable:
            state.status = .unreachable
        }
        state.windows = []
        state.capturedAt = nil
        state.nextRead = now.addingTimeInterval(minimumGap)
        return state
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
