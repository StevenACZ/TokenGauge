import AppKit
import Combine
import Foundation
import Sparkle
import os

@MainActor
final class UpdateManager: ObservableObject {

    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case available(version: String)
        case downloading(fraction: Double?)
        case installing
        case failed(version: String)
    }

    enum ManualCheckStatus: Equatable {
        case idle
        case checking
        case upToDate
        case failed
    }

    static let autoCheckDefaultsKey = "autoUpdateCheckEnabled"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var releasePageURL: URL?
    @Published private(set) var manualCheckStatus: ManualCheckStatus = .idle
    @Published private(set) var autoCheckEnabled: Bool

    let isDevelopmentBuild =
        Bundle.main.object(forInfoDictionaryKey: "TokenGaugeDevelopmentBuild") as? Bool ?? true
    var available: Bool {
        !isDevelopmentBuild || Self.qaFeedURL(environment: ProcessInfo.processInfo.environment) != nil
    }
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.stevenacz.TokenGauge", category: "updates")

    private var updater: SPUUpdater?
    private var driver: Driver?
    private var updaterDelegate: UpdaterDelegate?

    private var installRequested = false
    private var pendingVersion: String?
    private var pendingIsInformationOnly = false
    private var expectedDownloadBytes: UInt64 = 0
    private var receivedDownloadBytes: UInt64 = 0
    private var manualCheckPending = false
    private var manualCheckResetTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.autoCheckDefaultsKey) == nil {
            autoCheckEnabled = true
        } else {
            autoCheckEnabled = defaults.bool(forKey: Self.autoCheckDefaultsKey)
        }
    }

    nonisolated static func qaFeedURL(environment: [String: String]) -> String? {
        guard environment["TOKENGAUGE_QA_UPDATES"] == "1",
            let raw = environment["TOKENGAUGE_UPDATE_FEED_URL"],
            let url = URL(string: raw), url.scheme == "http",
            ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host ?? ""),
            url.user == nil, url.password == nil
        else { return nil }
        return raw
    }

    func start() {
        guard updater == nil, available else { return }

        let driver = Driver(manager: self)
        let updaterDelegate = UpdaterDelegate()
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: updaterDelegate
        )
        updater.sendsSystemProfile = false
        updater.updateCheckInterval = 86400
        updater.automaticallyDownloadsUpdates = false
        updater.automaticallyChecksForUpdates = autoCheckEnabled

        do {
            try updater.start()
        } catch {
            log.error("Updater failed to start")
            return
        }

        self.driver = driver
        self.updaterDelegate = updaterDelegate
        self.updater = updater
    }

    func setAutoCheckEnabled(_ enabled: Bool) {
        autoCheckEnabled = enabled
        defaults.set(enabled, forKey: Self.autoCheckDefaultsKey)
        updater?.automaticallyChecksForUpdates = enabled
    }

    func installPendingUpdate() {
        guard let updater else { return }
        if pendingIsInformationOnly {
            openReleasePage()
            return
        }
        guard updater.sessionInProgress == false else { return }
        handleInstallRequested()
        updater.checkForUpdates()
    }

    func checkForUpdatesManually() {
        guard available else { return }
        guard let updater else {
            handleManualCheckStarted()
            finishManualCheck(status: .failed)
            return
        }
        guard updater.sessionInProgress == false else { return }
        handleManualCheckStarted()
        updater.checkForUpdates()
    }

    func handleManualCheckStarted() {
        manualCheckResetTask?.cancel()
        manualCheckPending = true
        manualCheckStatus = .checking
    }

    func openReleasePage() {
        guard let releasePageURL else { return }
        NSWorkspace.shared.open(releasePageURL)
    }

    func handleInstallRequested() {
        installRequested = true
        phase = .downloading(fraction: nil)
    }

    func handleUpdateFound(
        version: String,
        releasePage: URL?,
        informationOnly: Bool
    ) -> SPUUserUpdateChoice {
        pendingVersion = version
        pendingIsInformationOnly = informationOnly
        releasePageURL = releasePage
        finishManualCheck(status: .idle)

        if installRequested && !informationOnly {
            return .install
        }
        installRequested = false
        phase = .available(version: version)
        return .dismiss
    }

    func handleDownloadInitiated() {
        expectedDownloadBytes = 0
        receivedDownloadBytes = 0
        phase = .downloading(fraction: nil)
    }

    func handleDownloadExpectedLength(_ length: UInt64) {
        expectedDownloadBytes = length
    }

    func handleDownloadReceived(bytes: UInt64) {
        receivedDownloadBytes += bytes
        guard expectedDownloadBytes > 0 else { return }
        let fraction = min(1.0, Double(receivedDownloadBytes) / Double(expectedDownloadBytes))
        phase = .downloading(fraction: fraction)
    }

    func handleExtractionStarted() {
        phase = .installing
    }

    func handleReadyToInstall() -> SPUUserUpdateChoice {
        phase = .installing
        return .install
    }

    func handleInstalling() {
        phase = .installing
    }

    func handleNotFound() {
        installRequested = false
        pendingVersion = nil
        pendingIsInformationOnly = false
        releasePageURL = nil
        phase = .idle
        finishManualCheck(status: .upToDate)
    }

    func handleError(_ message: String) {
        finishManualCheck(status: .failed)
        if installRequested, let pendingVersion {
            log.error("Update install failed")
            phase = .failed(version: pendingVersion)
        } else {
            log.debug("Update check failed silently")
            phase = pendingVersion.map { .available(version: $0) } ?? .idle
        }
        installRequested = false
    }

    func handleDismissInstallation() {
        installRequested = false
        switch phase {
        case .downloading, .installing:
            phase = pendingVersion.map { .available(version: $0) } ?? .idle
        case .idle, .available, .failed:
            break
        }
    }

    private func finishManualCheck(status: ManualCheckStatus) {
        guard manualCheckPending else { return }
        manualCheckPending = false
        manualCheckStatus = status
        guard status != .idle else { return }
        manualCheckResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.manualCheckStatus = .idle
        }
    }
}

@MainActor
private final class Driver: NSObject, SPUUserDriver {

    private unowned let manager: UpdateManager

    init(manager: UpdateManager) {
        self.manager = manager
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let choice = manager.handleUpdateFound(
            version: appcastItem.displayVersionString,
            releasePage: appcastItem.infoURL,
            informationOnly: appcastItem.isInformationOnlyUpdate
        )
        reply(choice)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        manager.handleNotFound()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        manager.handleError(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        manager.handleDownloadInitiated()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        manager.handleDownloadExpectedLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        manager.handleDownloadReceived(bytes: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        manager.handleExtractionStarted()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(manager.handleReadyToInstall())
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        manager.handleInstalling()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        manager.handleDismissInstallation()
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        guard Bundle.main.object(forInfoDictionaryKey: "TokenGaugeDevelopmentBuild") as? Bool == true else {
            return nil
        }
        return UpdateManager.qaFeedURL(environment: ProcessInfo.processInfo.environment)
    }
}
