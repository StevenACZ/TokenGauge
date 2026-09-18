import Foundation
import XCTest

@testable import TokenGaugeCore

final class ClaudeOAuthTokenTests: XCTestCase {
    func testParsesAccessTokenAndExpiry() {
        let payload = Data(
            #"{"claudeAiOauth":{"accessToken":"sk-ant-test","expiresAt":1756300000000}}"#.utf8
        )
        let token = ClaudeOAuthTokenReader.parse(payload)
        XCTAssertEqual(token?.value, "sk-ant-test")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 1_756_300_000))
    }

    func testRejectsMissingOrEmptyToken() {
        XCTAssertNil(ClaudeOAuthTokenReader.parse(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
        XCTAssertNil(ClaudeOAuthTokenReader.parse(Data(#"{"other":1}"#.utf8)))
        XCTAssertNil(ClaudeOAuthTokenReader.parse(Data("not json".utf8)))
    }

    func testAccountSwitchReadsTheKeychainOnceAndKeepsTheCacheOtherwise() {
        ClaudeOAuthTokenReader.invalidate()
        nonisolated(unsafe) var reads = 0
        let load: (String) -> @Sendable () -> ClaudeOAuthToken? = { value in
            {
                reads += 1
                return ClaudeOAuthToken(value: value, expiresAt: Date().addingTimeInterval(3600))
            }
        }

        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: "uuid-a", load: load("token-a"))?.value, "token-a")
        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: "uuid-a", load: load("token-a"))?.value, "token-a")
        XCTAssertEqual(reads, 1)

        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: "uuid-b", load: load("token-b"))?.value, "token-b")
        XCTAssertEqual(reads, 2)

        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: "uuid-b", load: load("token-b"))?.value, "token-b")
        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: nil, load: load("token-b"))?.value, "token-b")
        XCTAssertEqual(reads, 2)
        ClaudeOAuthTokenReader.invalidate()
    }

    func testUntaggedCacheIsNeverPromotedToARequestedAccount() {
        ClaudeOAuthTokenReader.invalidate()
        nonisolated(unsafe) var reads = 0
        let load: (String) -> @Sendable () -> ClaudeOAuthToken? = { value in
            {
                reads += 1
                return ClaudeOAuthToken(value: value, expiresAt: Date().addingTimeInterval(3600))
            }
        }

        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: nil, load: load("token-a"))?.value, "token-a")
        XCTAssertEqual(reads, 1)

        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: "uuid-b", load: load("token-b"))?.value, "token-b")
        XCTAssertEqual(reads, 2)

        XCTAssertEqual(ClaudeOAuthTokenReader.read(accountUuid: "uuid-b", load: load("token-b"))?.value, "token-b")
        XCTAssertEqual(reads, 2)
        ClaudeOAuthTokenReader.invalidate()
    }
}
