import AppKit
import SwiftUI
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

@MainActor
final class QuotaPanelRenderingTests: XCTestCase {
    func testNewStylesRenderOneTwoAndThreeWindowsAtSupportedWidths() throws {
        let originalLanguage = LocalizationManager.shared.language
        defer { LocalizationManager.shared.language = originalLanguage }
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
            for style in [QuotaPanelStyle.compact, .rings] {
                for count in 1...3 {
                    for width: CGFloat in style == .rings ? [240, 334] : [334, 414] {
                        let card = ProviderCard(
                            provider: .claude, state: state(count: count), panelStyle: style, showProviderTitle: true)
                        let bitmap = try render(card.frame(width: width), maximumHeight: 420)
                        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                        XCTAssertEqual(bitmap.size.width, width, accuracy: 1)
                    }
                }
            }
        }
    }

    func testCompactOneAndTwoWindowCardsStayBelowCombinedHeightBudget() throws {
        let originalLanguage = LocalizationManager.shared.language
        defer { LocalizationManager.shared.language = originalLanguage }
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
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
        let originalLanguage = LocalizationManager.shared.language
        defer { LocalizationManager.shared.language = originalLanguage }
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
            for (count, width) in [(2, CGFloat(194)), (3, CGFloat(290))] {
                let card = ProviderCard(
                    provider: .claude, state: state(count: count), panelStyle: .rings, showProviderTitle: true)
                let bitmap = try render(card.frame(width: width), maximumHeight: 195)
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
        var card = ProviderCard(
            provider: .claude, state: state(count: 3), panelStyle: .rings, showProviderTitle: true)
        let all = try render(card.frame(width: 240), maximumHeight: 320)
        card.hiddenClaudeWindows = [.weekly]
        let filtered = try render(card.frame(width: 240), maximumHeight: 190)
        XCTAssertLessThan(filtered.size.height, all.size.height - 100)
    }

    func testZeroAndFullRingsHaveDistinctRenderedBalances() throws {
        let empty = try render(QuotaRing(remainingPercentage: 0, tint: .blue), maximumHeight: 70)
        let full = try render(QuotaRing(remainingPercentage: 100, tint: .blue), maximumHeight: 70)
        XCTAssertEqual(empty.size.width, Theme.Layout.quotaRingDiameter, accuracy: 1)
        XCTAssertEqual(full.size.width, Theme.Layout.quotaRingDiameter, accuracy: 1)
        XCTAssertGreaterThan(bluePixelCount(full), bluePixelCount(empty) + 100)
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
            QuotaWindow(
                id: "five_hour", usedPercentage: 2, resetsAt: Date().addingTimeInterval(7200),
                durationMinutes: 300, displayName: nil),
            QuotaWindow(
                id: "seven_day", usedPercentage: 25, resetsAt: Date().addingTimeInterval(172800),
                durationMinutes: 10080, displayName: nil),
            QuotaWindow(
                id: "seven_day_fable", usedPercentage: 88, resetsAt: Date().addingTimeInterval(172800),
                durationMinutes: 10080, displayName: "Fable"),
        ]
        let snapshot = ProviderUsageSnapshot(
            provider: .claude, windows: Array(windows.prefix(count)), dailyUsage: [], summary: nil,
            availableResetCredits: 2, creditBalance: nil, capturedAt: Date().addingTimeInterval(-600))
        return ProviderViewState(snapshot: snapshot, status: status, isRefreshing: false)
    }

    private func render(_ content: some View, maximumHeight: CGFloat) throws -> NSBitmapImageRep {
        let view = NSHostingView(rootView: content.environment(\.quotaAnimationsEnabled, false))
        let size = view.fittingSize
        XCTAssertLessThanOrEqual(size.height, maximumHeight)
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
}
