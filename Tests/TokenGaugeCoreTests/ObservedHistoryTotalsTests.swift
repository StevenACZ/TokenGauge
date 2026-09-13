import Foundation
import SQLite3
import XCTest

@testable import TokenGaugeCore

final class ObservedHistoryTotalsTests: XCTestCase {
    private var root: URL!
    private var database: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        database = root.appending(path: "history.sqlite")
        _ = try UsageHistoryStore.bounds(at: database)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDailyTotalsUseMaximumObservedSourceWithoutOverlappingModels() throws {
        try sql(
            """
            INSERT INTO daily_tokens VALUES
                ('2026-09-07','codex','all',100,0),
                ('2026-09-07','codex','model-a',80,0),
                ('2026-09-07','codex','model-b',70,0),
                ('2026-09-08','codex','all',300,0),
                ('2026-09-08','codex','model-a',20,0);
            INSERT INTO effort_events VALUES
                ('a','codex',1,'2026-09-07','model-a','high',100),
                ('b','codex',1,'2026-09-07','model-b','high',100),
                ('c','codex',1,'2026-09-08','model-a','high',250);
            """)
        XCTAssertEqual(
            try query("SELECT day, tokens FROM daily_totals ORDER BY day"),
            [
                ["2026-09-07", "200"], ["2026-09-08", "300"],
            ])
        try sql("DELETE FROM effort_events WHERE day = '2026-09-07';")
        XCTAssertEqual(try query("SELECT tokens FROM daily_totals WHERE day = '2026-09-07'"), [["150"]])
    }

    func testEffortOnlyAndExplicitZeroDaysRemainPresentWhileMissingDaysStayAbsent() throws {
        try sql(
            """
            INSERT INTO effort_events VALUES
                ('a','claude',1,'2026-09-07','fable','high',40),
                ('b','claude',1,'2026-09-08','fable','high',0);
            INSERT INTO daily_tokens VALUES ('2026-09-10','claude','all',0,0);
            """)
        XCTAssertEqual(
            try query("SELECT day, tokens FROM daily_totals ORDER BY day"),
            [
                ["2026-09-07", "40"], ["2026-09-08", "0"], ["2026-09-10", "0"],
            ])
    }

    func testWeeklyAndMonthlyViewsSumTheSameObservedDailyTotals() throws {
        try sql(
            """
            INSERT INTO daily_tokens VALUES
                ('2026-08-31','codex','all',10,0), ('2026-09-01','codex','all',20,0),
                ('2026-09-07','codex','all',30,0);
            INSERT INTO effort_events VALUES
                ('a','codex',1,'2026-09-01','gpt','high',25),
                ('b','claude',1,'2026-09-01','fable','high',40);
            """)
        XCTAssertEqual(
            try query("SELECT week_start, provider, tokens FROM weekly_totals ORDER BY week_start, provider"),
            [
                ["2026-08-31", "claude", "40"], ["2026-08-31", "codex", "35"],
                ["2026-09-07", "codex", "30"],
            ])
        XCTAssertEqual(
            try query("SELECT month, provider, tokens FROM monthly_totals ORDER BY month, provider"),
            [
                ["2026-08", "codex", "10"], ["2026-09", "claude", "40"], ["2026-09", "codex", "55"],
            ])
    }

    func testVersionedMigrationPreservesRowsAndRunsOnlyOnce() throws {
        try sql(
            """
            INSERT INTO daily_tokens VALUES ('2026-09-07','codex','all',100,0);
            INSERT INTO effort_events VALUES ('a','codex',1,'2026-09-07','gpt','high',150);
            DROP VIEW monthly_totals;
            DROP VIEW weekly_totals;
            DROP VIEW daily_totals;
            CREATE VIEW daily_totals AS SELECT day, provider, SUM(tokens) AS tokens FROM daily_tokens GROUP BY day, provider;
            PRAGMA user_version = 0;
            """)
        let before = try query("SELECT * FROM daily_tokens")
        let eventsBefore = try query("SELECT * FROM effort_events")
        _ = try UsageHistoryStore.bounds(at: database)
        XCTAssertEqual(try query("PRAGMA user_version"), [["1"]])
        XCTAssertEqual(try query("SELECT tokens FROM daily_totals"), [["150"]])
        XCTAssertEqual(try query("SELECT * FROM daily_tokens"), before)
        XCTAssertEqual(try query("SELECT * FROM effort_events"), eventsBefore)
        let schemaVersion = try query("PRAGMA schema_version")
        _ = try UsageHistoryStore.bounds(at: database)
        XCTAssertEqual(try query("PRAGMA schema_version"), schemaVersion)
    }

    private func sql(_ sql: String) throws {
        try withDatabase { handle in
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func query(_ sql: String) throws -> [[String]] {
        try withDatabase { handle in
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &statement, nil), SQLITE_OK)
            let query = try XCTUnwrap(statement)
            defer { sqlite3_finalize(query) }
            var rows: [[String]] = []
            while sqlite3_step(query) == SQLITE_ROW {
                rows.append(
                    (0..<sqlite3_column_count(query)).map {
                        sqlite3_column_text(query, $0).map { String(cString: $0) } ?? "NULL"
                    })
            }
            return rows
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
        let db = try XCTUnwrap(handle)
        defer { sqlite3_close(db) }
        return try body(db)
    }
}
