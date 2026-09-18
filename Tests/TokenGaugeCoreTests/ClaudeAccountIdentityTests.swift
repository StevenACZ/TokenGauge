import Foundation
import XCTest

@testable import TokenGaugeCore

final class ClaudeAccountIdentityTests: XCTestCase {
    func testDecodesAccountAndIgnoresUnknownKeys() {
        let payload = Data(
            #"""
            {"numStartups":12,"projects":{"/tmp/a":{"allowedTools":[]}},
            "oauthAccount":{"accountUuid":"uuid-a","emailAddress":"one@example.com",
            "displayName":"One","organizationName":"Org","seatTier":"max"}}
            """#.utf8
        )
        let identity = ClaudeAccountIdentity(data: payload)
        XCTAssertEqual(identity?.accountUuid, "uuid-a")
        XCTAssertEqual(identity?.emailAddress, "one@example.com")
        XCTAssertEqual(identity?.displayName, "One")
        XCTAssertEqual(identity?.organizationName, "Org")
        XCTAssertEqual(identity?.label, "one@example.com")
    }

    func testFallsBackToDisplayNameAndRejectsIncompletePayloads() {
        let onlyName = ClaudeAccountIdentity(
            data: Data(#"{"oauthAccount":{"accountUuid":"uuid-b","displayName":"Two"}}"#.utf8))
        XCTAssertEqual(onlyName?.label, "Two")
        XCTAssertNil(ClaudeAccountIdentity(data: Data(#"{"numStartups":1}"#.utf8)))
        XCTAssertNil(ClaudeAccountIdentity(data: Data(#"{"oauthAccount":{"emailAddress":"one@example.com"}}"#.utf8)))
        XCTAssertNil(ClaudeAccountIdentity(data: Data(#"{"oauthAccount":{"accountUuid":""}}"#.utf8)))
        XCTAssertNil(ClaudeAccountIdentity(data: Data("not json".utf8)))
    }

    func testFingerprintIsAStableHexDigestThatHidesTheUuid() {
        let identity = ClaudeAccountIdentity(accountUuid: "uuid-a", emailAddress: "one@example.com")
        XCTAssertEqual(identity.fingerprint, ClaudeAccountIdentity(accountUuid: "uuid-a").fingerprint)
        XCTAssertNotEqual(identity.fingerprint, ClaudeAccountIdentity(accountUuid: "uuid-b").fingerprint)
        XCTAssertEqual(identity.fingerprint.count, 64)
        XCTAssertFalse(identity.fingerprint.contains("uuid-a"))
        XCTAssertTrue(identity.fingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    func testReturnsNilForMissingFile() {
        ClaudeAccountIdentityReader.invalidate()
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        XCTAssertNil(ClaudeAccountIdentityReader.current(homeDirectory: home))
    }

    func testRereadsOnlyWhenModificationDateOrSizeChanged() throws {
        ClaudeAccountIdentityReader.invalidate()
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = UsagePaths.claudeConfig(homeDirectory: home)
        try Data(#"{"oauthAccount":{"accountUuid":"uuid-a"}}"#.utf8).write(to: file)
        let stamp = Date(timeIntervalSince1970: 1_756_300_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)

        XCTAssertEqual(ClaudeAccountIdentityReader.current(homeDirectory: home)?.accountUuid, "uuid-a")

        try Data(#"{"oauthAccount":{"accountUuid":"uuid-b"}}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        XCTAssertEqual(ClaudeAccountIdentityReader.current(homeDirectory: home)?.accountUuid, "uuid-a")

        try FileManager.default.setAttributes(
            [.modificationDate: stamp.addingTimeInterval(60)], ofItemAtPath: file.path)
        XCTAssertEqual(ClaudeAccountIdentityReader.current(homeDirectory: home)?.accountUuid, "uuid-b")
    }
    func testCacheIsReusedForAnUnchangedFileAndRefreshedWhenTheSizeChanges() throws {
        ClaudeAccountIdentityReader.invalidate()
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = UsagePaths.claudeConfig(homeDirectory: home)
        let stamp = Date(timeIntervalSince1970: 1_756_500_000)
        try Data(#"{"oauthAccount":{"accountUuid":"uuid-a"}}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)

        XCTAssertEqual(ClaudeAccountIdentityReader.read(at: file)?.accountUuid, "uuid-a")

        try Data(#"{"oauthAccount":{"accountUuid":"uuid-c"}}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        XCTAssertEqual(ClaudeAccountIdentityReader.read(at: file)?.accountUuid, "uuid-a")

        try Data(#"{"oauthAccount":{"accountUuid":"uuid-c","displayName":"Three"}}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        XCTAssertEqual(ClaudeAccountIdentityReader.read(at: file)?.displayName, "Three")
    }

    func testTransientReadFailureKeepsTheLastIdentityButLogoutClearsIt() throws {
        ClaudeAccountIdentityReader.invalidate()
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: UsagePaths.claudeConfig(homeDirectory: home).path)
            try? FileManager.default.removeItem(at: home)
        }
        let file = UsagePaths.claudeConfig(homeDirectory: home)
        try Data(#"{"oauthAccount":{"accountUuid":"uuid-a"}}"#.utf8).write(to: file)
        XCTAssertEqual(ClaudeAccountIdentityReader.current(homeDirectory: home)?.accountUuid, "uuid-a")

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_756_400_000)], ofItemAtPath: file.path)
        XCTAssertEqual(ClaudeAccountIdentityReader.current(homeDirectory: home)?.accountUuid, "uuid-a")

        let moved = home.appending(path: "moved.json")
        try FileManager.default.moveItem(at: file, to: moved)
        XCTAssertEqual(ClaudeAccountIdentityReader.current(homeDirectory: home)?.accountUuid, "uuid-a")

        try Data(#"{"numStartups":3}"#.utf8).write(to: file)
        XCTAssertNil(ClaudeAccountIdentityReader.current(homeDirectory: home))
    }
}
