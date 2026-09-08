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

    private func state(provider: UsageProvider, status: ProviderStatus) -> ProviderViewState {
        let window = QuotaWindow(
            id: provider == .codex ? "codex.primary" : "seven_day",
            usedPercentage: provider == .codex ? 80 : 40,
            resetsAt: Date().addingTimeInterval(86_400), durationMinutes: 10_080, displayName: nil)
        let snapshot = ProviderUsageSnapshot(
            provider: provider, windows: [window], dailyUsage: [], summary: nil,
            availableResetCredits: nil, creditBalance: nil, capturedAt: Date())
        return ProviderViewState(snapshot: snapshot, status: status, isRefreshing: false)
    }
}
