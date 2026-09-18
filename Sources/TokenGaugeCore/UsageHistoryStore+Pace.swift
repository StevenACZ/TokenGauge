import Foundation

extension UsageHistoryStore {
    static func readPaceRows(
        _ connection: SQLiteConnection, provider: UsageProvider?, windowID: String?, since: Date?, until: Date?,
        accountFingerprint: String?
    ) throws -> [HistoryPaceRow] {
        try readPaces(
            connection,
            suffix: """
                WHERE sampled_at >= ?1 AND sampled_at <= ?2
                    AND (?3 IS NULL OR provider = ?3) AND (?4 IS NULL OR window_id = ?4)
                    AND account_fingerprint IS ?5
                ORDER BY sampled_at, provider, window_id
                """
        ) { statement in
            statement.bind(1, since?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude)
            statement.bind(2, until?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude)
            statement.bind(3, provider?.rawValue)
            statement.bind(4, windowID)
            statement.bind(5, accountFingerprint)
        }
    }

    static func readRecentPaces(
        _ connection: SQLiteConnection, key: HistoryPaceKey, activeOnly: Bool, limit: Int, before: Date?,
        accountFingerprint: String? = nil
    ) throws -> [HistoryPaceRow] {
        let active = activeOnly ? "AND is_active = 1" : ""
        return try readPaces(
            connection,
            suffix: """
                WHERE provider = ?1 AND window_id = ?2 AND sampled_at < ?3 \(active)
                    AND account_fingerprint IS ?5
                ORDER BY sampled_at DESC LIMIT ?4
                """
        ) { statement in
            statement.bind(1, key.provider.rawValue)
            statement.bind(2, key.windowID)
            statement.bind(3, before?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude)
            statement.bind(4, Int64(limit))
            statement.bind(5, accountFingerprint)
        }
    }

    private static func readPaces(
        _ connection: SQLiteConnection, suffix: String, bindings: (SQLiteStatement) -> Void
    ) throws -> [HistoryPaceRow] {
        var rows: [HistoryPaceRow] = []
        try connection.query(
            """
            SELECT provider, window_id, sampled_at, display_name, points_per_hour, observed_minutes,
                resets_at, last_used_percentage, is_active FROM pace_samples
            \(suffix);
            """, bindings: bindings
        ) { statement in
            guard let provider = UsageProvider(rawValue: statement.text(0)) else { return }
            rows.append(
                HistoryPaceRow(
                    key: HistoryPaceKey(provider: provider, windowID: statement.text(1)),
                    displayName: statement.optionalText(3),
                    pace: QuotaPace(
                        pointsPerHour: statement.double(4),
                        observedMinutes: statement.double(5),
                        sampledAt: statement.instant(2),
                        resetsAt: statement.date(6), lastUsedPercentage: statement.double(7)),
                    isActive: statement.flag(8)))
        }
        return rows
    }

    static func archivePace(
        _ connection: SQLiteConnection, snapshot: ProviderUsageSnapshot, window: QuotaWindow,
        previous: HistoryQuotaRow?, rows: [HistoryQuotaRow], now: Date, accountFingerprint: String?
    ) throws {
        guard window.durationMinutes == 10_080 else { return }
        guard let pace = HistoryAnalytics.pace(rows: rows, provider: snapshot.provider, windowID: window.id, now: now)
        else { return }
        let key = HistoryPaceKey(provider: snapshot.provider, windowID: window.id)
        let increased =
            previous.map {
                $0.isVerified && $0.durationMinutes == window.durationMinutes
                    && HistoryAnalytics.sameReset($0.resetsAt, window.resetsAt)
                    && window.usedPercentage > $0.usedPercentage
            } ?? false
        let activeHistory = try readRecentPaces(
            connection, key: key, activeOnly: true, limit: 1, before: nil, accountFingerprint: accountFingerprint)
        let seed = pace.pointsPerHour > 0 && activeHistory.isEmpty
        try connection.run(
            """
            INSERT OR IGNORE INTO pace_samples
                (provider, window_id, sampled_at, display_name, points_per_hour, observed_minutes,
                    resets_at, last_used_percentage, is_active, account_fingerprint)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10);
            """
        ) { statement in
            statement.bind(1, snapshot.provider.rawValue)
            statement.bind(2, window.id)
            statement.bind(3, pace.sampledAt.timeIntervalSince1970)
            statement.bind(4, window.displayName)
            statement.bind(5, pace.pointsPerHour)
            statement.bind(6, pace.observedMinutes)
            statement.bind(7, pace.resetsAt)
            statement.bind(8, window.usedPercentage)
            statement.bind(9, increased || seed)
            statement.bind(10, accountFingerprint)
        }
    }
}
