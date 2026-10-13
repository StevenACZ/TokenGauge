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

    @MainActor func testStylesInvalidateCacheAndKeepExactQuotaDescription() throws {
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
            XCTAssertEqual(attachmentCount, style == .rings ? 2 : 3)
            if style == .rings {
                for segment in presentation.segments {
                    let image = try XCTUnwrap(presentation.quotaImage(for: segment))
                    XCTAssertGreaterThan(try centerOpacity(image), 1)
                }
            }
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
                    let diameter = min(22, size.iconSize + 5)
                    let expected =
                        style == .bars
                        ? NSSize(width: size.iconSize * 1.8, height: size.iconSize)
                        : NSSize(width: diameter, height: diameter)
                    XCTAssertTrue(images.allSatisfy { $0.size == expected && !$0.isTemplate })
                    let ink = try images.map { try blueInk($0, annulusOnly: style == .rings) }
                    if style == .rings {
                        for image in images { XCTAssertGreaterThan(try centerOpacity(image), 1) }
                    }
                    XCTAssertLessThan(ink[0], ink[2] * 0.05)
                    XCTAssertGreaterThan(ink[2], 0)
                    XCTAssertEqual(ink[1] / ink[2], 0.5, accuracy: 0.12)
                }
            }
        }
    }

    @MainActor func testAnExhaustedQuotaDrawsASolidRedGraphic() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            for style in [QuotaMenuBarStyle.bars, .rings] {
                var redInk = [Double]()
                for used in [100.0, 95.0] {
                    let presentation = MenuBarPresentation(
                        providers: [.codex], state: { self.state(provider: $0, status: .ready, usedPercentage: used) },
                        appearance: NSAppearance(named: appearanceName)!, style: style)
                    redInk.append(try opaqueRedInk(XCTUnwrap(presentation.quotaImage(for: presentation.segments[0]))))
                }
                XCTAssertGreaterThan(redInk[0], 10, "\(appearanceName.rawValue) \(style)")
                XCTAssertEqual(redInk[1], 0, "a low quota keeps its own color: \(appearanceName.rawValue) \(style)")
                let spent = MenuBarPresentation(
                    providers: [.codex], state: { self.state(provider: $0, status: .ready, usedPercentage: 100) },
                    appearance: NSAppearance(named: appearanceName)!, style: style,
                    accounts: [
                        .init(id: UUID(), name: "Side", tint: .teal, icon: .letter, letter: "S", remaining: 0),
                        .init(id: UUID(), name: "Team", tint: .pink, icon: .letter, letter: "T", remaining: 5),
                    ])
                XCTAssertEqual(spent.groups.map(spent.isSpent), [true, true, false])
                XCTAssertTrue(spent.leadingSpent)
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
                let title = presentation.attributedTitle()
                XCTAssertTrue(title.string.hasSuffix(" --"))
                if style == .rings {
                    XCTAssertNotNil(title.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
                    XCTAssertTrue(presentation.accessibilityLabel.contains("Claude"))
                }
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
                style: style, selection: [.claude: [.weekly]])
            let missingModel = MenuBarPresentation(
                providers: [.claude], state: state, appearance: NSAppearance(named: .aqua)!,
                style: style, selection: [.claude: [.modelWeekly]])
            XCTAssertEqual(weekly.segments[0].remainingPercentage, 60)
            XCTAssertNil(missingModel.segments[0].remainingPercentage)
            XCTAssertTrue(missingModel.attributedTitle().string.hasSuffix(" --"))
        }
    }

    @MainActor private func blueInk(_ image: NSImage, annulusOnly: Bool) throws -> Double {
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        var total = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let pointX = (Double(x) + 0.5) * image.size.width / Double(bitmap.pixelsWide) - image.size.width / 2
                let pointY = (Double(y) + 0.5) * image.size.height / Double(bitmap.pixelsHigh) - image.size.height / 2
                if annulusOnly && hypot(pointX, pointY) < image.size.width / 2 - 2.2 { continue }
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                total += max(0, color.blueComponent - color.redComponent) * color.alphaComponent
            }
        }
        return total
    }

    @MainActor private func opaqueRedInk(_ image: NSImage) throws -> Double {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        var total = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.alphaComponent > 0.4, color.redComponent - color.blueComponent > 0.25,
                    color.redComponent - color.greenComponent > 0.25
                {
                    total += 1
                }
            }
        }
        return total
    }

    @MainActor private func centerOpacity(_ image: NSImage) throws -> Double {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        var opacity = 0.0
        for y in (bitmap.pixelsHigh / 3)..<(bitmap.pixelsHigh * 2 / 3) {
            for x in (bitmap.pixelsWide / 3)..<(bitmap.pixelsWide * 2 / 3) {
                opacity += try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
            }
        }
        return opacity
    }

    @MainActor func testExtraAccountsFollowClaudeAsTheirOwnGroups() {
        let work = MenuBarPresentation.Account(
            id: UUID(), name: "Work", tint: .violet, icon: .balloon, remaining: 37)
        let idle = MenuBarPresentation.Account(id: UUID(), name: "", tint: .claude, remaining: nil)
        let presentation = MenuBarPresentation(
            providers: [.claude], state: { self.state(provider: $0, status: .ready) },
            appearance: NSAppearance(named: .aqua)!, style: .bars, accounts: [work, idle])
        XCTAssertEqual(presentation.segments.map(\.text), ["60%", "37%", "--"])
        XCTAssertEqual(presentation.groups.count, 3)
        XCTAssertEqual(presentation.groups[1].first?.account, work.id)
        XCTAssertEqual(presentation.groups[1].first?.icon, .balloon)
        XCTAssertNil(presentation.groups[2].first?.icon)
        XCTAssertNotNil(AccountIconArt.image(.balloon, color: .systemPurple, size: 16))
        XCTAssertTrue(presentation.accessibilityLabel.contains("Work"))
        XCTAssertTrue(presentation.attributedTitle().string.hasSuffix("--"))
    }

    @MainActor func testAnAccountCanBeMarkedByItsInitial() throws {
        let side = MenuBarPresentation.Account(
            id: UUID(), name: "Side", tint: .teal, icon: .letter, letter: "S", remaining: 80)
        for style in QuotaMenuBarStyle.allCases {
            let presentation = MenuBarPresentation(
                providers: [.claude], state: { self.state(provider: $0, status: .ready) },
                appearance: NSAppearance(named: .aqua)!, style: style, accounts: [side])
            XCTAssertEqual(presentation.groups[1].first?.letter, "S")
            XCTAssertGreaterThan(presentation.renderedImage().size.width, 40, "\(style)")
        }
        let mark = AccountIconArt.letterImage("S", color: .systemTeal, size: 16)
        XCTAssertGreaterThan(try centerOpacity(mark), 0)
    }

    @MainActor func testRingKeepsTheAccountInitialUnstretchedAndCentered() throws {
        XCTAssertEqual(
            MenuBarPresentation.centered(NSSize(width: 6, height: 14), fitting: 14, in: 22),
            NSRect(x: 8, y: 4, width: 6, height: 14))
        XCTAssertEqual(
            MenuBarPresentation.centered(NSSize(width: 28, height: 14), fitting: 14, in: 22),
            NSRect(x: 4, y: 7.5, width: 14, height: 7))
        for letter in ["H", "S", "I", "W"] {
            let account = MenuBarPresentation.Account(
                id: UUID(), name: letter, tint: .teal, icon: .letter, letter: letter, remaining: 0)
            let presentation = MenuBarPresentation(
                providers: [.claude], state: { self.state(provider: $0, status: .ready) },
                appearance: NSAppearance(named: .aqua)!, style: .rings, accounts: [account])
            let segment = try XCTUnwrap(presentation.segments.last)
            let ring = try XCTUnwrap(presentation.quotaImage(for: segment))
            let ink = try inkBounds(ring) { $0.greenComponent > $0.redComponent && $0.alphaComponent > 0.2 }
            XCTAssertEqual(ink.midX, ring.size.width / 2, accuracy: 0.75, letter)
            XCTAssertEqual(ink.midY, ring.size.height / 2, accuracy: 0.75, letter)
            let natural = try inkBounds(AccountIconArt.letterImage(letter, color: .systemTeal, size: 14)) {
                $0.alphaComponent > 0.5
            }
            XCTAssertEqual(ink.width / ink.height, natural.width / natural.height, accuracy: 0.12, letter)
        }
    }

    private func inkBounds(_ image: NSImage, where matches: (NSColor) -> Bool) throws -> CGRect {
        let scale: CGFloat = 8
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var columns = [Int]()
        var rows = [Int]()
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y), matches(color) else { continue }
                columns.append(x)
                rows.append(y)
            }
        }
        let left = try XCTUnwrap(columns.min())
        let top = try XCTUnwrap(rows.min())
        return CGRect(
            x: CGFloat(left) / scale, y: CGFloat(top) / scale,
            width: CGFloat(try XCTUnwrap(columns.max()) - left + 1) / scale,
            height: CGFloat(try XCTUnwrap(rows.max()) - top + 1) / scale)
    }

    private func state(provider: UsageProvider, status: ProviderStatus, usedPercentage: Double? = nil)
        -> ProviderViewState
    {
        let window = Fixture.window(
            id: provider == .codex ? "codex.primary" : "seven_day",
            usedPercentage: usedPercentage ?? (provider == .codex ? 80 : 40),
            resetsAt: Date().addingTimeInterval(86_400), durationMinutes: 10_080)
        let snapshot = Fixture.snapshot(provider, windows: [window])
        return ProviderViewState(snapshot: snapshot, status: status, isRefreshing: false)
    }
}
