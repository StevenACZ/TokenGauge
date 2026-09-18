import Foundation
import XCTest
import os

@testable import TokenGaugeApp

final class BlockingWorkTests: XCTestCase {
    private struct Failure: Error {}

    func testBlockingWorkRunsOffCooperativePool() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<8 {
                group.addTask {
                    try await BlockingWork.run {
                        usleep(150_000)
                        return index
                    }
                }
            }
            var seen: Set<Int> = []
            for try await value in group { seen.insert(value) }
            return seen
        }

        XCTAssertEqual(values, Set(0..<8))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.9)
    }

    func testRunPropagatesThrownErrors() async {
        do {
            _ = try await BlockingWork.run { () -> Int in throw Failure() }
            XCTFail("Expected the blocking work to rethrow")
        } catch {
            XCTAssertTrue(error is Failure)
        }
    }

    func testWaitForResultReturnsTheValueAndPropagatesErrors() throws {
        XCTAssertEqual(try BlockingWork.waitForResult(timeout: 5) { 42 }, 42)
        XCTAssertThrowsError(try BlockingWork.waitForResult(timeout: 5) { () -> Int in throw Failure() }) { error in
            XCTAssertTrue(error is Failure)
        }
    }

    func testWaitForResultTimesOutAndCancelsTheOperation() {
        let cancelled = expectation(description: "operation cancelled")
        XCTAssertThrowsError(
            try BlockingWork.waitForResult(timeout: 0.2) { () -> Int in
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    cancelled.fulfill()
                    throw error
                }
                return 1
            }
        ) { error in
            XCTAssertTrue(error is BlockingWork.TimedOut)
        }
        wait(for: [cancelled], timeout: 2)
    }
}
