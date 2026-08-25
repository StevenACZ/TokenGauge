import Foundation
import XCTest

@testable import TokenGaugeCore

final class ClaudeHistoryScannerTests: XCTestCase {
    func testDeduplicatesStreamingRowsAndGroupsByLocalDay() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appending(path: "session.jsonl")
        let lines =
            [
                assistantLine(id: "msg-1", timestamp: "2026-08-24T10:00:00.000Z", input: 10, output: 5, cache: 20),
                assistantLine(id: "msg-1", timestamp: "2026-08-24T10:00:01.000Z", input: 10, output: 5, cache: 20),
                assistantLine(id: "msg-2", timestamp: "2026-08-25T09:00:00.000Z", input: 7, output: 3, cache: 0),
            ].joined(separator: "\n") + "\n"
        try Data(lines.utf8).write(to: transcript)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-08-25T12:00:00Z")!
        let usage = try ClaudeHistoryScanner.scan(
            projectsRoot: root,
            days: 2,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            usage,
            [
                DailyTokenUsage(day: "2026-08-24", tokens: 35),
                DailyTokenUsage(day: "2026-08-25", tokens: 10),
            ])
    }

    private func assistantLine(id: String, timestamp: String, input: Int, output: Int, cache: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","uuid":"uuid-\(id)","message":{"id":"\(id)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cache),"cache_read_input_tokens":0}}}
        """
    }
}
