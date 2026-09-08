import Darwin
import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeHistoryProcessTests: XCTestCase {
    func testDrainsNormalizedHistoryLargerThanPipeCapacity() throws {
        let buckets = (0..<2000).map { index in
            ModelTokenBucket(
                day: "2026-09-07", hourStart: Date(timeIntervalSince1970: 1_788_760_800 + Double(index * 3600)),
                model: "claude-synthetic", tokens: index + 1
            )
        }
        let payload = try JSONEncoder().encode(buckets)
        XCTAssertGreaterThan(payload.count, 131_072)
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try payload.write(to: file)
        let actual = try ClaudeUsageClient.historyBuckets(
            executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/head -c 131072 /dev/zero >&2; /bin/cat \"$1\"", "history-test", file.path],
            timeout: 3
        )
        XCTAssertEqual(actual, buckets)
    }

    func testFailedHelperDoesNotExposeStderr() {
        XCTAssertThrowsError(try run("printf 'synthetic-private-diagnostic' >&2; exit 9")) { error in
            XCTAssertEqual(error as? UsageDataError, .processFailed("History helper exited with status 9"))
        }
    }

    func testInvalidOutputIsReportedWithoutRawPayload() {
        XCTAssertThrowsError(try run("printf 'synthetic-private-output'")) { error in
            XCTAssertEqual(error as? UsageDataError, .invalidPayload)
        }
    }

    func testTimeoutKillsHelperIgnoringTerminationAndDiscardsStderr() throws {
        let pidFile = temporaryFile()
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(
            try ClaudeUsageClient.historyBuckets(
                executable: URL(filePath: "/bin/sh"),
                arguments: [
                    "-c", "trap '' TERM; printf '%s' $$ > \"$1\"; printf 'private' >&2; while :; do :; done",
                    "history-test", pidFile.path,
                ],
                timeout: 0.2
            )
        ) { error in
            XCTAssertEqual(error as? UsageDataError, .timedOut)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2.5)
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    private func run(_ script: String) throws -> [ModelTokenBucket] {
        try ClaudeUsageClient.historyBuckets(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], timeout: 2
        )
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}
