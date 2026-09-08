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
        XCTAssertTrue(presentation.accessibilityLabel.contains("Claude Code"))
        let title = presentation.attributedTitle()
        var attachments = [NSTextAttachment]()
        title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }
        XCTAssertEqual(attachments.count, 1)
        XCTAssertNotNil(attachments.first?.image)
        XCTAssertEqual(attachments.first?.bounds.width, 18)
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
