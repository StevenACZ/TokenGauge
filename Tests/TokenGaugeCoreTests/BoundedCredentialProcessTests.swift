import Foundation
import XCTest

@testable import TokenGaugeCore

final class BoundedCredentialProcessTests: XCTestCase {
    func testReadsPayloadLargerThanPipeCapacityWithoutDeadlock() {
        let output = run("/usr/bin/head -c 131072 /dev/zero")
        XCTAssertEqual(output?.count, 131_072)
    }

    func testRejectsFailedProcessAndOversizedOutput() {
        XCTAssertNil(run("printf synthetic; exit 1"))
        XCTAssertNil(run("/usr/bin/head -c 2097152 /dev/zero"))
    }

    func testTimeoutTerminatesUnresponsiveProcess() {
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(run("trap '' TERM; while :; do :; done", timeout: 0.1))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }

    private func run(_ script: String, timeout: TimeInterval = 2) -> Data? {
        ClaudeOAuthTokenReader.boundedPayload(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], timeout: timeout
        )
    }
}
