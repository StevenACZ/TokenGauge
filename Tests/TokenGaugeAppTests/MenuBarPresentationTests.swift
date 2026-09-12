import AppKit
import TokenGaugeCore
import XCTest

@testable import TokenGaugeApp

final class MenuBarPresentationTests: XCTestCase {
    @MainActor func testUnifiedKeepsHealthyQuotaWhenOtherProviderIsCancelled() {
        let presentation = MenuBarPresentation(
            providers: UsageDisplayMode.unified.providers,
            state: { provider in
                self.state(provider: provider, status: provider == .codex ? .ready : .cancelled)
            }, appearance: NSAppearance(named: .darkAqua)!)
        XCTAssertEqual(presentation.segments.map(\.provider), [.codex, .claude])
        XCTAssertEqual(presentation.segments.map(\.text), ["20%", "--"])
        XCTAssertTrue(presentation.accessibilityLabel.contains("Codex"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("Claude"))
        XCTAssertFalse(presentation.accessibilityLabel.contains("Claude Code"))
        let title = presentation.attributedTitle()
        var attachments = [NSTextAttachment]()
        title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }
        XCTAssertEqual(attachments.count, 1)
        XCTAssertNotNil(attachments.first?.image)
        XCTAssertEqual(attachments.first?.bounds.width, 17)
        XCTAssertTrue(title.string.contains("20%"))
        XCTAssertTrue(title.string.hasSuffix("--"))
    }

    @MainActor func testSingleProviderHasNoOtherProviderAttachmentOrLabel() {
        let presentation = MenuBarPresentation(
            providers: UsageDisplayMode.claude.providers,
            state: { self.state(provider: $0, status: .ready) },
            appearance: NSAppearance(named: .aqua)!)
        XCTAssertEqual(presentation.segments.map(\.provider), [.claude])
        XCTAssertFalse(presentation.accessibilityLabel.contains("Codex"))
        XCTAssertEqual(presentation.attributedTitle().string, " 60%")
    }

    @MainActor func testCacheChangesWhenResolvedAppearanceChanges() {
        let state: (UsageProvider) -> ProviderViewState = { self.state(provider: $0, status: .ready) }
        let light = MenuBarPresentation(providers: [.claude], state: state, appearance: NSAppearance(named: .aqua)!)
        let same = MenuBarPresentation(providers: [.claude], state: state, appearance: NSAppearance(named: .aqua)!)
        let dark = MenuBarPresentation(providers: [.claude], state: state, appearance: NSAppearance(named: .darkAqua)!)
        XCTAssertEqual(light, same)
        XCTAssertNotEqual(light, dark)
    }

    @MainActor func testSizeChangesInvalidateCacheWithoutChangingQuotaOrAccessibility() throws {
        let state: (UsageProvider) -> ProviderViewState = { self.state(provider: $0, status: .ready) }
        let appearance = NSAppearance(named: .aqua)!
        let large = MenuBarPresentation(providers: [.codex, .claude], state: state, appearance: appearance)
        let sizes: [(MenuBarSize, CGFloat, CGFloat)] = [(.large, 17, 13.5), (.medium, 15.5, 12.5), (.small, 13.5, 11)]
        var previous: MenuBarPresentation?
        for (size, iconSize, fontSize) in sizes {
            let presentation = MenuBarPresentation(
                providers: [.codex, .claude], state: state, appearance: appearance, size: size)
            let same = MenuBarPresentation(
                providers: [.codex, .claude], state: state, appearance: appearance, size: size)
            XCTAssertEqual(presentation, same)
            XCTAssertEqual(presentation.segments, large.segments)
            XCTAssertEqual(presentation.accessibilityLabel, large.accessibilityLabel)
            if let previous { XCTAssertNotEqual(presentation, previous) }
            let title = presentation.attributedTitle()
            let font = try XCTUnwrap(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.pointSize, fontSize)
            var attachments = [NSTextAttachment]()
            title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
                if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
            }
            let attachment = try XCTUnwrap(attachments.first)
            XCTAssertEqual(attachments.count, 1)
            XCTAssertEqual(attachment.bounds.size, NSSize(width: iconSize, height: iconSize))
            XCTAssertNotNil(attachment.image)
            previous = presentation
        }
    }

    @MainActor func testStylesInvalidateCacheAndKeepExactQuotaDescription() {
        let state: (UsageProvider) -> ProviderViewState = { self.state(provider: $0, status: .ready) }
        let appearance = NSAppearance(named: .aqua)!
        let numbers = MenuBarPresentation(providers: [.codex, .claude], state: state, appearance: appearance)
        for style in [QuotaMenuBarStyle.bars, .rings] {
            let presentation = MenuBarPresentation(
                providers: [.codex, .claude], state: state, appearance: appearance, style: style)
            XCTAssertNotEqual(presentation, numbers)
            XCTAssertEqual(presentation.accessibilityLabel, numbers.accessibilityLabel)
            XCTAssertTrue(presentation.accessibilityLabel.contains("20%"))
            XCTAssertTrue(presentation.accessibilityLabel.contains("60%"))
            let title = presentation.attributedTitle()
            XCTAssertFalse(title.string.contains("%"))
            var attachmentCount = 0
            title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
                if value is NSTextAttachment { attachmentCount += 1 }
            }
            XCTAssertEqual(attachmentCount, 3)
        }
    }

    @MainActor func testGraphicDimensionsAndFillAreProportionalInEverySizeAndAppearance() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            for size in MenuBarSize.allCases {
                for style in [QuotaMenuBarStyle.bars, .rings] {
                    var images = [NSImage]()
                    for used in [100.0, 50.0, 0.0] {
                        let presentation = MenuBarPresentation(
                            providers: [.codex],
                            state: { self.state(provider: $0, status: .ready, usedPercentage: used) },
                            appearance: NSAppearance(named: appearanceName)!, size: size, style: style)
                        images.append(try XCTUnwrap(presentation.quotaImage(for: presentation.segments[0])))
                    }
                    let expected = NSSize(
                        width: style == .bars ? size.iconSize * 1.8 : size.iconSize, height: size.iconSize)
                    XCTAssertTrue(images.allSatisfy { $0.size == expected && !$0.isTemplate })
                    let ink = try images.map { try blueInk($0) }
                    XCTAssertLessThan(ink[0], ink[2] * 0.05)
                    XCTAssertGreaterThan(ink[2], 0)
                    XCTAssertEqual(ink[1] / ink[2], 0.5, accuracy: 0.12)
                }
            }
        }
    }

    @MainActor func testGraphicsNeverRepresentUnavailableOrStaleBalances() {
        for style in [QuotaMenuBarStyle.bars, .rings] {
            for status in [ProviderStatus.unavailable, .stale, .authenticationRequired, .credentialExpired, .cancelled]
            {
                let presentation = MenuBarPresentation(
                    providers: [.claude], state: { self.state(provider: $0, status: status) },
                    appearance: NSAppearance(named: .aqua)!, style: style)
                XCTAssertEqual(presentation.attributedTitle().string, " --")
                XCTAssertNil(presentation.segments[0].remainingPercentage)
                XCTAssertNil(presentation.quotaImage(for: presentation.segments[0]))
                XCTAssertFalse(presentation.accessibilityLabel.contains("%"))
            }
        }
    }

    @MainActor func testFractionalQuotaChangeInvalidatesGraphicCacheEvenWhenRoundedTextMatches() {
        let appearance = NSAppearance(named: .aqua)!
        let first = MenuBarPresentation(
            providers: [.codex], state: { self.state(provider: $0, status: .ready, usedPercentage: 40.1) },
            appearance: appearance, style: .bars)
        let second = MenuBarPresentation(
            providers: [.codex], state: { self.state(provider: $0, status: .ready, usedPercentage: 40.2) },
            appearance: appearance, style: .bars)
        XCTAssertEqual(first.segments[0].text, second.segments[0].text)
        XCTAssertNotEqual(first, second)
    }

    @MainActor func testEveryStyleRespectsSelectedClaudeWindowWithoutSubstitutingMissingModel() {
        let state: (UsageProvider) -> ProviderViewState = { self.state(provider: $0, status: .ready) }
        for style in QuotaMenuBarStyle.allCases {
            let weekly = MenuBarPresentation(
                providers: [.claude], state: state, appearance: NSAppearance(named: .aqua)!,
                style: style, claudeSource: .weekly)
            let missingModel = MenuBarPresentation(
                providers: [.claude], state: state, appearance: NSAppearance(named: .aqua)!,
                style: style, claudeSource: .modelWeekly)
            XCTAssertEqual(weekly.segments[0].remainingPercentage, 60)
            XCTAssertNil(missingModel.segments[0].remainingPercentage)
            XCTAssertEqual(missingModel.attributedTitle().string, " --")
        }
    }

    @MainActor private func blueInk(_ image: NSImage) throws -> Double {
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        var total = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                total += max(0, color.blueComponent - color.redComponent) * color.alphaComponent
            }
        }
        return total
    }

    private func state(provider: UsageProvider, status: ProviderStatus, usedPercentage: Double? = nil)
        -> ProviderViewState
    {
        let window = QuotaWindow(
            id: provider == .codex ? "codex.primary" : "seven_day",
            usedPercentage: usedPercentage ?? (provider == .codex ? 80 : 40),
            resetsAt: Date().addingTimeInterval(86_400), durationMinutes: 10_080, displayName: nil)
        let snapshot = ProviderUsageSnapshot(
            provider: provider, windows: [window], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
        return ProviderViewState(snapshot: snapshot, status: status, isRefreshing: false)
    }
}
