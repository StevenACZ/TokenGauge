import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ModelActivityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_787_000_000)

    func testAggregateChipsDropFamiliesThatAlreadyOwnAWindow() {
        let chips = ModelActivity.chips(
            buckets: buckets,
            since: start,
            limit: 2,
            family: nil,
            excludingFamilies: ["fable"]
        )

        XCTAssertEqual(chips.map(\.displayName), ["Opus", "Sonnet"])
    }

    func testScopedChipsStillReportTheirOwnFamily() {
        let chips = ModelActivity.chips(buckets: buckets, since: start, limit: 2, family: "Fable")

        XCTAssertEqual(chips.map(\.displayName), ["Fable"])
        XCTAssertEqual(chips.map(\.tokens), [78_800_000])
    }

    func testNoExclusionKeepsEveryFamily() {
        let chips = ModelActivity.chips(buckets: buckets, since: start, limit: 3)

        XCTAssertEqual(chips.map(\.displayName), ["Fable", "Opus", "Sonnet"])
    }

    private var buckets: [ModelTokenBucket] {
        [
            bucket(model: "claude-fable-5", tokens: 78_800_000),
            bucket(model: "claude-opus-5[1m]", tokens: 1_400_000),
            bucket(model: "claude-sonnet-5", tokens: 90_000),
        ]
    }

    private func bucket(model: String, tokens: Int) -> ModelTokenBucket {
        ModelTokenBucket(day: "2026-08-27", hourStart: start, model: model, tokens: tokens)
    }
}
