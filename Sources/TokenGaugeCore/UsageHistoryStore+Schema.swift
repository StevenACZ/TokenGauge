import Foundation
import SQLite3

extension UsageHistoryStore {
    enum Schema {
        static let version: Int32 = 1

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
            CREATE TABLE IF NOT EXISTS activity_events (
                id TEXT NOT NULL PRIMARY KEY,
                provider TEXT NOT NULL,
                occurred_at REAL NOT NULL,
                day TEXT NOT NULL,
                kind TEXT NOT NULL,
                key TEXT NOT NULL,
                value INTEGER NOT NULL
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS activity_events_day_provider ON activity_events(day, provider);
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

    static func schemaVersion(_ connection: SQLiteConnection) throws -> Int32 {
        var version: Int32 = 0
        try connection.query("PRAGMA user_version;", bindings: { _ in }) { statement in
            version = sqlite3_column_int(statement.handle, 0)
        }
        return version
    }

    static func prepareSchema(_ connection: SQLiteConnection) throws {
        try connection.transaction {
            try connection.exec(Schema.statements)
            var columns = Set<String>()
            try connection.query("PRAGMA table_info(quota_samples);", bindings: { _ in }) { statement in
                columns.insert(statement.text(1))
            }
            if !columns.contains("verified") {
                try connection.exec("ALTER TABLE quota_samples ADD COLUMN verified INTEGER NOT NULL DEFAULT 0;")
            }
            if !columns.contains("observed_at") {
                try connection.exec("ALTER TABLE quota_samples ADD COLUMN observed_at REAL;")
            }
            if !columns.contains("continuity_started_at") {
                try connection.exec("ALTER TABLE quota_samples ADD COLUMN continuity_started_at REAL;")
            }
            if !columns.contains("continuity_reset_at") {
                try connection.exec("ALTER TABLE quota_samples ADD COLUMN continuity_reset_at REAL;")
            }
            if !columns.contains("account_fingerprint") {
                try connection.exec("ALTER TABLE quota_samples ADD COLUMN account_fingerprint TEXT;")
            }
            var paceColumns = Set<String>()
            try connection.query("PRAGMA table_info(pace_samples);", bindings: { _ in }) { statement in
                paceColumns.insert(statement.text(1))
            }
            if !paceColumns.contains("account_fingerprint") {
                try connection.exec("ALTER TABLE pace_samples ADD COLUMN account_fingerprint TEXT;")
            }
            var effortColumns = Set<String>()
            try connection.query("PRAGMA table_info(effort_events);", bindings: { _ in }) { statement in
                effortColumns.insert(statement.text(1))
            }
            if !effortColumns.contains("cached_tokens") {
                try connection.exec("ALTER TABLE effort_events ADD COLUMN cached_tokens INTEGER;")
            }
            if try schemaVersion(connection) < Schema.version {
                try connection.exec(Schema.observedTotalsViews)
                try connection.exec("PRAGMA user_version = \(Schema.version);")
            }
        }
    }
}
