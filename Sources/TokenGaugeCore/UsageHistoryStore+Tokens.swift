import Foundation

extension UsageHistoryStore {
    static func readTokenRows(
        _ connection: SQLiteConnection, since day: String?, through lastDay: String?
    ) throws -> [HistoryTokenRow] {
        let sql = """
            SELECT day, provider, model, tokens FROM daily_tokens
            WHERE day >= ?1 AND day <= ?2
            ORDER BY day, provider, model;
            """
        var rows: [HistoryTokenRow] = []
        try connection.query(sql) { statement in
            statement.bind(1, day ?? "0000-01-01")
            statement.bind(2, lastDay ?? "9999-12-31")
        } each: { statement in
            guard let provider = UsageProvider(rawValue: statement.text(1)) else { return }
            rows.append(
                HistoryTokenRow(
                    day: statement.text(0),
                    provider: provider,
                    model: statement.text(2),
                    tokens: statement.int(3)
                )
            )
        }
        return rows
    }

    static func readUsageDays(_ connection: SQLiteConnection, provider: UsageProvider?) throws -> Set<String> {
        let sql = """
            SELECT day FROM daily_totals
            WHERE tokens > 0 AND (?1 IS NULL OR provider = ?1);
            """
        var days: Set<String> = []
        try connection.query(sql) { statement in
            statement.bind(1, provider?.rawValue)
        } each: { statement in
            days.insert(statement.text(0))
        }
        return days
    }

    static func readBounds(_ connection: SQLiteConnection) throws -> HistoryBounds {
        var result = HistoryBounds(firstDay: nil, lastDay: nil)
        let sql = """
            SELECT (SELECT MIN(day) FROM daily_tokens), (SELECT MAX(day) FROM daily_tokens),
                (SELECT MIN(day) FROM effort_events), (SELECT MAX(day) FROM effort_events);
            """
        try connection.query(sql, bindings: { _ in }) { statement in
            let firstDays = [statement.optionalText(0), statement.optionalText(2)].compactMap { $0 }
            let lastDays = [statement.optionalText(1), statement.optionalText(3)].compactMap { $0 }
            result = HistoryBounds(firstDay: firstDays.min(), lastDay: lastDays.max())
        }
        return result
    }

    static func writeTokens(_ connection: SQLiteConnection, snapshot: ProviderUsageSnapshot, now: Date) throws {
        let sql = """
            INSERT INTO daily_tokens (day, provider, model, tokens, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(day, provider, model) DO UPDATE SET
                tokens = MAX(daily_tokens.tokens, excluded.tokens),
                updated_at = excluded.updated_at;
            """
        for row in tokenRows(for: snapshot) {
            try connection.run(sql) { statement in
                statement.bind(1, row.day)
                statement.bind(2, row.provider.rawValue)
                statement.bind(3, row.model)
                statement.bind(4, Int64(row.tokens))
                statement.bind(5, Int64(now.timeIntervalSince1970))
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
}
