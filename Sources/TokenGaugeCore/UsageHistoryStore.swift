import Darwin
import Foundation
import SQLite3

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
        continuityResetAt: Date? = nil
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
        recordTokens: Bool = true
    ) throws {
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        try exec(handle, "BEGIN IMMEDIATE;")
        do {
            if recordQuota { try writeQuota(handle, snapshot: snapshot) }
            if recordTokens && snapshot.activityReadSucceeded {
                try writeTokens(handle, snapshot: snapshot, now: now)
            }
            try prune(handle, now: now)
            try exec(handle, "COMMIT;")
        } catch {
            try? exec(handle, "ROLLBACK;")
            throw error
        }
    }

    public static func recordEffort(
        _ records: [EffortUsageRecord], at url: URL = UsagePaths.history()
    ) throws {
        let valid = records.filter(\.isValid)
        guard !valid.isEmpty else { return }
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        try exec(handle, "BEGIN IMMEDIATE;")
        do {
            for record in valid { try writeEffort(handle, record: record) }
            try exec(handle, "COMMIT;")
        } catch {
            try? exec(handle, "ROLLBACK;")
            throw error
        }
    }

    public static func effortRows(
        since day: String? = nil, through lastDay: String? = nil, at url: URL = UsagePaths.history()
    ) throws -> [HistoryEffortRow] {
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        let sql = """
            SELECT day, provider, model, effort, SUM(tokens) FROM effort_events
            WHERE day >= ?1 AND day <= ?2
            GROUP BY day, provider, model, effort ORDER BY day, provider, model, effort;
            """
        var rows: [HistoryEffortRow] = []
        try query(handle, sql) { statement in
            bind(statement, 1, day ?? "0000-01-01")
            bind(statement, 2, lastDay ?? "9999-12-31")
        } each: { statement in
            guard let provider = UsageProvider(rawValue: text(statement, 1)) else { return }
            rows.append(
                HistoryEffortRow(
                    day: text(statement, 0), provider: provider, model: text(statement, 2), effort: text(statement, 3),
                    tokens: Int(sqlite3_column_int64(statement, 4))))
        }
        return rows
    }

    public static func tokenRows(
        since day: String? = nil,
        through lastDay: String? = nil,
        at url: URL = UsagePaths.history()
    ) throws -> [HistoryTokenRow] {
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        let sql = """
            SELECT day, provider, model, tokens FROM daily_tokens
            WHERE day >= ?1 AND day <= ?2
            ORDER BY day, provider, model;
            """
        var rows: [HistoryTokenRow] = []
        try query(handle, sql) { statement in
            bind(statement, 1, day ?? "0000-01-01")
            bind(statement, 2, lastDay ?? "9999-12-31")
        } each: { statement in
            guard let provider = UsageProvider(rawValue: text(statement, 1)) else { return }
            rows.append(
                HistoryTokenRow(
                    day: text(statement, 0),
                    provider: provider,
                    model: text(statement, 2),
                    tokens: Int(sqlite3_column_int64(statement, 3))
                )
            )
        }
        return rows
    }

    public static func quotaRows(
        provider: UsageProvider? = nil,
        since: Date? = nil,
        until: Date? = nil,
        at url: URL = UsagePaths.history()
    ) throws -> [HistoryQuotaRow] {
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        return try readQuotaRows(handle, provider: provider, since: since, until: until)
    }

    private static func readQuotaRows(
        _ handle: OpaquePointer, provider: UsageProvider? = nil, since: Date? = nil, until: Date? = nil
    ) throws -> [HistoryQuotaRow] {
        let sql = """
            SELECT COALESCE(observed_at, sampled_at), provider, window_id, display_name, used_percentage, resets_at,
                duration_minutes, verified, continuity_started_at, continuity_reset_at
            FROM quota_samples
            WHERE sampled_at >= ?2 AND sampled_at <= ?3 AND (?1 IS NULL OR provider = ?1)
                AND COALESCE(observed_at, sampled_at) >= ?4 AND COALESCE(observed_at, sampled_at) <= ?5
            ORDER BY sampled_at, provider, window_id;
            """
        var rows: [HistoryQuotaRow] = []
        try query(handle, sql) { statement in
            bind(statement, 1, provider?.rawValue)
            sqlite3_bind_int64(statement, 2, since.map { bucket($0) } ?? Int64.min)
            sqlite3_bind_int64(statement, 3, until.map { bucket($0) } ?? Int64.max)
            sqlite3_bind_double(statement, 4, since?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude)
            sqlite3_bind_double(statement, 5, until?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude)
        } each: { statement in
            guard let provider = UsageProvider(rawValue: text(statement, 1)) else { return }
            rows.append(
                HistoryQuotaRow(
                    sampledAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    provider: provider,
                    windowID: text(statement, 2),
                    displayName: optionalText(statement, 3),
                    usedPercentage: sqlite3_column_double(statement, 4),
                    resetsAt: date(statement, 5),
                    durationMinutes: sqlite3_column_type(statement, 6) == SQLITE_NULL
                        ? nil : Int(sqlite3_column_int64(statement, 6)),
                    isVerified: sqlite3_column_int(statement, 7) == 1,
                    continuityStartedAt: date(statement, 8), continuityResetAt: date(statement, 9)
                )
            )
        }
        return rows
    }

    public static func paceRows(
        provider: UsageProvider? = nil, windowID: String? = nil, since: Date? = nil, until: Date? = nil,
        at url: URL = UsagePaths.history()
    ) throws -> [HistoryPaceRow] {
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        return try readPaces(
            handle,
            suffix: """
                WHERE sampled_at >= ?1 AND sampled_at <= ?2
                    AND (?3 IS NULL OR provider = ?3) AND (?4 IS NULL OR window_id = ?4)
                ORDER BY sampled_at, provider, window_id
                """
        ) { statement in
            sqlite3_bind_double(statement, 1, since?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude)
            sqlite3_bind_double(statement, 2, until?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude)
            bind(statement, 3, provider?.rawValue)
            bind(statement, 4, windowID)
        }
    }

    public static func recentPaces(
        for keys: [HistoryPaceKey], activeOnly: Bool = false, limitPerWindow: Int = 2,
        before: Date? = nil, matchingLatestQuota: Bool = false, at url: URL = UsagePaths.history()
    ) throws -> [HistoryPaceRow] {
        guard !keys.isEmpty, limitPerWindow > 0 else { return [] }
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        var rows: [HistoryPaceRow] = []
        for key in Set(keys).sorted(by: { $0.id < $1.id }) {
            let candidates = try readRecentPaces(
                handle, key: key, activeOnly: activeOnly, limit: limitPerWindow, before: before)
            if matchingLatestQuota {
                let quota = try latestQuota(handle, provider: key.provider, windowID: key.windowID)
                rows += candidates.filter { quota?.isVerified == true && $0.pace.sampledAt == quota?.sampledAt }
            } else {
                rows += candidates
            }
        }
        return rows
    }

    private static func readRecentPaces(
        _ handle: OpaquePointer, key: HistoryPaceKey, activeOnly: Bool, limit: Int, before: Date?
    ) throws -> [HistoryPaceRow] {
        let active = activeOnly ? "AND is_active = 1" : ""
        return try readPaces(
            handle,
            suffix: """
                WHERE provider = ?1 AND window_id = ?2 AND sampled_at < ?3 \(active)
                ORDER BY sampled_at DESC LIMIT ?4
                """
        ) { statement in
            bind(statement, 1, key.provider.rawValue)
            bind(statement, 2, key.windowID)
            sqlite3_bind_double(statement, 3, before?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude)
            sqlite3_bind_int64(statement, 4, Int64(limit))
        }
    }

    private static func readPaces(
        _ handle: OpaquePointer, suffix: String, bindings: (OpaquePointer) -> Void
    ) throws -> [HistoryPaceRow] {
        var rows: [HistoryPaceRow] = []
        try query(
            handle,
            """
            SELECT provider, window_id, sampled_at, display_name, points_per_hour, observed_minutes,
                resets_at, last_used_percentage, is_active FROM pace_samples
            \(suffix);
            """, bindings: bindings
        ) { statement in
            guard let provider = UsageProvider(rawValue: text(statement, 0)) else { return }
            rows.append(
                HistoryPaceRow(
                    key: HistoryPaceKey(provider: provider, windowID: text(statement, 1)),
                    displayName: optionalText(statement, 3),
                    pace: QuotaPace(
                        pointsPerHour: sqlite3_column_double(statement, 4),
                        observedMinutes: sqlite3_column_double(statement, 5),
                        sampledAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        resetsAt: date(statement, 6), lastUsedPercentage: sqlite3_column_double(statement, 7)),
                    isActive: sqlite3_column_int(statement, 8) == 1))
        }
        return rows
    }

    private static func archivePace(
        _ handle: OpaquePointer, snapshot: ProviderUsageSnapshot, window: QuotaWindow,
        previous: HistoryQuotaRow?, now: Date
    ) throws {
        guard window.durationMinutes == 10_080 else { return }
        let rows = try readQuotaRows(
            handle, provider: snapshot.provider, since: now.addingTimeInterval(-3600), until: now)
        guard let pace = HistoryAnalytics.pace(rows: rows, provider: snapshot.provider, windowID: window.id, now: now)
        else { return }
        let key = HistoryPaceKey(provider: snapshot.provider, windowID: window.id)
        let increased =
            previous.map {
                $0.isVerified && $0.durationMinutes == window.durationMinutes
                    && HistoryAnalytics.sameReset($0.resetsAt, window.resetsAt)
                    && window.usedPercentage > $0.usedPercentage
            } ?? false
        let activeHistory = try readRecentPaces(handle, key: key, activeOnly: true, limit: 1, before: nil)
        let seed = pace.pointsPerHour > 0 && activeHistory.isEmpty
        try run(
            handle,
            """
            INSERT OR IGNORE INTO pace_samples
                (provider, window_id, sampled_at, display_name, points_per_hour, observed_minutes,
                    resets_at, last_used_percentage, is_active)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9);
            """
        ) { statement in
            bind(statement, 1, snapshot.provider.rawValue)
            bind(statement, 2, window.id)
            sqlite3_bind_double(statement, 3, pace.sampledAt.timeIntervalSince1970)
            bind(statement, 4, window.displayName)
            sqlite3_bind_double(statement, 5, pace.pointsPerHour)
            sqlite3_bind_double(statement, 6, pace.observedMinutes)
            if let reset = pace.resetsAt {
                sqlite3_bind_double(statement, 7, reset.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 7)
            }
            sqlite3_bind_double(statement, 8, window.usedPercentage)
            sqlite3_bind_int(statement, 9, increased || seed ? 1 : 0)
        }
    }

    public static func bounds(at url: URL = UsagePaths.history()) throws -> HistoryBounds {
        let handle = try open(url)
        defer { sqlite3_close(handle) }
        try prepareSchema(handle)
        var result = HistoryBounds(firstDay: nil, lastDay: nil)
        let sql = """
            SELECT (SELECT MIN(day) FROM daily_tokens), (SELECT MAX(day) FROM daily_tokens),
                (SELECT MIN(day) FROM effort_events), (SELECT MAX(day) FROM effort_events);
            """
        try query(handle, sql, bindings: { _ in }) { statement in
            let firstDays = [optionalText(statement, 0), optionalText(statement, 2)].compactMap { $0 }
            let lastDays = [optionalText(statement, 1), optionalText(statement, 3)].compactMap { $0 }
            result = HistoryBounds(firstDay: firstDays.min(), lastDay: lastDays.max())
        }
        return result
    }

    static func bucket(_ date: Date, interval: TimeInterval = sampleInterval) -> Int64 {
        let seconds = date.timeIntervalSince1970
        return Int64((seconds / interval).rounded(.down) * interval)
    }
}

extension UsageHistoryStore {
    private enum Schema {
        static let statements = """
            CREATE TABLE IF NOT EXISTS quota_samples (
                provider TEXT NOT NULL,
                window_id TEXT NOT NULL,
                sampled_at INTEGER NOT NULL,
                display_name TEXT,
                duration_minutes INTEGER,
                used_percentage REAL NOT NULL,
                resets_at INTEGER,
                PRIMARY KEY (provider, window_id, sampled_at)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS quota_samples_sampled_at ON quota_samples(sampled_at);
            CREATE TABLE IF NOT EXISTS daily_tokens (
                day TEXT NOT NULL,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                tokens INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (day, provider, model)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS pace_samples (
                provider TEXT NOT NULL, window_id TEXT NOT NULL, sampled_at REAL NOT NULL,
                display_name TEXT, points_per_hour REAL NOT NULL, observed_minutes REAL NOT NULL,
                resets_at REAL, last_used_percentage REAL, is_active INTEGER NOT NULL,
                PRIMARY KEY(provider, window_id, sampled_at)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS pace_samples_sampled_at ON pace_samples(sampled_at);
            CREATE INDEX IF NOT EXISTS pace_samples_active ON pace_samples(provider, window_id, is_active, sampled_at);
            CREATE TABLE IF NOT EXISTS effort_events (
                id TEXT NOT NULL PRIMARY KEY,
                provider TEXT NOT NULL,
                occurred_at REAL NOT NULL,
                day TEXT NOT NULL,
                model TEXT NOT NULL,
                effort TEXT NOT NULL,
                tokens INTEGER NOT NULL
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS effort_events_day_provider ON effort_events(day, provider);
            """

        static let observedTotalsViews = """
            DROP VIEW IF EXISTS monthly_totals;
            DROP VIEW IF EXISTS weekly_totals;
            DROP VIEW IF EXISTS daily_totals;
            CREATE VIEW daily_totals AS
                SELECT day, provider, MAX(tokens) AS tokens FROM (
                    SELECT day, provider,
                        MAX(COALESCE(MAX(CASE WHEN model = 'all' THEN tokens END), 0),
                            COALESCE(SUM(CASE WHEN model != 'all' THEN tokens END), 0)) AS tokens
                    FROM daily_tokens GROUP BY day, provider
                    UNION ALL
                    SELECT day, provider, SUM(tokens) AS tokens
                    FROM effort_events GROUP BY day, provider
                ) GROUP BY day, provider;
            CREATE VIEW weekly_totals AS
                SELECT date(day, 'weekday 0', '-6 days') AS week_start, provider, SUM(tokens) AS tokens
                FROM daily_totals GROUP BY week_start, provider;
            CREATE VIEW monthly_totals AS
                SELECT substr(day, 1, 7) AS month, provider, SUM(tokens) AS tokens
                FROM daily_totals GROUP BY month, provider;
            """

    }

    private static func prepareSchema(_ handle: OpaquePointer) throws {
        try exec(handle, "BEGIN IMMEDIATE;")
        do {
            try exec(handle, Schema.statements)
            var columns = Set<String>()
            try query(handle, "PRAGMA table_info(quota_samples);", bindings: { _ in }) { statement in
                columns.insert(text(statement, 1))
            }
            if !columns.contains("verified") {
                try exec(handle, "ALTER TABLE quota_samples ADD COLUMN verified INTEGER NOT NULL DEFAULT 0;")
            }
            if !columns.contains("observed_at") {
                try exec(handle, "ALTER TABLE quota_samples ADD COLUMN observed_at REAL;")
            }
            if !columns.contains("continuity_started_at") {
                try exec(handle, "ALTER TABLE quota_samples ADD COLUMN continuity_started_at REAL;")
            }
            if !columns.contains("continuity_reset_at") {
                try exec(handle, "ALTER TABLE quota_samples ADD COLUMN continuity_reset_at REAL;")
            }
            var version: Int32 = 0
            try query(handle, "PRAGMA user_version;", bindings: { _ in }) { statement in
                version = sqlite3_column_int(statement, 0)
            }
            if version < 1 {
                try exec(handle, Schema.observedTotalsViews)
                try exec(handle, "PRAGMA user_version = 1;")
            }
            try exec(handle, "COMMIT;")
        } catch {
            try? exec(handle, "ROLLBACK;")
            throw error
        }
    }

    private static func writeEffort(_ handle: OpaquePointer, record: EffortUsageRecord) throws {
        let sql = """
            INSERT INTO effort_events (id, provider, occurred_at, day, model, effort, tokens)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            ON CONFLICT(id) DO UPDATE SET
                day = CASE WHEN excluded.occurred_at < effort_events.occurred_at THEN excluded.day ELSE effort_events.day END,
                occurred_at = MIN(effort_events.occurred_at, excluded.occurred_at),
                model = CASE WHEN effort_events.model = 'unknown' THEN excluded.model ELSE effort_events.model END,
                effort = CASE WHEN effort_events.effort = 'unknown' THEN excluded.effort ELSE effort_events.effort END,
                tokens = MAX(effort_events.tokens, excluded.tokens)
            WHERE effort_events.provider = excluded.provider;
            """
        try run(handle, sql) { statement in
            bind(statement, 1, record.id.lowercased())
            bind(statement, 2, record.provider.rawValue)
            sqlite3_bind_double(statement, 3, record.recordedAt.timeIntervalSince1970)
            bind(statement, 4, record.day)
            bind(statement, 5, record.model)
            bind(statement, 6, record.effort)
            sqlite3_bind_int64(statement, 7, Int64(record.tokens))
        }
    }

    private static func writeQuota(_ handle: OpaquePointer, snapshot: ProviderUsageSnapshot) throws {
        guard let capturedAt = snapshot.capturedAt else { return }
        let sampledAt = bucket(capturedAt)
        let sql = """
            INSERT INTO quota_samples
                (provider, window_id, sampled_at, display_name, duration_minutes, used_percentage, resets_at, verified, observed_at, continuity_started_at, continuity_reset_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?10, ?8, ?9, ?11)
            ON CONFLICT(provider, window_id, sampled_at) DO UPDATE SET
                display_name = excluded.display_name,
                duration_minutes = excluded.duration_minutes,
                used_percentage = excluded.used_percentage,
                resets_at = excluded.resets_at,
                verified = excluded.verified,
                observed_at = excluded.observed_at,
                continuity_started_at = excluded.continuity_started_at,
                continuity_reset_at = excluded.continuity_reset_at
            WHERE excluded.observed_at >= COALESCE(quota_samples.observed_at, quota_samples.sampled_at);
            """
        for window in snapshot.windows {
            let previous = try latestQuota(handle, provider: snapshot.provider, windowID: window.id)
            guard previous.map({ capturedAt > $0.sampledAt }) ?? true else { continue }
            let valid = window.usedPercentage.isFinite && (0...100).contains(window.usedPercentage)
            var continuityStartedAt = capturedAt
            var continuityResetAt = window.resetsAt
            if let previous, previous.isVerified, valid,
                previous.usedPercentage <= window.usedPercentage,
                HistoryAnalytics.sameReset(previous.continuityResetAt ?? previous.resetsAt, window.resetsAt),
                previous.durationMinutes == window.durationMinutes,
                capturedAt.timeIntervalSince(previous.sampledAt) <= 1800,
                let boundary = previous.continuityStartedAt
            {
                continuityStartedAt = boundary
                continuityResetAt = previous.continuityResetAt ?? previous.resetsAt
            }
            try run(handle, sql) { statement in
                bind(statement, 1, snapshot.provider.rawValue)
                bind(statement, 2, window.id)
                sqlite3_bind_int64(statement, 3, sampledAt)
                bind(statement, 4, window.displayName)
                bind(statement, 5, window.durationMinutes.map(Int64.init))
                sqlite3_bind_double(statement, 6, window.usedPercentage.isFinite ? window.usedPercentage : 0)
                if let reset = window.resetsAt {
                    sqlite3_bind_double(statement, 7, reset.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                sqlite3_bind_double(statement, 8, capturedAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 9, continuityStartedAt.timeIntervalSince1970)
                sqlite3_bind_int(statement, 10, valid ? 1 : 0)
                if let reset = continuityResetAt {
                    sqlite3_bind_double(statement, 11, reset.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(statement, 11)
                }
            }
            try archivePace(handle, snapshot: snapshot, window: window, previous: previous, now: capturedAt)
        }
    }

    private static func latestQuota(
        _ handle: OpaquePointer, provider: UsageProvider, windowID: String
    ) throws -> HistoryQuotaRow? {
        let sql = """
            SELECT COALESCE(observed_at, sampled_at), used_percentage, resets_at, duration_minutes,
                verified, continuity_started_at, continuity_reset_at
            FROM quota_samples WHERE provider = ?1 AND window_id = ?2 ORDER BY sampled_at DESC LIMIT 1;
            """
        var row: HistoryQuotaRow?
        try query(handle, sql) { statement in
            bind(statement, 1, provider.rawValue)
            bind(statement, 2, windowID)
        } each: { statement in
            row = HistoryQuotaRow(
                sampledAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), provider: provider,
                windowID: windowID, displayName: nil, usedPercentage: sqlite3_column_double(statement, 1),
                resetsAt: date(statement, 2),
                durationMinutes: sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil : Int(sqlite3_column_int64(statement, 3)),
                isVerified: sqlite3_column_int(statement, 4) == 1, continuityStartedAt: date(statement, 5),
                continuityResetAt: date(statement, 6))
        }
        return row
    }

    private static func writeTokens(_ handle: OpaquePointer, snapshot: ProviderUsageSnapshot, now: Date) throws {
        let sql = """
            INSERT INTO daily_tokens (day, provider, model, tokens, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(day, provider, model) DO UPDATE SET
                tokens = MAX(daily_tokens.tokens, excluded.tokens),
                updated_at = excluded.updated_at;
            """
        for row in tokenRows(for: snapshot) {
            try run(handle, sql) { statement in
                bind(statement, 1, row.day)
                bind(statement, 2, row.provider.rawValue)
                bind(statement, 3, row.model)
                sqlite3_bind_int64(statement, 4, Int64(row.tokens))
                sqlite3_bind_int64(statement, 5, Int64(now.timeIntervalSince1970))
            }
        }
    }

    static func tokenRows(for snapshot: ProviderUsageSnapshot) -> [HistoryTokenRow] {
        if snapshot.modelBuckets.isEmpty {
            return snapshot.dailyUsage
                .filter { $0.tokens >= 0 }
                .map { HistoryTokenRow(day: $0.day, provider: snapshot.provider, model: "all", tokens: $0.tokens) }
        }
        var totals: [String: [String: Int]] = [:]
        for item in snapshot.modelBuckets where item.tokens >= 0 {
            totals[item.day, default: [:]][item.model, default: 0] += item.tokens
        }
        return
            totals
            .flatMap { day, models in
                models.map { HistoryTokenRow(day: day, provider: snapshot.provider, model: $0.key, tokens: $0.value) }
            }
            .sorted { left, right in
                if left.day != right.day { return left.day < right.day }
                return left.model < right.model
            }
    }

    private static func prune(_ handle: OpaquePointer, now: Date) throws {
        let cutoff = Int64(now.addingTimeInterval(-Double(quotaRetentionDays) * 86_400).timeIntervalSince1970)
        try run(handle, "DELETE FROM quota_samples WHERE sampled_at < ?1;") { statement in
            sqlite3_bind_int64(statement, 1, cutoff)
        }
    }
}

extension UsageHistoryStore {
    private static var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(Int(-1), to: sqlite3_destructor_type.self)
    }

    private static func open(_ url: URL) throws -> OpaquePointer {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? url.path
            if let handle { sqlite3_close(handle) }
            throw UsageHistoryError.openFailed(message)
        }
        sqlite3_busy_timeout(handle, 3_000)
        chmod(url.path, S_IRUSR | S_IWUSR)
        return handle
    }

    private static func exec(_ handle: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? sql
            sqlite3_free(error)
            throw UsageHistoryError.statementFailed(message)
        }
    }

    private static func run(
        _ handle: OpaquePointer,
        _ sql: String,
        bindings: (OpaquePointer) -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw UsageHistoryError.statementFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageHistoryError.statementFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private static func query(
        _ handle: OpaquePointer,
        _ sql: String,
        bindings: (OpaquePointer) -> Void,
        each: (OpaquePointer) -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw UsageHistoryError.statementFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: each(statement)
            case SQLITE_DONE: return
            default: throw UsageHistoryError.statementFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, transientDestructor)
    }

    private static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Int64?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int64(statement, index, value)
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        optionalText(statement, index) ?? ""
    }

    private static func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: raw)
    }

    private static func date(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }
}
