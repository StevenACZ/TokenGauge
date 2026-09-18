import Darwin
import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeRecoveryProcessTests: XCTestCase {
    func testTTYEnvironmentDirectoryNoInputAndNoisyOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appending(path: "ready")
        let script = """
            test -t 0 && test -t 1 && test -t 2 || exit 1
            test "$PWD" -ef "$HOME/Library/Application Support/TokenGauge/recovery" || exit 2
            test -z "$ANTHROPIC_API_KEY$CLAUDECODE$NODE_OPTIONS$TMUX" || exit 3
            case "$PATH" in *evil*) exit 4;; esac
            stty -icanon min 0 time 1
            test "$(dd bs=1 count=1 2>/dev/null | wc -c | tr -d ' ')" = 0 || exit 5
            /usr/bin/head -c 1048576 /dev/zero
            /usr/bin/head -c 1048576 /dev/zero >&2
            touch "$HOME/ready"
            sleep 10
            """
        var checks: [TimeInterval] = []
        XCTAssertTrue(
            run(script, directory: directory, timeout: 5) {
                checks.append(ProcessInfo.processInfo.systemUptime)
                return FileManager.default.fileExists(atPath: marker.path)
            }
        )
        XCTAssertGreaterThanOrEqual(checks.count, 2)
        for (first, second) in zip(checks, checks.dropFirst()) {
            XCTAssertGreaterThanOrEqual(second - first, 2)
        }
    }

    func testFailureNeverBecomesSuccessFromExitCode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertFalse(run("exit 0", directory: directory, timeout: 0.2) { false })
        XCTAssertFalse(run("exit 9", directory: directory, timeout: 0.2) { false })
        XCTAssertFalse(
            ClaudeRecoveryProcess.run(
                executable: directory.appending(path: "missing"), homeDirectory: directory, timeout: 0.2
            ) { true }
        )
    }

    func testTimeoutKillsOwnedGroupIncludingHungDescendant() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = """
            trap '' TERM
            echo $$ > "$HOME/parent"
            /bin/sh -c 'trap "" TERM; while :; do sleep 1; done' &
            echo $! > "$HOME/child"
            wait
            """
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertFalse(run(script, directory: directory, timeout: 0.4) { false })
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        for name in ["parent", "child"] {
            let value = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
            let pid = try XCTUnwrap(Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)))
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while kill(pid, 0) == 0, ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
            XCTAssertEqual(kill(pid, 0), -1)
            XCTAssertEqual(errno, ESRCH)
        }
    }

    func testProductionArgumentsRemainSafeModeOnly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "fake-claude")
        try "#!/bin/sh\n[ \"$#\" = 1 ] && [ \"$1\" = --safe-mode ] && touch \"$HOME/ready\"\nsleep 10\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        XCTAssertTrue(
            ClaudeRecoveryProcess.run(executable: executable, homeDirectory: directory, timeout: 4) {
                FileManager.default.fileExists(atPath: directory.appending(path: "ready").path)
            }
        )
    }

    func testCancellationAfterStartupStopsAndReapsChildPromptly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appending(path: "parent")
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertFalse(
            ClaudeRecoveryProcess.run(
                executable: URL(filePath: "/bin/sh"), homeDirectory: directory, timeout: 10,
                arguments: ["-c", "trap '' TERM; echo $$ > \"$HOME/parent\"; while :; do sleep 1; done"],
                environment: [:],
                shouldContinue: { !FileManager.default.fileExists(atPath: marker.path) }
            ) { false }
        )
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        let value = try String(contentsOf: marker, encoding: .utf8)
        let pid = try XCTUnwrap(Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testExitedChildCannotClaimLaterCredentialRecovery() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertFalse(
            run("exit 9", directory: directory, timeout: 5) {
                ProcessInfo.processInfo.systemUptime - start > 0.2
            })
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertFalse(
            run("exit 9", directory: directory, timeout: 5) {
                usleep(200_000)
                return true
            })
    }

    func testChildRunsInDedicatedDirectoryCreatedPrivatelyInsteadOfHome() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = UsagePaths.recoveryWorkingDirectory(homeDirectory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertFalse(
            ClaudeRecoveryProcess.run(
                executable: URL(filePath: "/bin/sh"), homeDirectory: directory, timeout: 4,
                arguments: ["-c", "pwd > \"$TMPDIR/cwd\""], environment: ["TMPDIR": directory.path]
            ) { false }
        )
        let value = try String(contentsOf: directory.appending(path: "cwd"), encoding: .utf8)
        let observed = URL(filePath: value.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(observed.resolvingSymlinksInPath().path, recovery.resolvingSymlinksInPath().path)
        XCTAssertNotEqual(observed.resolvingSymlinksInPath().path, directory.resolvingSymlinksInPath().path)
        let permissions =
            try FileManager.default.attributesOfItem(atPath: recovery.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
    }

    func testAppServerAndCaptureHelperRunInTheSameDedicatedDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = UsagePaths.recoveryWorkingDirectory(homeDirectory: directory)
        let result = try ProcessRunner.run(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", "pwd"], input: Data(),
            requiredResponseIDs: [], timeout: 4, workingDirectory: recovery
        )
        let value = String(decoding: result.standardOutput, as: UTF8.self)
        let observed = URL(filePath: value.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(observed.resolvingSymlinksInPath().path, recovery.resolvingSymlinksInPath().path)
        XCTAssertNotEqual(observed.resolvingSymlinksInPath().path, directory.resolvingSymlinksInPath().path)
        let permissions =
            try FileManager.default.attributesOfItem(atPath: recovery.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o700)
    }

    private func run(
        _ script: String, directory: URL, timeout: TimeInterval, recovered: () -> Bool
    ) -> Bool {
        ClaudeRecoveryProcess.run(
            executable: URL(filePath: "/bin/sh"), homeDirectory: directory, timeout: timeout,
            arguments: ["-c", script],
            environment: [
                "ANTHROPIC_API_KEY": "synthetic", "CLAUDECODE": "1", "NODE_OPTIONS": "--bad-option",
                "TMUX": "synthetic", "PATH": "/evil", "HOME": "/evil", "LANG": "en_US.UTF-8",
            ], recovered: recovered
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
