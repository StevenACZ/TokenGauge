import Foundation
import XCTest

@testable import TokenGaugeCore

final class ClaudeExtraAccountTests: XCTestCase {
    func testAccountsSavedBeforeTheMenuBarOptionStillDecode() throws {
        let json =
            #"[{"id":"8C2D1E0A-4E4B-4B8E-9C55-2B0D7C1F9A10","name":"Side","location":"~/.claude-side","tint":"violet"}]"#
        let accounts = try JSONDecoder().decode([ClaudeExtraAccount].self, from: Data(json.utf8))
        XCTAssertEqual(accounts.first?.tint, .violet)
        XCTAssertEqual(accounts.first?.showsInMenuBar, false)
        XCTAssertEqual(accounts.first?.icon, .dot)
    }

    func testLocalAndRemoteLocationsParse() {
        XCTAssertEqual(
            ClaudeAccountLocation.parse(" ~/.claude-side "),
            ClaudeAccountLocation(host: nil, directory: "~/.claude-side"))
        XCTAssertEqual(
            ClaudeAccountLocation.parse("work-mac:~/.claude-work"),
            ClaudeAccountLocation(host: "work-mac", directory: "~/.claude-work"))
        XCTAssertEqual(
            ClaudeAccountLocation.parse("me@work.local:/Users/me/.claude"),
            ClaudeAccountLocation(host: "me@work.local", directory: "/Users/me/.claude"))
    }

    func testUnsafeOrIncompleteLocationsAreRejected() {
        for text in [
            "", "work-mac:", "-oProxyCommand=x:~/.claude", "host name:~/.claude", "relative/dir", "~/it's", "a:b:c",
        ] {
            XCTAssertNil(ClaudeAccountLocation.parse(text), text)
        }
    }

    func testRemoteCommandQuotesTheScriptAndTheDirectory() {
        let location = ClaudeAccountLocation(host: "work-mac", directory: "~/.claude work")
        let (executable, arguments) = location.processArguments
        XCTAssertEqual(executable, "/usr/bin/ssh")
        XCTAssertEqual(Array(arguments.prefix(6)), ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-T", "work-mac"])
        XCTAssertTrue(arguments[6].hasPrefix("/bin/sh -c '"))
        XCTAssertTrue(arguments[6].hasSuffix(" sh '~/.claude work'"))
        XCTAssertEqual(ClaudeAccountLocation.quoted("it's"), "'it'\\''s'")
    }

    func testLocalScriptReadsTheKeychainItemNamedAfterTheDirectory() throws {
        let script = ClaudeAccountLocation.script
        XCTAssertTrue(script.contains("shasum -a 256 | cut -c1-8"))
        XCTAssertTrue(script.contains("curl -s -m 10 -H @-"))
        XCTAssertTrue(script.contains("TG_STATUS %{http_code} %header{retry-after}"))
        XCTAssertTrue(script.contains("claudeAiOauth.expiresAt"))
        XCTAssertFalse(script.contains("Bearer $t\" https"))
    }

    func testOutputParsesWindowsAndStatuses() {
        let body =
            #"{"limits":[{"kind":"session","percent":43,"resets_at":"2026-10-09T18:40:00.403510+00:00"},{"kind":"weekly_all","percent":5,"resets_at":"2026-10-16T10:00:00Z"}]}"#
        guard case .windows(let windows) = ClaudeExtraAccountParser.parse(Data((body + "\nTG_STATUS 200\n").utf8))
        else {
            return XCTFail("expected windows")
        }
        XCTAssertEqual(windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(windows.first?.usedPercentage, 43)
        XCTAssertEqual(ClaudeExtraAccountParser.parse(Data("TG_STATUS 401\n".utf8)), .status(401))
        XCTAssertEqual(
            ClaudeExtraAccountParser.parse(Data("{\"error\":1}\nTG_STATUS 429 1206\n".utf8)),
            .rateLimited(retryAfter: 1206))
        XCTAssertEqual(
            ClaudeExtraAccountParser.parse(Data("{\"error\":1}\nTG_STATUS 429 \n".utf8)), .rateLimited(retryAfter: nil))
        XCTAssertEqual(ClaudeExtraAccountParser.parse(Data("TG_STATUS 403 \n".utf8)), .status(403))
        XCTAssertEqual(ClaudeExtraAccountParser.parse(Data("TG_STATUS expired\n".utf8)), .expired)
        XCTAssertEqual(ClaudeExtraAccountParser.parse(Data("{\"limits\":[]}\nTG_STATUS 200".utf8)), .windows([]))
        XCTAssertEqual(ClaudeExtraAccountParser.parse(Data("ssh: connect refused".utf8)), .unreachable)
        XCTAssertEqual(ClaudeExtraAccountParser.parse(nil), .unreachable)
    }
}
