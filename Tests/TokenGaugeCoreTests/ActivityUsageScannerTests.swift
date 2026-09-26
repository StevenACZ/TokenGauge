import Foundation
import SQLite3
import XCTest

@testable import TokenGaugeCore

final class ActivityUsageScannerTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-12T18:00:00Z")!

    func testClaudeSkillToolUseCountsButSkillTextDoesNot() throws {
        try withHome { home in
            try write(
                home, ".claude/projects/project/a.jsonl",
                [
                    claudeSkill("m1", tool: "t1", skill: "memory-closeout"),
                    claudeSkill("m1", tool: "t1", skill: "memory-closeout"),
                    claudeSkill("m2", tool: "t2", skill: "anthropic-skills:pdf"),
                    claudeSkill("m3", tool: "t3", skill: "Bad Name"),
                    #"""
                    {"type":"assistant","timestamp":"2026-09-12T12:00:00.000Z","message":{"id":"m4","content":[{"type":"text","text":"call {\"type\":\"tool_use\",\"name\":\"Skill\",\"input\":{\"skill\":\"leak\"}}"}]}}
                    """#,
                    #"""
                    {"type":"user","timestamp":"2026-09-12T12:00:00.000Z","message":{"id":"m5","content":[{"type":"tool_use","id":"t5","name":"Skill","input":{"skill":"user-text"}}]}}
                    """#,
                ])
            let records = try scan(home).activityRecords
            XCTAssertEqual(records.map(\.key).sorted(), ["anthropic-skills:pdf", "memory-closeout"])
            XCTAssertTrue(records.allSatisfy { $0.kind == .skill && $0.value == 1 && $0.id.count == 64 })
        }
    }

    func testCodexSkillReadCountsOncePerRolloutAndIgnoresSearchesAndEdits() throws {
        try withHome { home in
            let read = codexCall(
                #"text(await tools.exec_command({cmd:\"cat /u/.agents/skills/memory-closeout/SKILL.md\"}))"#)
            try write(
                home, ".codex/sessions/2026/09/12/rollout-a.jsonl",
                [
                    sessionMeta(#""cli""#), read, read,
                    codexCall(#"tools.exec_command({cmd:\"sed -n '1,80p' /u/skills/memory-closeout/SKILL.md\"})"#),
                    codexCall(#"tools.exec_command({cmd:\"rg -n 'a|b' /u/skills/search-only/SKILL.md\"})"#),
                    codexCall(#"tools.exec_command({cmd:\"rg skills/grep-only/SKILL.md\"})"#),
                    codexCall(
                        #"*** Begin Patch\n*** Update File: /u/skills/patched/SKILL.md\n@@\n-a\n+b\n*** End Patch"#,
                        name: "apply_patch"),
                    codexCall(#"tools.exec_command({cmd:\"apply_patch skills/patched-cmd/SKILL.md\"})"#),
                    #"""
                    {"type":"response_item","timestamp":"2026-09-12T12:00:00Z","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"cd /u && head -n 5 skills/agent-delegation/SKILL.md\"}"}}
                    """#,
                ])
            try write(home, ".codex/sessions/2026/09/12/rollout-b.jsonl", [sessionMeta(#""cli""#), read])
            let records = try scan(home).activityRecords
            XCTAssertEqual(
                records.map(\.key).sorted(), ["agent-delegation", "memory-closeout", "memory-closeout"])
            XCTAssertEqual(Set(records.map(\.id)).count, 3)
        }
    }

    func testSubagentAndSidechainTurnsAreSkipped() throws {
        try withHome { home in
            try write(
                home, ".claude/projects/project/a.jsonl",
                [claudeTurn("u1", duration: 5000), claudeTurn("u2", duration: 9000, sidechain: true)])
            try write(
                home, ".claude/projects/project/session/subagents/agent.jsonl", [claudeTurn("u3", duration: 7000)])
            try write(
                home, ".codex/sessions/2026/09/12/rollout-main.jsonl",
                [sessionMeta(#""vscode""#), codexTurn("turn-main", duration: 3000)])
            try write(
                home, ".codex/sessions/2026/09/12/rollout-child.jsonl",
                [sessionMeta(#"{"subagent":{"thread_spawn":{}}}"#), codexTurn("turn-child", duration: 4000)])
            try write(
                home, ".codex/sessions/2026/09/12/rollout-legacy.jsonl",
                [sessionMeta(#""subagent""#), codexTurn("turn-legacy", duration: 4000)])
            let records = try scan(home).activityRecords
            XCTAssertEqual(records.map(\.value).sorted(), [3000, 5000])
            XCTAssertTrue(records.allSatisfy { $0.kind == .turn && $0.key.isEmpty })
        }
    }

    func testRepeatedScansKeepActivityAndEffortTotalsIdentical() throws {
        try withHome { home in
            let state = home.appending(path: "support/scan-state.json")
            let database = home.appending(path: "support/history.sqlite")
            try write(
                home, ".claude/projects/project/a.jsonl",
                [
                    claudeSkill("m1", tool: "t1", skill: "memory-closeout"), claudeTurn("u1", duration: 5000),
                    claudeUsage("m2", cached: 30),
                ])
            try write(
                home, ".codex/sessions/2026/09/12/rollout-a.jsonl",
                [
                    sessionMeta(#""cli""#), codexCall(#"tools.exec_command({cmd:\"cat skills/x/SKILL.md\"})"#),
                    codexTurn("turn-a", duration: 3000), codexUsage("r1", total: 100, cached: 60),
                ])
            let first = try scan(home, state: state)
            try UsageHistoryStore.recordEffort(first.effortRecords, activity: first.activityRecords, at: database)
            let activity = try UsageHistoryStore.activityRows(at: database)
            let effort = try UsageHistoryStore.effortRows(at: database)
            let cached = try UsageHistoryStore.cachedTokenRows(at: database)
            let second = try scan(home, state: state)
            XCTAssertEqual(second.bytesRead, 0)
            try UsageHistoryStore.recordEffort(second.effortRecords, activity: second.activityRecords, at: database)
            let full = try scan(home)
            try UsageHistoryStore.recordEffort(full.effortRecords, activity: full.activityRecords, at: database)
            XCTAssertEqual(activity.count, 4)
            XCTAssertEqual(try UsageHistoryStore.activityRows(at: database), activity)
            XCTAssertEqual(try UsageHistoryStore.effortRows(at: database), effort)
            XCTAssertEqual(try UsageHistoryStore.cachedTokenRows(at: database), cached)
            XCTAssertEqual(
                cached.map { [$0.cachedTokens, $0.tokens] }, [[30, 90], [60, 100]])
        }
    }

    func testCachedTokensKeepMaximumAndIgnoreUnknownRows() throws {
        try withHome { home in
            let database = home.appending(path: "history.sqlite")
            try UsageHistoryStore.recordEffort([effort("a", tokens: 50, cached: 20)], at: database)
            try UsageHistoryStore.recordEffort([effort("a", tokens: 40, cached: 10)], at: database)
            try UsageHistoryStore.recordEffort([effort("a", tokens: 40, cached: nil)], at: database)
            try UsageHistoryStore.recordEffort([effort("b", tokens: 70, cached: nil)], at: database)
            XCTAssertEqual(
                try UsageHistoryStore.cachedTokenRows(at: database),
                [HistoryCachedRow(day: "2026-09-12", provider: .codex, cachedTokens: 20, tokens: 50)])
            try UsageHistoryStore.recordEffort([effort("b", tokens: 70, cached: 35)], at: database)
            XCTAssertEqual(try UsageHistoryStore.cachedTokenRows(at: database).first?.cachedTokens, 55)
        }
    }

    func testActivityAggregatesAndRejectsInvalidRecords() throws {
        try withHome { home in
            let database = home.appending(path: "history.sqlite")
            try UsageHistoryStore.recordEffort(
                [],
                activity: [
                    activity("a", kind: .turn, key: "", value: 1000),
                    activity("b", kind: .turn, key: "", value: 4000),
                    activity("b", kind: .turn, key: "", value: 3000),
                    activity("c", kind: .skill, key: "memory-closeout", value: 1),
                    activity("d", kind: .skill, key: "/private/path", value: 1),
                    activity("e", kind: .turn, key: "text", value: 1),
                    activity("f", kind: .turn, key: "", value: -1),
                ], at: database)
            XCTAssertEqual(
                try UsageHistoryStore.activityRows(since: "2026-09-12", through: "2026-09-12", at: database),
                [
                    HistoryActivityRow(
                        day: "2026-09-12", provider: .claude, kind: .skill, key: "memory-closeout", count: 1, total: 1,
                        maximum: 1),
                    HistoryActivityRow(
                        day: "2026-09-12", provider: .claude, kind: .turn, key: "", count: 2, total: 5000,
                        maximum: 4000),
                ])
            XCTAssertTrue(try UsageHistoryStore.activityRows(since: "2026-09-13", at: database).isEmpty)
        }
    }

    func testOldSchemaDatabaseMigratesWithoutLosingEffortRows() throws {
        try withHome { home in
            let database = home.appending(path: "history.sqlite")
            var handle: OpaquePointer?
            XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
            let legacy = """
                CREATE TABLE effort_events (
                    id TEXT NOT NULL PRIMARY KEY, provider TEXT NOT NULL, occurred_at REAL NOT NULL,
                    day TEXT NOT NULL, model TEXT NOT NULL, effort TEXT NOT NULL, tokens INTEGER NOT NULL
                ) WITHOUT ROWID;
                INSERT INTO effort_events VALUES ('\(String(repeating: "a", count: 64))', 'codex', 100,
                    '2026-09-12', 'gpt-6', 'high', 40);
                PRAGMA user_version = 1;
                """
            XCTAssertEqual(sqlite3_exec(handle, legacy, nil, nil, nil), SQLITE_OK)
            sqlite3_close(handle)

            XCTAssertTrue(try UsageHistoryStore.cachedTokenRows(at: database).isEmpty)
            XCTAssertTrue(try UsageHistoryStore.activityRows(at: database).isEmpty)
            try UsageHistoryStore.recordEffort(
                [effort("a", tokens: 50, cached: 25)], activity: [activity("b", kind: .turn, key: "", value: 10)],
                at: database)
            XCTAssertEqual(try UsageHistoryStore.effortRows(at: database).map(\.tokens), [50])
            XCTAssertEqual(try UsageHistoryStore.cachedTokenRows(at: database).first?.cachedTokens, 25)
            XCTAssertEqual(try UsageHistoryStore.activityRows(at: database).first?.total, 10)
        }
    }

    private func scan(_ home: URL, state: URL? = nil) throws -> TranscriptScanner.Result {
        try TranscriptScanner.scan(homeDirectory: home, stateURL: state, now: now)
    }

    private func withHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private func write(_ home: URL, _ path: String, _ lines: [String]) throws {
        let file = home.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }

    private func claudeSkill(_ message: String, tool: String, skill: String) -> String {
        """
        {"type":"assistant","timestamp":"2026-09-12T12:00:00.000Z","message":{"id":"\(message)","content":[{"type":"text","text":"synthetic"},{"type":"tool_use","id":"\(tool)","name":"Skill","input":{"skill":"\(skill)","args":"synthetic"}}]}}
        """
    }

    private func claudeTurn(_ uuid: String, duration: Int, sidechain: Bool = false) -> String {
        """
        {"type":"system","subtype":"turn_duration","timestamp":"2026-09-12T12:00:00.000Z","uuid":"\(uuid)","isSidechain":\(sidechain),"durationMs":\(duration)}
        """
    }

    private func claudeUsage(_ id: String, cached: Int) -> String {
        """
        {"type":"assistant","timestamp":"2026-09-12T12:00:00.000Z","message":{"id":"\(id)","model":"claude-fable-5-1","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":\(cached),"output_tokens":30}}}
        """
    }

    private func sessionMeta(_ source: String) -> String {
        """
        {"type":"session_meta","timestamp":"2026-09-12T11:59:00Z","payload":{"id":"session","source":\(source)}}
        """
    }

    private func codexCall(_ input: String, name: String = "exec") -> String {
        """
        {"type":"response_item","timestamp":"2026-09-12T12:00:00Z","payload":{"type":"custom_tool_call","name":"\(name)","input":"\(input)"}}
        """
    }

    private func codexTurn(_ turn: String, duration: Int) -> String {
        """
        {"type":"event_msg","timestamp":"2026-09-12T12:10:00Z","payload":{"type":"task_complete","turn_id":"\(turn)","duration_ms":\(duration),"last_agent_message":"synthetic"}}
        """
    }

    private func codexUsage(_ id: String, total: Int, cached: Int) -> String {
        """
        {"type":"token_usage_record","timestamp":"2026-09-12T12:05:00Z","payload":{"turn_id":"turn-a","response_id":"\(id)","usage":{"total_tokens":\(total),"cached_input_tokens":\(cached)}}}
        """
    }

    private func effort(_ character: String, tokens: Int, cached: Int?) -> EffortUsageRecord {
        EffortUsageRecord(
            id: String(repeating: character, count: 64), provider: .codex, recordedAt: Date(timeIntervalSince1970: 100),
            day: "2026-09-12", model: "gpt-6", effort: "high", tokens: tokens, cachedTokens: cached)
    }

    private func activity(_ character: String, kind: HistoryActivityKind, key: String, value: Int)
        -> ActivityUsageRecord
    {
        ActivityUsageRecord(
            id: String(repeating: character, count: 64), provider: .claude,
            recordedAt: Date(timeIntervalSince1970: 1_789_214_400), day: "2026-09-12", kind: kind, key: key,
            value: value)
    }
}
