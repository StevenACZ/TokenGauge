import Foundation
import XCTest

@testable import TokenGaugeCore

final class EffortUsageScannerTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-12T18:00:00Z")!

    func testDirectCodexUsageLinksEffortAndIgnoresCumulativeEvents() throws {
        try withHome { home in
            try write(
                home, ".codex/sessions/2026/09/12/a.jsonl",
                [
                    """
                    {"type":"turn_context","payload":{"turn_id":"turn-a","model":"gpt-6-astra","effort":"xhigh"}}
                    """,
                    codex("response-a", turn: "turn-a", tokens: "40"),
                    codex("response-a", turn: "turn-a", tokens: "40"),
                    """
                    {"type":"event_msg","timestamp":"2026-09-12T12:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":9999}}}}
                    """,
                    codex("response-b", turn: "absent", tokens: "20"),
                ])
            let result = try EffortUsageScanner.scan(homeDirectory: home, now: now)
            XCTAssertEqual(result.count, 2)
            XCTAssertEqual(result.reduce(0) { $0 + $1.tokens }, 60)
            XCTAssertEqual(
                result.first { $0.tokens == 40 }?.id, "36195e9ed643fc1d085e80ca409ecf4dba7b27d06820da13487844e97cbf09f7"
            )
            XCTAssertEqual(result.first { $0.tokens == 40 }?.effort, "xhigh")
            XCTAssertEqual(result.first { $0.tokens == 40 }?.model, "gpt-6-astra")
            XCTAssertEqual(result.first { $0.tokens == 20 }?.effort, "unknown")
            XCTAssertTrue(result.allSatisfy { $0.id.count == 64 && !$0.id.contains("response") })
            XCTAssertEqual(try EffortUsageScanner.scan(homeDirectory: home, now: now).map(\.id), result.map(\.id))
        }
    }

    func testResumedCodexSessionInOldDateDirectoryIncludesOnlyRecentEvents() throws {
        try withHome { home in
            let filename = ".codex/sessions/2026/01/01/resumed.jsonl"
            try write(
                home, filename,
                [
                    """
                    {"type":"turn_context","payload":{"turn_id":"resumed","model":"gpt-6-astra","effort":"high"}}
                    """,
                    codex("old-response", turn: "resumed", tokens: "90")
                        .replacingOccurrences(of: "2026-09-12", with: "2026-01-01"),
                    codex("new-response", turn: "resumed", tokens: "40"),
                ])
            try FileManager.default.setAttributes(
                [.modificationDate: now], ofItemAtPath: home.appending(path: filename).path)
            let records = try EffortUsageScanner.scan(homeDirectory: home, now: now)
            XCTAssertEqual(records.map(\.tokens), [40])
            XCTAssertEqual(records.first?.effort, "high")
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: home.appending(path: filename).path)
            XCTAssertTrue(try EffortUsageScanner.scan(homeDirectory: home, now: now).isEmpty)
        }
    }

    func testClaudeStreamingKeepsMaximumAndFirstTimestampAcrossFiles() throws {
        try withHome { home in
            try write(home, ".claude/projects/project/a.jsonl", [claude("m", time: "12:00:00", output: "3")])
            try write(home, ".claude/projects/project/b.jsonl", [claude("m", time: "12:01:00", output: "9")])
            let result = try EffortUsageScanner.scan(homeDirectory: home, now: now)
            XCTAssertEqual(result.count, 1)
            guard result.count == 1 else { return }
            XCTAssertEqual(result[0].tokens, 69)
            XCTAssertEqual(result[0].recordedAt, ISO8601DateFormatter().date(from: "2026-09-12T12:00:00Z"))
            XCTAssertEqual(result[0].effort, "medium")
            XCTAssertEqual(result[0].model, "claude-fable-5-1")
        }
    }

    func testDuplicateUnknownMetadataCannotEraseKnownValues() throws {
        try withHome { home in
            let first = claude("known-first", time: "12:00:00", output: "3")
            let increased = claude("known-first", time: "12:01:00", output: "9")
                .replacingOccurrences(of: "claude-fable-5-1", with: "unknown")
                .replacingOccurrences(of: "medium", with: "unknown")
            let second = claude("unknown-first", time: "12:02:00", output: "12")
                .replacingOccurrences(of: "claude-fable-5-1", with: "unknown")
                .replacingOccurrences(of: "medium", with: "unknown")
            let enriched = claude("unknown-first", time: "12:03:00", output: "1")
            try write(home, ".claude/projects/project/a.jsonl", [first, increased, second, enriched])
            let records = try EffortUsageScanner.scan(homeDirectory: home, now: now)
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(records.map(\.tokens), [69, 72])
            XCTAssertTrue(records.allSatisfy { $0.model == "claude-fable-5-1" && $0.effort == "medium" })
            XCTAssertEqual(records.first?.recordedAt, ISO8601DateFormatter().date(from: "2026-09-12T12:00:00Z"))
        }
    }

    func testRejectsMalformedNumbersLongLinesAndOutOfWindowEvents() throws {
        try withHome { home in
            try write(
                home, ".codex/sessions/2026/09/12/a.jsonl",
                [
                    codex("bad-bool", tokens: "true"), codex("bad-overflow", tokens: "999999999999999999999999999"),
                    codex("negative", tokens: "-2"), String(repeating: "x", count: 1_048_577),
                    codex("valid", tokens: "8"),
                    codex("old", tokens: "80").replacingOccurrences(of: "2026-09-12", with: "2026-08-01"),
                    codex("future", tokens: "80").replacingOccurrences(of: "12:00:00", with: "23:00:00"),
                ])
            try write(home, ".claude/projects/project/a.jsonl", [claude("overflow", output: String(Int.max))])
            XCTAssertEqual(try EffortUsageScanner.scan(homeDirectory: home, now: now).map(\.tokens), [8])
        }
    }

    func testSkipsSymlinkRootsDirectoriesAndFiles() throws {
        try withHome { home in
            let outside = home.appending(path: "outside")
            try write(home, "outside/valid.jsonl", [claude("outside", output: "3")])
            try FileManager.default.createDirectory(
                at: home.appending(path: ".claude"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: home.appending(path: ".claude/projects"), withDestinationURL: outside)
            XCTAssertTrue(try EffortUsageScanner.scan(homeDirectory: home, now: now).isEmpty)
            try FileManager.default.removeItem(at: home.appending(path: ".claude/projects"))
            try FileManager.default.createDirectory(
                at: home.appending(path: ".claude/projects"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: home.appending(path: ".claude/projects/link"), withDestinationURL: outside)
            try FileManager.default.createSymbolicLink(
                at: home.appending(path: ".claude/projects/link.jsonl"),
                withDestinationURL: outside.appending(path: "valid.jsonl"))
            XCTAssertTrue(try EffortUsageScanner.scan(homeDirectory: home, now: now).isEmpty)
        }
    }

    func testUnknownMetadataIsSanitizedAndStaleFilesAreSkipped() throws {
        try withHome { home in
            try write(
                home, ".claude/projects/project/a.jsonl",
                [
                    claude("a", output: "3")
                        .replacingOccurrences(of: "claude-fable-5-1", with: "private text")
                        .replacingOccurrences(of: "medium", with: "private effort")
                ])
            try write(home, ".claude/projects/project/stale.jsonl", [claude("stale", output: "3")])
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 0)],
                ofItemAtPath: home.appending(path: ".claude/projects/project/stale.jsonl").path)
            let result = try EffortUsageScanner.scan(homeDirectory: home, now: now)
            XCTAssertEqual(result.count, 1)
            guard result.count == 1 else { return }
            XCTAssertEqual(result[0].effort, "unknown")
            XCTAssertEqual(result[0].model, "unknown")
            XCTAssertTrue(try EffortUsageScanner.scan(homeDirectory: home, now: now, lookbackDays: 0).isEmpty)
        }
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
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
    }

    private func codex(_ id: String, turn: String = "unknown", tokens: String) -> String {
        """
        {"type":"token_usage_record","timestamp":"2026-09-12T12:00:00Z","payload":{"turn_id":"\(turn)","response_id":"\(id)","usage":{"total_tokens":\(tokens)}}}
        """
    }

    private func claude(_ id: String, time: String = "12:00:00", output: String) -> String {
        """
        {"type":"assistant","timestamp":"2026-09-12T\(time).000Z","perTurnEffort":"medium","effort":"high","message":{"id":"\(id)","model":"claude-fable-5-1","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":\(output)},"content":[{"type":"text","text":"synthetic ignored content"}]}}
        """
    }
}
