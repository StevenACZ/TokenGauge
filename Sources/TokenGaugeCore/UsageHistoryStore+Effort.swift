import Foundation

extension UsageHistoryStore {
    static func readEffortRows(
        _ connection: SQLiteConnection, since day: String?, through lastDay: String?
    ) throws -> [HistoryEffortRow] {
        let sql = """
            SELECT day, provider, model, effort, SUM(tokens) FROM effort_events
            WHERE day >= ?1 AND day <= ?2
            GROUP BY day, provider, model, effort ORDER BY day, provider, model, effort;
            """
        var rows: [HistoryEffortRow] = []
        try connection.query(sql) { statement in
            statement.bind(1, day ?? "0000-01-01")
            statement.bind(2, lastDay ?? "9999-12-31")
        } each: { statement in
            guard let provider = UsageProvider(rawValue: statement.text(1)) else { return }
            rows.append(
                HistoryEffortRow(
                    day: statement.text(0), provider: provider, model: statement.text(2), effort: statement.text(3),
                    tokens: statement.int(4)))
        }
        return rows
    }

    static func writeEffort(_ connection: SQLiteConnection, record: EffortUsageRecord) throws {
        let sql = """
            INSERT INTO effort_events (id, provider, occurred_at, day, model, effort, tokens, cached_tokens)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(id) DO UPDATE SET
                day = CASE WHEN excluded.occurred_at < effort_events.occurred_at THEN excluded.day ELSE effort_events.day END,
                occurred_at = MIN(effort_events.occurred_at, excluded.occurred_at),
                model = CASE WHEN effort_events.model = 'unknown' THEN excluded.model ELSE effort_events.model END,
                effort = CASE WHEN effort_events.effort = 'unknown' THEN excluded.effort ELSE effort_events.effort END,
                tokens = MAX(effort_events.tokens, excluded.tokens),
                cached_tokens = MAX(
                    COALESCE(effort_events.cached_tokens, excluded.cached_tokens),
                    COALESCE(excluded.cached_tokens, effort_events.cached_tokens))
            WHERE effort_events.provider = excluded.provider;
            """
        try connection.run(sql) { statement in
            statement.bind(1, record.id.lowercased())
            statement.bind(2, record.provider.rawValue)
            statement.bind(3, record.recordedAt.timeIntervalSince1970)
            statement.bind(4, record.day)
            statement.bind(5, record.model)
            statement.bind(6, record.effort)
            statement.bind(7, Int64(record.tokens))
            statement.bind(8, record.cachedTokens.map(Int64.init))
        }
    }

    static func writeActivity(_ connection: SQLiteConnection, record: ActivityUsageRecord) throws {
        let sql = """
            INSERT INTO activity_events (id, provider, occurred_at, day, kind, key, value)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            ON CONFLICT(id) DO UPDATE SET
                day = CASE WHEN excluded.occurred_at < activity_events.occurred_at THEN excluded.day ELSE activity_events.day END,
                occurred_at = MIN(activity_events.occurred_at, excluded.occurred_at),
                value = MAX(activity_events.value, excluded.value)
            WHERE activity_events.provider = excluded.provider AND activity_events.kind = excluded.kind;
            """
        try connection.run(sql) { statement in
            statement.bind(1, record.id.lowercased())
            statement.bind(2, record.provider.rawValue)
            statement.bind(3, record.recordedAt.timeIntervalSince1970)
            statement.bind(4, record.day)
            statement.bind(5, record.kind.rawValue)
            statement.bind(6, record.key)
            statement.bind(7, Int64(record.value))
        }
    }

    static func readActivityRows(
        _ connection: SQLiteConnection, since day: String?, through lastDay: String?
    ) throws -> [HistoryActivityRow] {
        let sql = """
            SELECT day, provider, kind, key, COUNT(*), SUM(value), MAX(value) FROM activity_events
            WHERE day >= ?1 AND day <= ?2
            GROUP BY day, provider, kind, key ORDER BY day, provider, kind, key;
            """
        var rows: [HistoryActivityRow] = []
        try connection.query(sql) { statement in
            statement.bind(1, day ?? "0000-01-01")
            statement.bind(2, lastDay ?? "9999-12-31")
        } each: { statement in
            guard let provider = UsageProvider(rawValue: statement.text(1)),
                let kind = HistoryActivityKind(rawValue: statement.text(2))
            else { return }
            rows.append(
                HistoryActivityRow(
                    day: statement.text(0), provider: provider, kind: kind, key: statement.text(3),
                    count: statement.int(4), total: statement.int(5), maximum: statement.int(6)))
        }
        return rows
    }

    static func readCachedRows(
        _ connection: SQLiteConnection, since day: String?, through lastDay: String?
    ) throws -> [HistoryCachedRow] {
        let sql = """
            SELECT day, provider, SUM(cached_tokens), SUM(tokens) FROM effort_events
            WHERE cached_tokens IS NOT NULL AND day >= ?1 AND day <= ?2
            GROUP BY day, provider ORDER BY day, provider;
            """
        var rows: [HistoryCachedRow] = []
        try connection.query(sql) { statement in
            statement.bind(1, day ?? "0000-01-01")
            statement.bind(2, lastDay ?? "9999-12-31")
        } each: { statement in
            guard let provider = UsageProvider(rawValue: statement.text(1)) else { return }
            rows.append(
                HistoryCachedRow(
                    day: statement.text(0), provider: provider, cachedTokens: statement.int(2),
                    tokens: statement.int(3)))
        }
        return rows
    }
}
