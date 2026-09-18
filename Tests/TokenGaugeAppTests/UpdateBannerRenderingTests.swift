import AppKit
import SwiftUI
import XCTest

@testable import TokenGaugeApp

@MainActor
final class UpdateBannerRenderingTests: XCTestCase {

    private let phases: [UpdateManager.Phase] = [
        .checking,
        .available(version: "1.4.0"),
        .downloading(version: "1.4.0", fraction: nil),
        .downloading(version: "1.4.0", fraction: 0.43),
        .extracting(version: "1.4.0", fraction: 0.6),
        .readyToInstall(version: "1.4.0", deferred: false),
        .readyToInstall(version: "1.4.0", deferred: true),
        .installing(version: "1.4.0"),
        .failed(message: UpdateManager.failureMessageKey),
    ]

    func testEveryBannerStateKeepsItsDeclaredHeight() throws {
        let language = LocalizationManager.shared.language
        defer { LocalizationManager.shared.language = language }
        for language in AppLanguage.allCases {
            LocalizationManager.shared.language = language
            for phase in phases {
                let manager = try makeManager(phase: phase)
                let view = NSHostingView(
                    rootView: UpdateBannerView(updates: manager).frame(width: Theme.Layout.panelWidth))
                XCTAssertEqual(
                    view.fittingSize.height, UpdateBannerView.height(for: phase), accuracy: 1,
                    "\(language.rawValue) / \(phase)")
                XCTAssertEqual(view.fittingSize.width, Theme.Layout.panelWidth, accuracy: 1)
            }
        }
    }

    func testIdleBannerRendersNothing() throws {
        let manager = try makeManager(phase: .idle)
        let view = NSHostingView(rootView: UpdateBannerView(updates: manager))

        XCTAssertEqual(UpdateBannerView.height(for: .idle), 0)
        XCTAssertEqual(view.fittingSize.height, 0, accuracy: 1)
    }

    func testAboutKeepsTheManualCheckReachableOutsideARunningUpdate() throws {
        let check = try actionBitmap(phase: .idle)
        for phase in [
            UpdateManager.Phase.available(version: "1.4.0"), .readyToInstall(version: "1.4.0", deferred: true),
        ] {
            let bitmap = try actionBitmap(phase: phase)
            XCTAssertGreaterThan(bitmap.pixelsHigh, check.pixelsHigh, "\(phase)")
            XCTAssertTrue(endsWith(bitmap, check), "\(phase)")
        }
        let installing = try actionBitmap(phase: .installing(version: "1.4.0"))
        XCTAssertFalse(endsWith(installing, check))

        let idle = try actionHeight(phase: .idle)
        XCTAssertGreaterThan(idle, 0)
        XCTAssertLessThan(idle, UpdateBannerView.compactHeight)
        XCTAssertEqual(
            try actionHeight(phase: .installing(version: "1.4.0")), UpdateBannerView.compactHeight, accuracy: 1)
    }

    private func actionHeight(phase: UpdateManager.Phase) throws -> CGFloat {
        let manager = try makeManager(phase: phase)
        let view = NSHostingView(
            rootView: UpdateActionView(updates: manager).frame(width: Theme.Layout.panelWidth))
        return view.fittingSize.height
    }

    private func actionBitmap(phase: UpdateManager.Phase) throws -> NSBitmapImageRep {
        let manager = try makeManager(phase: phase)
        return try render(
            UpdateActionView(updates: manager).frame(width: Theme.Layout.panelWidth)
                .environment(\.colorScheme, .light).background(Color.white))
    }

    private func endsWith(_ bitmap: NSBitmapImageRep, _ tail: NSBitmapImageRep) -> Bool {
        guard bitmap.pixelsWide == tail.pixelsWide, bitmap.pixelsHigh >= tail.pixelsHigh else { return false }
        var different = 0
        for row in 0..<tail.pixelsHigh {
            for column in 0..<tail.pixelsWide {
                let left = bitmap.colorAt(x: column, y: bitmap.pixelsHigh - tail.pixelsHigh + row)?
                    .usingColorSpace(.deviceRGB)
                let right = tail.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB)
                guard let left, let right else { return false }
                if abs(left.redComponent - right.redComponent) > 0.1
                    || abs(left.greenComponent - right.greenComponent) > 0.1
                    || abs(left.blueComponent - right.blueComponent) > 0.1
                {
                    different += 1
                }
            }
        }
        return different * 100 < tail.pixelsWide * tail.pixelsHigh
    }

    private func makeManager(phase: UpdateManager.Phase) throws -> UpdateManager {
        let suite = "TokenGauge.banner.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let manager = UpdateManager(defaults: defaults)
        switch phase {
        case .idle:
            break
        case .checking:
            manager.handleManualCheckStarted()
        case .available(let version):
            _ = manager.handleUpdateFound(version: version, releasePage: nil, informationOnly: false)
        case .downloading(let version, let fraction):
            _ = manager.handleUpdateFound(version: version, releasePage: nil, informationOnly: false)
            manager.handleDownloadInitiated()
            if let fraction {
                manager.handleDownloadExpectedLength(1_000)
                manager.handleDownloadReceived(bytes: UInt64(fraction * 1_000))
            }
        case .extracting(let version, let fraction):
            _ = manager.handleUpdateFound(version: version, releasePage: nil, informationOnly: false)
            manager.handleExtractionStarted()
            if let fraction { manager.handleExtractionProgress(fraction) }
        case .readyToInstall(let version, let deferred):
            _ = manager.handleUpdateFound(version: version, releasePage: nil, informationOnly: false)
            manager.handleReadyToInstall { _ in }
            if deferred { manager.deferReadyUpdate() }
        case .installing(let version):
            _ = manager.handleUpdateFound(version: version, releasePage: nil, informationOnly: false)
            manager.handleInstalling()
        case .failed:
            _ = manager.handleUpdateFound(version: "1.4.0", releasePage: nil, informationOnly: false)
            manager.handleInstallRequested()
            manager.handleError("failure")
        }
        XCTAssertEqual(manager.phase, phase)
        return manager
    }
}
