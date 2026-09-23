import Foundation
import XCTest
import os

@testable import TokenGaugeApp

final class FileChangeMonitorTests: XCTestCase {
    func testDetectsLateCreationInPlaceWritesAndAtomicReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "tg-monitor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "auth.json")
        let changes = OSAllocatedUnfairLock(initialState: 0)
        let monitor = FileChangeMonitor(url: url, debounce: 0.05) { changes.withLock { $0 += 1 } }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .milliseconds(100))

        try Data("created".utf8).write(to: url)
        try await waitFor(changes, atLeast: 1)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" appended".utf8))
        try handle.close()
        try await waitFor(changes, atLeast: 2)

        try Data("replaced".utf8).write(to: url, options: .atomic)
        try await waitFor(changes, atLeast: 3)

        try Data("rewritten".utf8).write(to: url)
        try await waitFor(changes, atLeast: 4)
    }

    func testUnrelatedSiblingsDoNotReportAMissingFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "tg-monitor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let changes = OSAllocatedUnfairLock(initialState: 0)
        let monitor = FileChangeMonitor(url: directory.appending(path: "auth.json"), debounce: 0.05) {
            changes.withLock { $0 += 1 }
        }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .milliseconds(100))

        try Data("noise".utf8).write(to: directory.appending(path: "history.jsonl"))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(changes.withLock { $0 }, 0)
    }

    private func waitFor(_ changes: OSAllocatedUnfairLock<Int>, atLeast count: Int) async throws {
        for _ in 0..<200 where changes.withLock({ $0 }) < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(changes.withLock { $0 }, count)
    }
}
