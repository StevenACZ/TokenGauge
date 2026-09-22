import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class ResetCreditsBadgeRenderingTests: XCTestCase {
    private let narrowRingCard = Theme.Layout.minimumRingCardWidth

    func testWideCardsKeepResetCreditsOnTheHeaderRow() throws {
        try withEachLanguage { language in
            for style in [QuotaPanelStyle.rings, .standard] {
                let plain = fittingSize(card(credits: nil, width: Theme.Layout.compactPanelWidth, age: 0, style: style))
                for age: TimeInterval in [0, -720, -3_540] {
                    for credits in [1, 3, 12, 120] {
                        let size = fittingSize(
                            card(credits: credits, width: Theme.Layout.compactPanelWidth, age: age, style: style))
                        XCTAssertEqual(size.height, plain.height, accuracy: 1, "\(language) \(style) \(age) \(credits)")
                    }
                }
            }
        }
    }

    func testNarrowCardsMoveResetCreditsToOneStableRowWhateverTheFreshness() throws {
        try withEachLanguage { language in
            for style in [QuotaPanelStyle.rings, .standard] {
                let plain = fittingSize(card(credits: nil, width: narrowRingCard, age: 0, style: style))
                let reference = fittingSize(card(credits: 1, width: narrowRingCard, age: 0, style: style))
                XCTAssertGreaterThan(reference.height, plain.height + 10, "\(language) \(style)")
                XCTAssertLessThan(reference.height, plain.height + 30, "\(language) \(style)")
                for age: TimeInterval in [0, -720, -3_540] {
                    for credits in [1, 3, 12, 120] {
                        let size = fittingSize(card(credits: credits, width: narrowRingCard, age: age, style: style))
                        XCTAssertEqual(
                            size.height, reference.height, accuracy: 1, "\(language) \(style) \(age) \(credits)")
                    }
                }
            }
        }
    }

    private func card(credits: Int?, width: CGFloat, age: TimeInterval, style: QuotaPanelStyle) -> some View {
        ProviderCard(
            provider: .codex,
            state: ProviderViewState(
                snapshot: Fixture.snapshot(
                    .codex,
                    windows: [
                        Fixture.window(
                            id: "codex.secondary", usedPercentage: 90, resetsAt: Date().addingTimeInterval(432_000),
                            durationMinutes: 10_080)
                    ], availableResetCredits: credits, capturedAt: Date().addingTimeInterval(age)),
                status: .ready, isRefreshing: false),
            panelStyle: style, showProviderTitle: true
        )
        .frame(width: width)
    }
}
