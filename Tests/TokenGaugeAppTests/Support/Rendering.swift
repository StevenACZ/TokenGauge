import AppKit
import SwiftUI
import XCTest

@testable import TokenGaugeApp

@MainActor
func withCurrentLanguage(_ body: () throws -> Void) rethrows {
    let language = LocalizationManager.shared.language
    defer { LocalizationManager.shared.language = language }
    try body()
}

@MainActor
func fittingSize(_ content: some View) -> NSSize {
    NSHostingView(rootView: content.environment(\.quotaAnimationsEnabled, false)).fittingSize
}

@MainActor
func render(_ content: some View, maximumHeight: CGFloat? = nil) throws -> NSBitmapImageRep {
    let view = NSHostingView(rootView: content.environment(\.quotaAnimationsEnabled, false))
    let size = view.fittingSize
    if let maximumHeight { XCTAssertLessThanOrEqual(size.height, maximumHeight) }
    view.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    defer { window.contentView = nil }
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

@MainActor
@discardableResult
func render(_ content: some View, to output: URL, maximumHeight: CGFloat = Theme.Layout.maximumPanelHeight) throws
    -> NSSize
{
    let application = NSApplication.shared
    let previousAppearance = application.appearance
    application.appearance = NSAppearance(named: .darkAqua)
    defer { application.appearance = previousAppearance }
    let view = NSHostingView(
        rootView: content.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
    view.appearance = NSAppearance(named: .darkAqua)
    let size = view.fittingSize
    XCTAssertGreaterThan(size.width, 200)
    XCTAssertLessThanOrEqual(size.height, maximumHeight)
    view.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .windowBackgroundColor
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.appearance?.performAsCurrentDrawingAppearance {
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: output)
    window.contentView = nil
    return size
}
