import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class WindowVisibilityTests: XCTestCase {
    func testCodexKeepsOnlyTheWeeklyMainlineWindow() {
        let windows = [
            Fixture.window(id: "codex_bengalfox.primary", durationMinutes: 300, displayName: "GPT-5.3-Codex-Spark"),
            Fixture.window(id: "codex.primary", durationMinutes: 10_080),
            Fixture.window(
                id: "codex_bengalfox.secondary", durationMinutes: 10_080, displayName: "GPT-5.3-Codex-Spark"),
        ]

        let visible = WindowVisibility.visible(windows, provider: .codex)

        XCTAssertEqual(visible.map(\.id), ["codex.primary"])
    }

    func testCodexFallsBackToMainlineWindowsWhenNoWeeklyExists() {
        let windows = [
            Fixture.window(id: "codex.primary", durationMinutes: 300),
            Fixture.window(id: "codex_spark.primary", durationMinutes: 300, displayName: "Spark"),
        ]

        XCTAssertEqual(WindowVisibility.visible(windows, provider: .codex).map(\.id), ["codex.primary"])
    }

    func testClaudeKeepsEveryOfficialWindow() {
        let windows = [
            Fixture.window(id: "five_hour", durationMinutes: 300),
            Fixture.window(id: "seven_day", durationMinutes: 10_080),
        ]

        XCTAssertEqual(WindowVisibility.visible(windows, provider: .claude).map(\.id), ["five_hour", "seven_day"])
    }

    @MainActor
    func testModelFamiliesCollapseVersions() {
        XCTAssertEqual(ModelActivity.family("claude-fable-5"), "Fable")
        XCTAssertEqual(ModelActivity.family("claude-opus-5[1m]"), "Opus")
        XCTAssertEqual(ModelActivity.family("claude-haiku-4-5-20251001"), "Haiku")
    }

    @MainActor
    func testModelDisplayNamesKeepTheVersion() {
        XCTAssertEqual(ModelActivity.displayName("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(ModelActivity.displayName("claude-opus-5[1m]"), "Opus 5")
        XCTAssertEqual(ModelActivity.displayName("claude-fable-5-1"), "Fable 5.1")
        XCTAssertEqual(ModelActivity.displayName("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(ModelActivity.displayName("gpt-6-astra"), "GPT-6 Astra")
        XCTAssertEqual(ModelActivity.displayName("gpt-5.3-codex"), "GPT-5.3 Codex")
    }

    @MainActor
    func testChipsRankByTokensAndRespectTheWindowStart() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let buckets = [
            bucket(hour: start.addingTimeInterval(-3600), model: "claude-fable-5", tokens: 900),
            bucket(hour: start, model: "claude-fable-5", tokens: 100),
            bucket(hour: start.addingTimeInterval(3600), model: "claude-opus-5", tokens: 400),
        ]

        let chips = ModelActivity.chips(buckets: buckets, since: start)

        XCTAssertEqual(chips.map(\.displayName), ["Opus 5", "Fable 5"])
        XCTAssertEqual(chips.map(\.tokens), [400, 100])
    }

    private func bucket(hour: Date, model: String, tokens: Int) -> ModelTokenBucket {
        ModelTokenBucket(day: "2033-05-18", hourStart: hour, model: model, tokens: tokens)
    }
}
