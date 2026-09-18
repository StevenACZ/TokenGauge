import Foundation
import os

public enum UsageHistoryError: Error, Equatable, Sendable {
    case openFailed(String)
    case statementFailed(String)
}

public struct HistoryTokenRow: Equatable, Sendable {
    public let day: String
    public let provider: UsageProvider
    public let model: String
    public let tokens: Int

    public init(day: String, provider: UsageProvider, model: String, tokens: Int) {
        self.day = day
        self.provider = provider
        self.model = model
        self.tokens = tokens
    }
}

public struct HistoryQuotaRow: Equatable, Sendable {
    public let sampledAt: Date
    public let provider: UsageProvider
    public let windowID: String
    public let displayName: String?
    public let usedPercentage: Double
    public let resetsAt: Date?
    public let durationMinutes: Int?
    public let isVerified: Bool
    public let continuityResetAt: Date?
    public let continuityStartedAt: Date?
    public let accountFingerprint: String?

    public init(
        sampledAt: Date,
        provider: UsageProvider,
        windowID: String,
        displayName: String?,
        usedPercentage: Double,
        resetsAt: Date?,
        durationMinutes: Int? = nil,
        isVerified: Bool = false,
        continuityStartedAt: Date? = nil,
        continuityResetAt: Date? = nil,
        accountFingerprint: String? = nil
    ) {
        self.sampledAt = sampledAt
        self.provider = provider
        self.windowID = windowID
        self.displayName = displayName
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
        self.isVerified = isVerified
        self.continuityStartedAt = continuityStartedAt
        self.continuityResetAt = continuityResetAt
        self.accountFingerprint = accountFingerprint
    }
}

public enum UsageHistoryStore {
    public static let sampleInterval: TimeInterval = 900
    public static let quotaRetentionDays = 730

    public static func record(
        _ snapshot: ProviderUsageSnapshot,
        at url: URL = UsagePaths.history(),
        now: Date = Date(),
        recordQuota: Bool = true,
        recordTokens: Bool = true,
        accountFingerprint: String? = nil
    ) throws {
        try write(url) { connection in
            try connection.transaction {
                if recordQuota {
                    try writeQuota(connection, snapshot: snapshot, accountFingerprint: accountFingerprint)
                }
                if recordTokens && snapshot.activityReadSucceeded {
                    try writeTokens(connection, snapshot: snapshot, now: now)
                }
                try prune(connection, now: now)
            }
        }
    }

    public static func recordEffort(
        _ records: [EffortUsageRecord], at url: URL = UsagePaths.history()
    ) throws {
        let valid = records.filter(\.isValid)
        guard !valid.isEmpty else { return }
        try write(url) { connection in
            try connection.transaction {
                for record in valid { try writeEffort(connection, record: record) }
            }
        }
    }

    public static func effortRows(
        since day: String? = nil, through lastDay: String? = nil, at url: URL = UsagePaths.history()
    ) throws -> [HistoryEffortRow] {
        try read(url) { connection in
            try readEffortRows(connection, since: day, through: lastDay)
        }
    }

    public static func tokenRows(
        since day: String? = nil,
        through lastDay: String? = nil,
        at url: URL = UsagePaths.history()
    ) throws -> [HistoryTokenRow] {
        try read(url) { connection in
            try readTokenRows(connection, since: day, through: lastDay)
        }
    }

    public static func usageDays(
        provider: UsageProvider? = nil,
        at url: URL = UsagePaths.history()
    ) throws -> Set<String> {
        try read(url) { connection in
            try readUsageDays(connection, provider: provider)
        }
    }

    public static func usageDaysByProvider(
        at url: URL = UsagePaths.history()
    ) throws -> [UsageProvider: Set<String>] {
        try read(url) { connection in
            try readUsageDaysByProvider(connection)
        }
    }

    public static func quotaRows(
        provider: UsageProvider? = nil,
        since: Date? = nil,
        until: Date? = nil,
        at url: URL = UsagePaths.history()
    ) throws -> [HistoryQuotaRow] {
        try read(url) { connection in
            try readQuotaRows(connection, provider: provider, since: since, until: until)
        }
    }

    public static func paceRows(
        provider: UsageProvider? = nil, windowID: String? = nil, since: Date? = nil, until: Date? = nil,
        accountFingerprint: String? = nil, at url: URL = UsagePaths.history()
    ) throws -> [HistoryPaceRow] {
        try read(url) { connection in
            try readPaceRows(
                connection, provider: provider, windowID: windowID, since: since, until: until,
                accountFingerprint: accountFingerprint)
        }
    }

    public static func recentPaces(
        for keys: [HistoryPaceKey], activeOnly: Bool = false, limitPerWindow: Int = 2,
        before: Date? = nil, matchingLatestQuota: Bool = false, accountFingerprint: String? = nil,
        at url: URL = UsagePaths.history()
    ) throws -> [HistoryPaceRow] {
        guard !keys.isEmpty, limitPerWindow > 0 else { return [] }
        return try read(url) { connection in
            var rows: [HistoryPaceRow] = []
            for key in Set(keys).sorted(by: { $0.id < $1.id }) {
                let candidates = try readRecentPaces(
                    connection, key: key, activeOnly: activeOnly, limit: limitPerWindow, before: before,
                    accountFingerprint: accountFingerprint)
                if matchingLatestQuota {
                    let quota = try latestQuota(connection, provider: key.provider, windowID: key.windowID)
                    rows += candidates.filter { quota?.isVerified == true && $0.pace.sampledAt == quota?.sampledAt }
                } else {
                    rows += candidates
                }
            }
            return rows
        }
    }

    public static func bounds(at url: URL = UsagePaths.history()) throws -> HistoryBounds {
        try read(url) { connection in
            try readBounds(connection)
        }
    }

    static func bucket(_ date: Date, interval: TimeInterval = sampleInterval) -> Int64 {
        let seconds = date.timeIntervalSince1970
        return Int64((seconds / interval).rounded(.down) * interval)
    }
}

extension UsageHistoryStore {
    struct Registry {
        var preparations: [String: Int] = [:]
        var lastEntryWasReadOnly: Bool?
        var entries = 0
    }

    private static let registry = OSAllocatedUnfairLock(initialState: Registry())

    static var preparedPaths: Set<String> {
        registry.withLock { Set($0.preparations.keys) }
    }

    static func schemaPreparations(for path: String) -> Int {
        registry.withLock { $0.preparations[path] ?? 0 }
    }

    static var lastEntryWasReadOnly: Bool? {
        registry.withLock { $0.lastEntryWasReadOnly }
    }

    public static var entryCount: Int {
        registry.withLock { $0.entries }
    }

    static func write<T>(_ url: URL, _ body: (SQLiteConnection) throws -> T) throws -> T {
        let connection = try SQLiteConnection.open(url, readOnly: false)
        defer { connection.close() }
        recordEntry(readOnly: connection.isReadOnly)
        try prepareIfNeeded(connection, path: url.path)
        return try body(connection)
    }

    static func read<T>(_ url: URL, _ body: (SQLiteConnection) throws -> T) throws -> T {
        guard isPrepared(url.path), FileManager.default.fileExists(atPath: url.path) else {
            return try write(url, body)
        }
        let connection = try SQLiteConnection.open(url, readOnly: true)
        defer { connection.close() }
        recordEntry(readOnly: connection.isReadOnly)
        if try schemaVersion(connection) < Schema.version {
            return try write(url, body)
        }
        return try body(connection)
    }

    private static func recordEntry(readOnly: Bool) {
        registry.withLock {
            $0.lastEntryWasReadOnly = readOnly
            $0.entries += 1
        }
    }

    private static func isPrepared(_ path: String) -> Bool {
        registry.withLock { $0.preparations[path] != nil }
    }

    private static func markPrepared(_ path: String) {
        registry.withLock { $0.preparations[path, default: 0] += 1 }
    }

    private static func prepareIfNeeded(_ connection: SQLiteConnection, path: String) throws {
        if isPrepared(path), try schemaVersion(connection) >= Schema.version { return }
        try prepareSchema(connection)
        markPrepared(path)
    }
}
