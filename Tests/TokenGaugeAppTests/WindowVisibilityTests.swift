import Foundation
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class WindowVisibilityTests: XCTestCase {
    func testCodexKeepsOnlyTheWeeklyMainlineWindow() {
        let windows = [
            window(id: "codex_bengalfox.primary", duration: 300, name: "GPT-5.3-Codex-Spark"),
            window(id: "codex.primary", duration: 10_080, name: nil),
            window(id: "codex_bengalfox.secondary", duration: 10_080, name: "GPT-5.3-Codex-Spark"),
        ]

        let visible = WindowVisibility.visible(windows, provider: .codex)

        XCTAssertEqual(visible.map(\.id), ["codex.primary"])
    }

    func testCodexFallsBackToMainlineWindowsWhenNoWeeklyExists() {
        let windows = [
            window(id: "codex.primary", duration: 300, name: nil),
            window(id: "codex_spark.primary", duration: 300, name: "Spark"),
        ]

        XCTAssertEqual(WindowVisibility.visible(windows, provider: .codex).map(\.id), ["codex.primary"])
    }

    func testClaudeKeepsEveryOfficialWindow() {
        let windows = [
            window(id: "five_hour", duration: 300, name: nil),
            window(id: "seven_day", duration: 10_080, name: nil),
        ]

        XCTAssertEqual(WindowVisibility.visible(windows, provider: .claude).map(\.id), ["five_hour", "seven_day"])
    }

    @MainActor
    func testModelDisplayNamesCollapseToFamilies() {
        XCTAssertEqual(ModelActivity.displayName("claude-fable-5"), "Fable")
        XCTAssertEqual(ModelActivity.displayName("claude-opus-5[1m]"), "Opus")
        XCTAssertEqual(ModelActivity.displayName("claude-haiku-4-5-20251001"), "Haiku")
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

        XCTAssertEqual(chips.map(\.displayName), ["Opus", "Fable"])
        XCTAssertEqual(chips.map(\.tokens), [400, 100])
    }

    private func window(id: String, duration: Int, name: String?) -> QuotaWindow {
        QuotaWindow(id: id, usedPercentage: 10, resetsAt: nil, durationMinutes: duration, displayName: name)
    }

    private func bucket(hour: Date, model: String, tokens: Int) -> ModelTokenBucket {
        ModelTokenBucket(day: "2033-05-18", hourStart: hour, model: model, tokens: tokens)
    }
}
