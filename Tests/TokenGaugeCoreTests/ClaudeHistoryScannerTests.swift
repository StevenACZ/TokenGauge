import Foundation
import XCTest

@testable import TokenGaugeCore

final class ClaudeHistoryScannerTests: XCTestCase {
    func testDeduplicatesStreamingRowsAndGroupsByModelHourAndDay() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appending(path: "session.jsonl")
        let lines =
            [
                assistantLine(
                    id: "msg-1",
                    timestamp: "2026-08-24T10:00:00.000Z",
                    model: "claude-fable-5",
                    input: 10,
                    output: 5,
                    cache: 20
                ),
                assistantLine(
                    id: "msg-1",
                    timestamp: "2026-08-24T10:00:01.000Z",
                    model: "claude-fable-5",
                    input: 10,
                    output: 5,
                    cache: 20
                ),
                assistantLine(
                    id: "msg-2",
                    timestamp: "2026-08-25T09:10:00.000Z",
                    model: "claude-opus-5",
                    input: 7,
                    output: 3,
                    cache: 0
                ),
                assistantLine(
                    id: "msg-3",
                    timestamp: "2026-08-25T09:50:00.000Z",
                    model: "claude-opus-5",
                    input: 1,
                    output: 1,
                    cache: 0
                ),
            ].joined(separator: "\n") + "\n"
        try Data(lines.utf8).write(to: transcript)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-25T12:00:00Z")!
        let buckets = try ClaudeHistoryScanner.scan(
            projectsRoot: root,
            days: 2,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets.map(\.model), ["claude-fable-5", "claude-opus-5"])
        XCTAssertEqual(buckets.map(\.tokens), [35, 12])
        XCTAssertEqual(buckets.map(\.day), ["2026-08-24", "2026-08-25"])
        XCTAssertEqual(
            ModelTokenAggregator.daily(buckets),
            [
                DailyTokenUsage(day: "2026-08-24", tokens: 35),
                DailyTokenUsage(day: "2026-08-25", tokens: 12),
            ])
    }

    func testGroupsRecordsWithoutModelUnderUnknown() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appending(path: "session.jsonl")
        let line = """
            {"type":"assistant","timestamp":"2026-08-25T09:00:00.000Z","uuid":"uuid-a","message":{"id":"a","model":"<synthetic>","usage":{"input_tokens":4,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
            """
        try Data((line + "\n").utf8).write(to: transcript)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-25T12:00:00Z")!
        let buckets = try ClaudeHistoryScanner.scan(projectsRoot: root, days: 2, now: now, calendar: calendar)

        XCTAssertEqual(buckets.map(\.model), ["unknown"])
        XCTAssertEqual(buckets.map(\.tokens), [5])
    }

    private func assistantLine(
        id: String,
        timestamp: String,
        model: String,
        input: Int,
        output: Int,
        cache: Int
    ) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","uuid":"uuid-\(id)","message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cache),"cache_read_input_tokens":0}}}
        """
    }
}
