import Sparkle
import XCTest

@testable import TokenGaugeApp

@MainActor
final class UpdateManagerTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000)

    private func makeManager() -> UpdateManager {
        UpdateManager(
            defaults: UserDefaults(suiteName: "TokenGauge.UpdaterTests." + UUID().uuidString)!,
            now: { [unowned self] in self.clock })
    }

    private func found(
        _ manager: UpdateManager, version: String = "9.9.9", informationOnly: Bool = false,
        stage: UpdateManager.Stage = .notDownloaded
    ) -> SPUUserUpdateChoice {
        manager.handleUpdateFound(
            version: version, releasePage: nil, informationOnly: informationOnly, stage: stage)
    }

    func testScheduledFoundUpdateIsDismissedAndSurfaced() {
        let manager = makeManager()
        let choice = manager.handleUpdateFound(
            version: "9.9.9",
            releasePage: URL(string: "https://example.com/release"),
            informationOnly: false
        )

        XCTAssertEqual(choice, .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
        XCTAssertEqual(manager.releasePageURL?.absoluteString, "https://example.com/release")
    }

    func testInformationOnlyUpdateNeverInstalls() {
        let manager = makeManager()
        manager.handleInstallRequested()

        XCTAssertEqual(found(manager, informationOnly: true), .dismiss)
        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testDownloadProgressIsFractionOfExpectedLength() {
        let manager = makeManager()
        _ = found(manager)
        manager.handleDownloadInitiated()
        XCTAssertEqual(manager.phase, .downloading(version: "9.9.9", fraction: nil))

        manager.handleDownloadExpectedLength(1_000)
        manager.handleDownloadReceived(bytes: 250)
        XCTAssertEqual(manager.phase, .downloading(version: "9.9.9", fraction: 0.25))

        manager.handleDownloadReceived(bytes: 750)
        XCTAssertEqual(manager.phase, .downloading(version: "9.9.9", fraction: 1.0))
    }

    func testUnknownContentLengthStaysIndeterminate() {
        let manager = makeManager()
        manager.handleDownloadInitiated()
        manager.handleDownloadReceived(bytes: 4_096)

        XCTAssertEqual(manager.phase, .downloading(version: "", fraction: nil))
    }

    func testDownloadFractionIsCappedAtOne() {
        let manager = makeManager()
        manager.handleDownloadInitiated()
        manager.handleDownloadExpectedLength(100)
        manager.handleDownloadReceived(bytes: 250)

        XCTAssertEqual(manager.phase, .downloading(version: "", fraction: 1.0))
    }

    func testProgressPublishesAtMostTwentyTimesPerSecond() {
        let manager = makeManager()
        _ = found(manager)
        manager.handleDownloadInitiated()
        manager.handleDownloadExpectedLength(1_000)

        manager.handleDownloadReceived(bytes: 100)
        XCTAssertEqual(manager.phase, .downloading(version: "9.9.9", fraction: 0.1))

        manager.handleDownloadReceived(bytes: 100)
        XCTAssertEqual(manager.phase, .downloading(version: "9.9.9", fraction: 0.1))

        clock.addTimeInterval(UpdateManager.progressPublishInterval * 2)
        manager.handleDownloadReceived(bytes: 100)
        XCTAssertEqual(manager.phase, .downloading(version: "9.9.9", fraction: 0.3))
    }

    func testExtractionProgressIsReported() {
        let manager = makeManager()
        _ = found(manager)
        manager.handleExtractionStarted()
        XCTAssertEqual(manager.phase, .extracting(version: "9.9.9", fraction: nil))

        manager.handleExtractionProgress(0.5)
        XCTAssertEqual(manager.phase, .extracting(version: "9.9.9", fraction: 0.5))

        manager.handleExtractionProgress(1.0)
        XCTAssertEqual(manager.phase, .extracting(version: "9.9.9", fraction: 1.0))
    }

    func testReadyToInstallWaitsForTheUserChoice() {
        let manager = makeManager()
        _ = found(manager)
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9", deferred: false))
        XCTAssertTrue(choices.isEmpty)

        manager.installReadyUpdate()

        XCTAssertEqual(choices, [.install])
        XCTAssertEqual(manager.phase, .installing(version: "9.9.9"))
    }

    func testDeferredReadyUpdateStaysVisibleAndResumesWithInstall() {
        let manager = makeManager()
        _ = found(manager)
        var choices: [SPUUserUpdateChoice] = []
        manager.handleReadyToInstall { choices.append($0) }

        manager.deferReadyUpdate()
        XCTAssertEqual(choices, [.dismiss])
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9", deferred: true))

        manager.handleDismissInstallation()
        XCTAssertEqual(manager.phase, .readyToInstall(version: "9.9.9", deferred: true))

        manager.resumeDeferredInstall()
        XCTAssertEqual(manager.phase, .installing(version: "9.9.9"))
        XCTAssertEqual(found(manager, stage: .downloaded), .install)

        manager.handleReadyToInstall { choices.append($0) }
        XCTAssertEqual(choices, [.dismiss, .install])
        XCTAssertEqual(manager.phase, .installing(version: "9.9.9"))
    }

    func testDownloadedStageWithoutInstallIntentSurfacesTheDeferredRow() {
        XCTAssertEqual(
            UpdateManager.decideUpdateFound(
                version: "1.4.0", stage: .downloaded, installRequested: false, informationOnly: false),
            UpdateManager.FoundDecision(
                choice: .dismiss, phase: .readyToInstall(version: "1.4.0", deferred: true)))
        XCTAssertEqual(
            UpdateManager.decideUpdateFound(
                version: "1.4.0", stage: .downloaded, installRequested: true, informationOnly: false),
            UpdateManager.FoundDecision(choice: .install, phase: .installing(version: "1.4.0")))
        XCTAssertEqual(
            UpdateManager.decideUpdateFound(
                version: "1.4.0", stage: .notDownloaded, installRequested: true, informationOnly: false),
            UpdateManager.FoundDecision(
                choice: .install, phase: .downloading(version: "1.4.0", fraction: nil)))
        XCTAssertEqual(
            UpdateManager.decideUpdateFound(
                version: "1.4.0", stage: .downloaded, installRequested: true, informationOnly: true),
            UpdateManager.FoundDecision(choice: .dismiss, phase: .available(version: "1.4.0")))
    }

    func testScheduledCheckErrorStaysSilent() {
        let manager = makeManager()
        XCTAssertEqual(found(manager), .dismiss)

        manager.handleError("network down")

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testScheduledCheckErrorWithNothingPendingIsIdle() {
        let manager = makeManager()
        manager.handleError("network down")

        XCTAssertEqual(manager.phase, .idle)
    }

    func testDismissDuringDownloadRollsBackToAvailable() {
        let manager = makeManager()
        _ = found(manager)
        manager.handleDownloadInitiated()

        manager.handleDismissInstallation()

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testDismissKeepsPendingRowAlive() {
        let manager = makeManager()
        _ = found(manager)

        manager.handleDismissInstallation()

        XCTAssertEqual(manager.phase, .available(version: "9.9.9"))
    }

    func testNotFoundClearsPendingState() {
        let manager = makeManager()
        _ = found(manager)

        manager.handleNotFound()

        XCTAssertEqual(manager.phase, .idle)
        XCTAssertNil(manager.releasePageURL)
    }

    func testCancelledInstallationCannotAuthorizeTheNextCheck() {
        let manager = makeManager()
        _ = found(manager, version: "1.0.1")
        manager.handleInstallRequested()
        XCTAssertEqual(found(manager, version: "1.0.1"), .install)
        manager.handleDismissInstallation()
        XCTAssertEqual(found(manager, version: "1.0.1"), .dismiss)
        manager.handleInstallRequested()
        XCTAssertEqual(found(manager, version: "1.0.1"), .install)
    }

    func testQAFeedRequiresExplicitOptInAndLoopback() {
        XCTAssertNil(
            UpdateManager.qaFeedURL(environment: ["TOKENGAUGE_UPDATE_FEED_URL": "http://localhost:8000/appcast.xml"]))
        for raw in [
            "https://github.com/feed", "http://localhost.example.com/feed", "http://user@localhost/feed",
            "file:///tmp/feed",
        ] {
            XCTAssertNil(
                UpdateManager.qaFeedURL(environment: ["TOKENGAUGE_QA_UPDATES": "1", "TOKENGAUGE_UPDATE_FEED_URL": raw]))
        }
        for host in ["localhost", "127.0.0.1", "[::1]"] {
            let raw = "http://\(host):8000/appcast.xml"
            XCTAssertEqual(
                UpdateManager.qaFeedURL(environment: ["TOKENGAUGE_QA_UPDATES": "1", "TOKENGAUGE_UPDATE_FEED_URL": raw]),
                raw)
        }
    }

    func testFeedOverridePrecedence() {
        let qa = ["TOKENGAUGE_QA_UPDATES": "1", "TOKENGAUGE_UPDATE_FEED_URL": "http://127.0.0.1:18764/appcast.xml"]
        let override = "http://127.0.0.1:8000/override.xml"

        XCTAssertEqual(
            UpdateManager.feedURL(environment: qa, override: override, isDevelopmentBuild: true),
            qa["TOKENGAUGE_UPDATE_FEED_URL"])
        XCTAssertEqual(
            UpdateManager.feedURL(environment: [:], override: override, isDevelopmentBuild: true), override)
        XCTAssertEqual(
            UpdateManager.feedURL(environment: qa, override: override, isDevelopmentBuild: false), override)
        XCTAssertNil(UpdateManager.feedURL(environment: [:], override: nil, isDevelopmentBuild: false))
        XCTAssertNil(UpdateManager.feedURL(environment: [:], override: "not a url", isDevelopmentBuild: false))
    }

    func testManualCheckFailureIsVisibleWithoutPublishingErrorDetails() {
        let manager = makeManager()
        manager.handleManualCheckStarted()
        XCTAssertEqual(manager.manualCheckStatus, .checking)
        XCTAssertEqual(manager.phase, .checking)
        manager.handleError("private network error detail")
        XCTAssertEqual(manager.manualCheckStatus, .failed)
        XCTAssertEqual(manager.phase, .idle)
    }

    func testManualCheckNotFoundReportsUpToDate() {
        let manager = makeManager()
        manager.handleManualCheckStarted()
        manager.handleNotFound()
        XCTAssertEqual(manager.manualCheckStatus, .upToDate)
    }

    func testInstallationErrorRequiresExplicitRetry() {
        let manager = makeManager()
        _ = found(manager, version: "1.0.1")
        manager.handleInstallRequested()
        manager.handleError("download failed")
        XCTAssertEqual(manager.phase, .failed(message: UpdateManager.failureMessageKey))
        XCTAssertEqual(found(manager, version: "1.0.1"), .dismiss)
    }
}
