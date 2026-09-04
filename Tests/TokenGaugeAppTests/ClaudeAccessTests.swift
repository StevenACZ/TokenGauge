import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class ClaudeAccessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testHTTPStatusDistinguishesAuthenticationAndAccessFromTemporaryFailures() {
        XCTAssertEqual(ClaudeAccountUsageError.httpStatus(401), .authenticationRequired)
        for status in [402, 403] {
            XCTAssertEqual(ClaudeAccountUsageError.httpStatus(status), .accessDenied)
        }
        for status in [0, 400, 404, 429, 500, 503] {
            XCTAssertEqual(ClaudeAccountUsageError.httpStatus(status), .unavailable)
        }
    }

    func testEmptySuccessfulQuotaIsDistinctFromMalformedData() throws {
        XCTAssertTrue(try ClaudeAccountUsageClient.parseWindows(Data(#"{"limits":[]}"#.utf8)).isEmpty)
        for payload in ["invalid", "{}", #"{"limits":[{}]}"#] {
            XCTAssertThrowsError(try ClaudeAccountUsageClient.parseWindows(Data(payload.utf8))) { error in
                XCTAssertEqual(error as? ClaudeAccountUsageError, .unavailable)
            }
        }
    }

    func testFreshFallbackCannotMaskAuthenticationOrAccessFailure() {
        let cases: [(ClaudeAccountUsageError, ClaudeAccessState)] = [
            (.authenticationRequired, .authenticationRequired), (.accessDenied, .accessDenied),
        ]
        for (error, expected) in cases {
            let result = resolve(.failure(error), cached: cached())
            XCTAssertEqual(result.access, expected)
            XCTAssertEqual(result.snapshot.windows, cached().windows)
            XCTAssertEqual(result.snapshot.capturedAt, cached().capturedAt)
        }
    }

    func testTemporaryFailureUsesCachedStateEvenWhenQuotaWasJustCaptured() {
        let result = resolve(.failure(ClaudeAccountUsageError.unavailable), cached: cached())
        XCTAssertEqual(result.access, .cached)
        XCTAssertEqual(result.snapshot.capturedAt, now.addingTimeInterval(-1))
    }

    func testNetworkFailureWithoutCurrentQuotaIsUnavailableAndPreservesActivity() {
        let bucket = ModelTokenBucket(day: "2033-05-18", hourStart: now, model: "claude-opus", tokens: 123)
        let result = ClaudeUsageClient.resolve(
            account: .failure(URLError(.notConnectedToInternet)),
            cached: cached(reset: now.addingTimeInterval(-1)),
            capture: nil,
            modelBuckets: [bucket],
            now: now
        )
        XCTAssertEqual(result.access, .unavailable)
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        XCTAssertEqual(result.snapshot.modelBuckets, [bucket])
        XCTAssertEqual(result.snapshot.dailyUsage.first?.tokens, 123)
    }

    func testEmptySuccessIsUnavailableWhilePreservingCachedQuota() {
        let result = resolve(.success(ClaudeAccountSnapshot(capturedAt: now, windows: [])), cached: cached())
        XCTAssertEqual(result.access, .unavailable)
        XCTAssertEqual(result.snapshot.windows, cached().windows)
    }

    func testNonemptySuccessRestoresLiveStateAndUsesCaptureAsActivityEvidence() {
        let captureTime = now.addingTimeInterval(-30)
        let capture = ClaudeCapturedSnapshot(capturedAt: captureTime, windows: [:])
        let account = ClaudeAccountSnapshot(capturedAt: now, windows: cached().windows)
        let result = ClaudeUsageClient.resolve(
            account: .success(account), cached: nil, capture: capture, modelBuckets: [], now: now
        )
        XCTAssertEqual(result.access, .live)
        XCTAssertEqual(result.snapshot.capturedAt, now)
        XCTAssertEqual(result.lastActivityAt, captureTime)
        XCTAssertNil(resolve(.success(account)).lastActivityAt)
    }

    func testFallbackActivityEvidenceUsesStatusLineTimestamp() {
        let captureTime = now.addingTimeInterval(-60)
        let result = ClaudeUsageClient.resolve(
            account: .failure(ClaudeAccountUsageError.authenticationRequired),
            cached: cached(),
            capture: ClaudeCapturedSnapshot(capturedAt: captureTime, windows: [:]),
            modelBuckets: [],
            now: now
        )
        XCTAssertEqual(result.lastActivityAt, captureTime)
        XCTAssertEqual(result.access, .authenticationRequired)
    }

    private func resolve(
        _ account: Result<ClaudeAccountSnapshot, Error>, cached: ClaudeAccountSnapshot? = nil
    ) -> ClaudeUsageResult {
        ClaudeUsageClient.resolve(account: account, cached: cached, capture: nil, modelBuckets: [], now: now)
    }

    private func cached(reset: Date? = nil) -> ClaudeAccountSnapshot {
        ClaudeAccountSnapshot(
            capturedAt: now.addingTimeInterval(-1),
            windows: [
                QuotaWindow(
                    id: "seven_day", usedPercentage: 52,
                    resetsAt: reset ?? now.addingTimeInterval(86_400), durationMinutes: 10_080, displayName: nil
                )
            ]
        )
    }
}
