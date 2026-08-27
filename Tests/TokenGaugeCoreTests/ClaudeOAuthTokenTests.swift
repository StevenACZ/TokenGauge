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
}
