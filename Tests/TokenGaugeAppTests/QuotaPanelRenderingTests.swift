import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class QuotaPanelRenderingTests: XCTestCase {
    func testNewStylesRenderOneTwoAndThreeWindowsAtSupportedWidths() throws {
        try withEachLanguage { _ in
            for style in [QuotaPanelStyle.compact, .rings] {
                for count in 1...3 {
                    for width: CGFloat in style == .rings ? [240, 334] : [334, 414] {
                        let claude = state(count: count)
                        let card = ProviderCard(
                            provider: .claude, state: claude, panelStyle: style, showProviderTitle: true,
                            showHourlyPace: true, paces: paces(claude))
                        let bitmap = try render(card.frame(width: width), maximumHeight: 420)
                        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                        XCTAssertEqual(bitmap.size.width, width, accuracy: 1)
                    }
                }
            }
        }
    }

    func testCompactOneAndTwoWindowCardsStayBelowCombinedHeightBudget() throws {
        try withEachLanguage { _ in
            var combinedHeight: CGFloat = Theme.Layout.sectionSpacing
            for count in 1...2 {
                let card = ProviderCard(
                    provider: .claude, state: state(count: count), panelStyle: .compact, showProviderTitle: true)
                let bitmap = try render(card.frame(width: 414), maximumHeight: 110)
                combinedHeight += bitmap.size.height
            }
            XCTAssertLessThanOrEqual(combinedHeight, 190)
        }
    }

    func testTwoRingCellsFillTheAvailableWidthWithoutAnEmptyThirdSlot() throws {
        let bitmap = try render(
            QuotaRingGrid {
                Color.red.frame(height: 20)
                Color.blue.frame(height: 20)
            }.frame(width: 320), maximumHeight: 20)
        let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide - 2, y: 4)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(pixel.alphaComponent, 0.9)
        XCTAssertGreaterThan(pixel.blueComponent, pixel.redComponent)
    }

    func testProportionalRingWidthsKeepTwoAndThreeWindowsOnOneRow() throws {
        try withEachLanguage { _ in
            for count in [2, 3] {
                let width = QuotaRingLayout.minimumGridWidth(windows: count) + Theme.Layout.cardPadding * 2
                let claude = state(count: count)
                let card = ProviderCard(
                    provider: .claude, state: claude, panelStyle: .rings, showProviderTitle: true,
                    showHourlyPace: true, paces: paces(claude))
                let bitmap = try render(card.frame(width: width), maximumHeight: 260)
                XCTAssertEqual(bitmap.size.width, width, accuracy: 1)
            }
        }
    }

    func testHistoricalAndAbsentDataRenderWithoutExpandingTheCard() throws {
        for style in [QuotaPanelStyle.compact, .rings] {
            for providerStatus in [ProviderStatus.credentialExpired, .authenticationRequired, .unavailable] {
                let card = ProviderCard(
                    provider: .claude, state: state(count: 3, status: providerStatus), panelStyle: style,
                    showProviderTitle: true, claudeAutomaticRecovery: true)
                _ = try render(card.frame(width: 240), maximumHeight: 480)
            }
            let empty = ProviderCard(
                provider: .claude, state: .loading, panelStyle: style, showProviderTitle: true)
            _ = try render(empty.frame(width: 240), maximumHeight: 180)
        }
    }

    func testHiddenWindowsDoNotOccupyRingSpace() throws {
        let claude = state(count: 3)
        var card = ProviderCard(
            provider: .claude, state: claude, panelStyle: .rings, showProviderTitle: true,
            showHourlyPace: true, paces: paces(claude))
        let all = try render(card.frame(width: 240), maximumHeight: 420)
        card.hiddenClaudeWindows = [.weekly]
        let filtered = try render(card.frame(width: 240), maximumHeight: 300)
        XCTAssertLessThan(filtered.size.height, all.size.height - 50)
    }

    func testZeroAndFullRingsHaveDistinctRenderedBalances() throws {
        let empty = try render(QuotaRing(remainingPercentage: 0, tint: .blue), maximumHeight: 70)
        let full = try render(QuotaRing(remainingPercentage: 100, tint: .blue), maximumHeight: 70)
        XCTAssertEqual(empty.size.width, Theme.Layout.quotaRingDiameter, accuracy: 1)
        XCTAssertEqual(full.size.width, Theme.Layout.quotaRingDiameter, accuracy: 1)
        XCTAssertGreaterThan(bluePixelCount(full), bluePixelCount(empty) + 100)
    }

    func testAdaptiveRingCardsRenderEveryWindowCountWithinThePanelHeight() throws {
        let width = Theme.Layout.ringPanelWidth - Theme.Layout.panelPadding * 2
        try withEachLanguage { _ in
            for count in 1...3 {
                let state = state(count: count)
                let claude = ProviderCard(
                    provider: .claude, state: state, panelStyle: .rings, showProviderTitle: true,
                    showHourlyPace: true, paces: paces(state))
                let bitmap = try render(claude.frame(width: width), maximumHeight: Theme.Layout.maximumPanelHeight)
                XCTAssertEqual(bitmap.size.width, width, accuracy: 1)
            }
            for count in 1...2 {
                let state = codexState(count: count)
                let codex = ProviderCard(
                    provider: .codex, state: state, panelStyle: .rings, showProviderTitle: true,
                    showHourlyPace: true, paces: paces(state))
                let bitmap = try render(codex.frame(width: width), maximumHeight: Theme.Layout.maximumPanelHeight)
                XCTAssertEqual(bitmap.size.width, width, accuracy: 1)
            }
        }
    }

    func testThreeWindowIndividualCardFallsBackToRowsAndStaysOnOneColumn() throws {
        let cardWidth = Theme.Layout.ringPanelWidth - Theme.Layout.panelPadding * 2
        let available = cardWidth - Theme.Layout.cardPadding * 2
        XCTAssertEqual(QuotaRingLayout.choose(availableWidth: available, windows: 3), .rows)
        XCTAssertEqual(QuotaRingLayout.choose(availableWidth: available, windows: 2), .grid(columns: 2))
        let claude = state(count: 3)
        let card = ProviderCard(
            provider: .claude, state: claude, panelStyle: .rings, showProviderTitle: true,
            showHourlyPace: true, paces: paces(claude))
        let rows = try render(card.frame(width: cardWidth), maximumHeight: Theme.Layout.maximumPanelHeight)
        let grid = try render(
            card.frame(width: QuotaRingLayout.minimumGridWidth(windows: 3) + Theme.Layout.cardPadding * 2),
            maximumHeight: Theme.Layout.maximumPanelHeight)
        XCTAssertGreaterThan(rows.size.height, grid.size.height)
    }

    func testUnifiedRingCardsShareOneHeight() throws {
        let available = Theme.Layout.ringUnifiedWidth - Theme.Layout.panelPadding * 2 - Theme.Layout.quotaRingSpacing
        let balanced = QuotaRingLayout.minimumGridWidth(windows: 2) * 2 + Theme.Layout.cardPadding * 4
        let matrix: [(Int, Int, CGFloat, CGFloat)] = [
            (1, 3, Theme.Layout.minimumRingCardWidth, available - Theme.Layout.minimumRingCardWidth),
            (2, 2, balanced / 2, balanced / 2),
        ]
        for (codexWindows, claudeWindows, codexWidth, claudeWidth) in matrix {
            let codexState = codexState(count: codexWindows)
            let claudeState = state(count: claudeWindows)
            let codex = ProviderCard(
                provider: .codex, state: codexState, panelStyle: .rings,
                showProviderTitle: true, showHourlyPace: true, stretchesHeight: true, paces: paces(codexState))
            let claude = ProviderCard(
                provider: .claude, state: claudeState, panelStyle: .rings,
                showProviderTitle: true, showHourlyPace: true, stretchesHeight: true, paces: paces(claudeState))
            let row = HStack(alignment: .top, spacing: Theme.Layout.quotaRingSpacing) {
                codex.frame(width: codexWidth)
                claude.frame(width: claudeWidth)
            }
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light)
            .background(Color.white)
            let bitmap = try render(row, maximumHeight: Theme.Layout.maximumPanelHeight)
            let tall = try render(claude.frame(width: claudeWidth), maximumHeight: Theme.Layout.maximumPanelHeight)
            XCTAssertEqual(bitmap.size.height, max(bitmap.size.height, tall.size.height), accuracy: 1)
            let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
            let bottom = bitmap.pixelsHigh - Int(4 * scale)
            let card = try XCTUnwrap(
                bitmap.colorAt(x: Int(codexWidth / 2 * scale), y: bottom)?.usingColorSpace(.deviceRGB))
            let gap = try XCTUnwrap(
                bitmap.colorAt(x: Int((codexWidth + Theme.Layout.quotaRingSpacing / 2) * scale), y: bottom)?
                    .usingColorSpace(.deviceRGB))
            XCTAssertLessThan(card.redComponent, gap.redComponent - 0.005, "\(codexWindows) vs \(claudeWindows)")
        }
    }

    func testStandardCardsFitTheProviderAreaWithoutScrolling() throws {
        let available = Theme.Layout.unifiedPanelWidth - Theme.Layout.panelPadding * 2
        let cardWidth = (available - 10) / 2
        try withEachLanguage { language in
            let codexState = codexState(count: 2)
            let claudeState = state(count: 3)
            let codex = ProviderCard(
                provider: .codex, state: codexState, showProviderTitle: true, showHourlyPace: true,
                paces: paces(codexState))
            let claude = ProviderCard(
                provider: .claude, state: claudeState, showProviderTitle: true, showHourlyPace: true,
                paces: paces(claudeState))
            let unified = HStack(alignment: .top, spacing: 10) {
                codex.frame(width: cardWidth)
                claude.frame(width: cardWidth)
            }
            .fixedSize(horizontal: false, vertical: true)
            XCTAssertLessThanOrEqual(
                fittingSize(unified).height, Theme.Layout.providerMaxHeight, language.rawValue)
            let single = ProviderCard(
                provider: .claude, state: claudeState, showHourlyPace: true, paces: paces(claudeState))
            XCTAssertLessThanOrEqual(
                fittingSize(single.frame(width: Theme.Layout.panelWidth - Theme.Layout.panelPadding * 2)).height,
                Theme.Layout.providerMaxHeight, language.rawValue)
        }
    }

    func testStandardPanelWithLargestProviderCardsStaysWithinTheMaximumHeight() throws {
        try withDefaults { defaults in
            let store = Fixture.store(
                defaults: defaults,
                snapshots: [codexState(count: 2).snapshot, state(count: 3).snapshot].compactMap { $0 })
            store.panelStyle = .standard
            store.showHourlyPace = true
            try withEachLanguage { language in
                for mode in UsageDisplayMode.allCases {
                    store.displayMode = mode
                    let size = fittingSize(PopoverView(store: store, showSettings: {}, showAbout: {}))
                    XCTAssertLessThanOrEqual(
                        size.height, Theme.Layout.maximumPanelHeight, "\(language.rawValue) / \(mode.rawValue)")
                }
            }
        }
    }

    private func bluePixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent > color.redComponent + 0.3 && color.alphaComponent > 0.5 { count += 1 }
            }
        }
        return count
    }

    private func state(count: Int, status: ProviderStatus = .ready) -> ProviderViewState {
        let windows = [
            Fixture.window(
                id: "five_hour", usedPercentage: 2, resetsAt: Date().addingTimeInterval(7200),
                durationMinutes: 300),
            Fixture.window(
                id: "seven_day", usedPercentage: 25, resetsAt: Date().addingTimeInterval(172800),
                durationMinutes: 10080),
            Fixture.window(
                id: "seven_day_fable", usedPercentage: 88, resetsAt: Date().addingTimeInterval(172800),
                durationMinutes: 10080, displayName: "Fable"),
        ]
        let snapshot = Fixture.snapshot(
            .claude, windows: Array(windows.prefix(count)), availableResetCredits: 2,
            capturedAt: Date().addingTimeInterval(-600),
            modelBuckets: Fixture.modelBuckets([
                ("claude-opus-4-6", 171_600_000), ("claude-fable-1", 67_900_000),
                ("claude-haiku-4-5", 1_100_000),
            ]))
        return ProviderViewState(snapshot: snapshot, status: status, isRefreshing: false)
    }

    private func codexState(count: Int, status: ProviderStatus = .ready) -> ProviderViewState {
        let windows = [
            Fixture.window(
                id: "codex.weekly", usedPercentage: 41, resetsAt: Date().addingTimeInterval(172800),
                durationMinutes: 10080),
            Fixture.window(
                id: "base_model_inference.weekly", usedPercentage: 12,
                resetsAt: Date().addingTimeInterval(172800), durationMinutes: 10080, displayName: "gpt-reserve"),
        ]
        let snapshot = Fixture.snapshot(
            .codex, windows: Array(windows.prefix(count)), capturedAt: Date().addingTimeInterval(-600),
            modelBuckets: Fixture.modelBuckets([("gpt-6-astra", 148_300_000), ("gpt-6-codex", 52_400_000)]))
        return ProviderViewState(snapshot: snapshot, status: status, isRefreshing: false)
    }

    private func paces(_ state: ProviderViewState) -> [String: QuotaPace] {
        var result: [String: QuotaPace] = [:]
        for window in state.snapshot?.windows ?? [] {
            result[window.id] = Fixture.pace(15.6, resetsAt: window.resetsAt)
        }
        return result
    }
}
