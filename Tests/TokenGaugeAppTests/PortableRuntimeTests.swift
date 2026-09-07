import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class PortableRuntimeTests: XCTestCase {
    func testSystemLanguageUsesFirstSupportedPreference() {
        XCTAssertEqual(AppLanguage.preferred(from: ["fr-FR", "es-PE", "en-US"]), .spanish)
        XCTAssertEqual(AppLanguage.preferred(from: ["en_US", "es"]), .english)
        XCTAssertEqual(AppLanguage.preferred(from: ["de-DE"]), .english)
    }

    func testResourceFallbackIsLazyWhenPackagedBundleExists() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        let packaged = resources.appendingPathComponent("TokenGauge_TokenGaugeApp.bundle")
        try FileManager.default.createDirectory(at: packaged, withIntermediateDirectories: true)
        try Data(
            "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.resources</string></dict></plist>"
                .utf8
        )
        .write(to: root.appendingPathComponent("Contents/Info.plist"))
        let main = try XCTUnwrap(Bundle(url: root))
        var fallbackUsed = false
        let resolved = AppResources.resolve(in: main) {
            fallbackUsed = true
            return .main
        }
        XCTAssertFalse(fallbackUsed)
        XCTAssertEqual(resolved.bundleURL.path, packaged.path)
    }

    func testDevelopmentResourcesIncludeImagesAndBothLanguages() {
        XCTAssertNotNil(AppResources.bundle.url(forResource: "provider-codex", withExtension: "svg"))
        XCTAssertNotNil(AppResources.bundle.url(forResource: "es", withExtension: "lproj"))
        XCTAssertNotNil(AppResources.bundle.url(forResource: "en", withExtension: "lproj"))
    }

    func testCodexDiscoveryIncludesOnlyAbsoluteInheritedPathEntries() {
        let home = URL(filePath: "/synthetic-user")
        let candidates = CodexAppServerClient(homeDirectory: home).executableCandidates(
            environment: ["PATH": ":relative/bin:/custom/node/bin:/another bin:"]
        ).map(\.path)
        XCTAssertEqual(
            candidates,
            [
                "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/synthetic-user/.local/bin/codex",
                "/custom/node/bin/codex", "/another bin/codex",
            ])
    }

    func testCodexConfiguredExecutableTakesPriority() throws {
        let executable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: executable) }
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = CodexAppServerClient()
        XCTAssertEqual(client.resolveExecutable(environment: [:], configuredPath: executable.path), executable)
        XCTAssertEqual(
            client.executableCandidates(environment: [:], configuredPath: "relative").first?.path,
            "/opt/homebrew/bin/codex"
        )
    }

    func testAppServerDoesNotBlockOnLargeStderr() throws {
        let result = try run("/usr/bin/head -c 131072 /dev/zero >&2; printf '%s\\n' '{\"id\":3}' '{\"id\":4}'")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testAppServerDrainsOutputAndWaitsForRequiredResponsesBeforeClosingInput() throws {
        let script = "read first; printf '%s\\n' '{\"id\":3}'; printf '%s\\n' '{\"id\":4}'; while read line; do :; done"
        let result = try run(script, input: "initialize\n")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(String(decoding: result.standardOutput, as: UTF8.self).contains("\"id\":4"))
    }

    func testAppServerFailureDoesNotExposeStderr() {
        XCTAssertThrowsError(try run("echo private-value >&2; exit 9")) { error in
            XCTAssertEqual(error as? UsageDataError, .processFailed("Codex app-server exited with status 9"))
        }
    }

    func testAppServerTimeoutIsBounded() {
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try run("while :; do :; done", timeout: 0.1)) { error in
            XCTAssertEqual(error as? UsageDataError, .timedOut)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }

    private func run(_ script: String, input: String = "", timeout: TimeInterval = 2) throws -> ProcessResult {
        try ProcessRunner.run(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], input: Data(input.utf8),
            requiredResponseIDs: [3, 4], timeout: timeout
        )
    }
}
