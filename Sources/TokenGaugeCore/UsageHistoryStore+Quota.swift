import Foundation

extension UsageHistoryStore {
    static func readQuotaRows(
        _ connection: SQLiteConnection, provider: UsageProvider? = nil, since: Date? = nil, until: Date? = nil
    ) throws -> [HistoryQuotaRow] {
        let sql = """
            SELECT COALESCE(observed_at, sampled_at), provider, window_id, display_name, used_percentage, resets_at,
                duration_minutes, verified, continuity_started_at, continuity_reset_at, account_fingerprint
            FROM quota_samples
            WHERE sampled_at >= ?2 AND sampled_at <= ?3 AND (?1 IS NULL OR provider = ?1)
                AND COALESCE(observed_at, sampled_at) >= ?4 AND COALESCE(observed_at, sampled_at) <= ?5
            ORDER BY sampled_at, provider, window_id;
            """
        var rows: [HistoryQuotaRow] = []
        try connection.query(sql) { statement in
            statement.bind(1, provider?.rawValue)
            statement.bind(2, since.map { bucket($0) } ?? Int64.min)
            statement.bind(3, until.map { bucket($0) } ?? Int64.max)
            statement.bind(4, since?.timeIntervalSince1970 ?? -Double.greatestFiniteMagnitude)
            statement.bind(5, until?.timeIntervalSince1970 ?? Double.greatestFiniteMagnitude)
        } each: { statement in
            guard let provider = UsageProvider(rawValue: statement.text(1)) else { return }
            rows.append(
                HistoryQuotaRow(
                    sampledAt: statement.instant(0),
                    provider: provider,
                    windowID: statement.text(2),
                    displayName: statement.optionalText(3),
                    usedPercentage: statement.double(4),
                    resetsAt: statement.date(5),
                    durationMinutes: statement.optionalInt(6),
                    isVerified: statement.flag(7),
                    continuityStartedAt: statement.date(8), continuityResetAt: statement.date(9),
                    accountFingerprint: statement.optionalText(10)
                )
            )
        }
        return rows
    }

    static func writeQuota(
        _ connection: SQLiteConnection, snapshot: ProviderUsageSnapshot, accountFingerprint: String?
    ) throws {
        guard let capturedAt = snapshot.capturedAt else { return }
        let sampledAt = bucket(capturedAt)
        let sql = """
            INSERT INTO quota_samples
                (provider, window_id, sampled_at, display_name, duration_minutes, used_percentage, resets_at, verified, observed_at, continuity_started_at, continuity_reset_at, account_fingerprint)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?10, ?8, ?9, ?11, ?12)
            ON CONFLICT(provider, window_id, sampled_at) DO UPDATE SET
                display_name = excluded.display_name,
                duration_minutes = excluded.duration_minutes,
                used_percentage = excluded.used_percentage,
                resets_at = excluded.resets_at,
                verified = excluded.verified,
                observed_at = excluded.observed_at,
                continuity_started_at = excluded.continuity_started_at,
                continuity_reset_at = excluded.continuity_reset_at,
                account_fingerprint = excluded.account_fingerprint
            WHERE excluded.observed_at >= COALESCE(quota_samples.observed_at, quota_samples.sampled_at);
            """
        var archived: [(window: QuotaWindow, previous: HistoryQuotaRow?)] = []
        for window in snapshot.windows {
            let previous = try latestQuota(connection, provider: snapshot.provider, windowID: window.id)
            guard previous.map({ capturedAt > $0.sampledAt }) ?? true else { continue }
            let valid = window.usedPercentage.isFinite && (0...100).contains(window.usedPercentage)
            var continuityStartedAt = capturedAt
            var continuityResetAt = window.resetsAt
            if let previous, previous.isVerified, valid,
                previous.usedPercentage <= window.usedPercentage,
                previous.accountFingerprint == accountFingerprint,
                HistoryAnalytics.sameReset(previous.continuityResetAt ?? previous.resetsAt, window.resetsAt),
                previous.durationMinutes == window.durationMinutes,
                capturedAt.timeIntervalSince(previous.sampledAt) <= 1800,
                let boundary = previous.continuityStartedAt
            {
                continuityStartedAt = boundary
                continuityResetAt = previous.continuityResetAt ?? previous.resetsAt
            }
            try connection.run(sql) { statement in
                statement.bind(1, snapshot.provider.rawValue)
                statement.bind(2, window.id)
                statement.bind(3, sampledAt)
                statement.bind(4, window.displayName)
                statement.bind(5, window.durationMinutes.map(Int64.init))
                statement.bind(6, window.usedPercentage.isFinite ? window.usedPercentage : 0)
                statement.bind(7, window.resetsAt)
                statement.bind(8, capturedAt)
                statement.bind(9, continuityStartedAt)
                statement.bind(10, valid)
                statement.bind(11, continuityResetAt)
                statement.bind(12, accountFingerprint)
            }
            archived.append((window, previous))
        }
        guard archived.contains(where: { $0.window.durationMinutes == 10_080 }) else { return }
        let recent = try readQuotaRows(
            connection, provider: snapshot.provider, since: capturedAt.addingTimeInterval(-3600), until: capturedAt)
        for entry in archived {
            try archivePace(
                connection, snapshot: snapshot, window: entry.window, previous: entry.previous, rows: recent,
                now: capturedAt, accountFingerprint: accountFingerprint)
        }
    }

    static func latestQuota(
        _ connection: SQLiteConnection, provider: UsageProvider, windowID: String
    ) throws -> HistoryQuotaRow? {
        let sql = """
            SELECT COALESCE(observed_at, sampled_at), used_percentage, resets_at, duration_minutes,
                verified, continuity_started_at, continuity_reset_at, account_fingerprint
            FROM quota_samples WHERE provider = ?1 AND window_id = ?2 ORDER BY sampled_at DESC LIMIT 1;
            """
        var row: HistoryQuotaRow?
        try connection.query(sql) { statement in
            statement.bind(1, provider.rawValue)
            statement.bind(2, windowID)
        } each: { statement in
            row = HistoryQuotaRow(
                sampledAt: statement.instant(0), provider: provider,
                windowID: windowID, displayName: nil, usedPercentage: statement.double(1),
                resetsAt: statement.date(2),
                durationMinutes: statement.optionalInt(3),
                isVerified: statement.flag(4), continuityStartedAt: statement.date(5),
                continuityResetAt: statement.date(6), accountFingerprint: statement.optionalText(7))
        }
        return row
    }

    static func prune(_ connection: SQLiteConnection, now: Date) throws {
        let cutoff = Int64(now.addingTimeInterval(-Double(quotaRetentionDays) * 86_400).timeIntervalSince1970)
        try connection.run("DELETE FROM quota_samples WHERE sampled_at < ?1;") { statement in
            statement.bind(1, cutoff)
        }
    }
}
