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
        case checking
        case available(version: String)
        case downloading(version: String, fraction: Double?)
        case extracting(version: String, fraction: Double?)
        case readyToInstall(version: String, deferred: Bool)
        case installing(version: String)
        case failed(message: String)
    }

    enum Stage: Equatable {
        case notDownloaded
        case downloaded
        case installing
    }

    struct FoundDecision: Equatable {
        let choice: SPUUserUpdateChoice
        let phase: Phase
    }

    enum ManualCheckStatus: Equatable {
        case idle
        case checking
        case upToDate
        case failed
    }

    static let autoCheckDefaultsKey = "autoUpdateCheckEnabled"
    nonisolated static let feedOverrideDefaultsKey = "updateFeedURLOverride"
    static let deferredVersionDefaultsKey = "deferredUpdateVersion"
    static let progressPublishInterval: TimeInterval = 0.05
    static let failureMessageKey = "updates.failed"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var releasePageURL: URL?
    @Published private(set) var manualCheckStatus: ManualCheckStatus = .idle
    @Published private(set) var autoCheckEnabled: Bool

    let isDevelopmentBuild =
        Bundle.main.object(forInfoDictionaryKey: "TokenGaugeDevelopmentBuild") as? Bool ?? true
    var available: Bool {
        !isDevelopmentBuild
            || Self.feedURL(
                environment: ProcessInfo.processInfo.environment,
                override: defaults.string(forKey: Self.feedOverrideDefaultsKey),
                isDevelopmentBuild: isDevelopmentBuild
            ) != nil
    }
    private let defaults: UserDefaults
    private let now: () -> Date
    private let log = Logger(subsystem: "com.stevenacz.TokenGauge", category: "updates")

    private var updater: SPUUpdater?
    private var driver: Driver?
    private var updaterDelegate: UpdaterDelegate?

    private var installRequested = false
    private var resumeInstallRequested = false
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var pendingVersion: String?
    private var pendingIsInformationOnly = false
    private var expectedDownloadBytes: UInt64 = 0
    private var receivedDownloadBytes: UInt64 = 0
    private var lastProgressPublish = Date.distantPast
    private var manualCheckPending = false
    private var manualCheckResetTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
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

    nonisolated static func feedURL(
        environment: [String: String],
        override: String?,
        isDevelopmentBuild: Bool
    ) -> String? {
        if isDevelopmentBuild, let qa = qaFeedURL(environment: environment) { return qa }
        if let override, let url = URL(string: override), url.scheme == "https" {
            return override
        }
        return nil
    }

    nonisolated static func decideUpdateFound(
        version: String,
        stage: Stage,
        installRequested: Bool,
        informationOnly: Bool
    ) -> FoundDecision {
        if informationOnly {
            return FoundDecision(choice: .dismiss, phase: .available(version: version))
        }
        if installRequested {
            let phase: Phase =
                stage == .notDownloaded
                ? .downloading(version: version, fraction: nil) : .installing(version: version)
            return FoundDecision(choice: .install, phase: phase)
        }
        if stage == .downloaded {
            return FoundDecision(choice: .dismiss, phase: .readyToInstall(version: version, deferred: true))
        }
        return FoundDecision(choice: .dismiss, phase: .available(version: version))
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

        if deferredVersion != nil { updater.checkForUpdatesInBackground() }
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

    func installReadyUpdate() {
        guard case .readyToInstall(let version, let deferred) = phase else { return }
        guard !deferred else {
            resumeDeferredInstall()
            return
        }
        installRequested = false
        resumeInstallRequested = false
        deferredVersion = nil
        phase = .installing(version: version)
        let reply = readyReply
        readyReply = nil
        reply?(.install)
    }

    func deferReadyUpdate() {
        guard case .readyToInstall(let version, false) = phase else { return }
        installRequested = false
        resumeInstallRequested = false
        let reply = readyReply
        readyReply = nil
        reply?(.dismiss)
        deferredVersion = version
        phase = .readyToInstall(version: version, deferred: true)
    }

    func resumeDeferredInstall() {
        guard case .readyToInstall(let version, true) = phase else { return }
        resumeInstallRequested = true
        installRequested = true
        phase = .installing(version: version)
        guard let updater, updater.sessionInProgress == false else { return }
        updater.checkForUpdates()
    }

    func checkForUpdatesManually() {
        guard available else { return }
        guard let updater else {
            handleManualCheckStarted()
            finishManualCheck(status: .failed)
            phase = idleOrPendingPhase
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
        if phase == .idle { phase = .checking }
    }

    func openReleasePage() {
        guard let releasePageURL else { return }
        NSWorkspace.shared.open(releasePageURL)
    }

    func handleInstallRequested() {
        installRequested = true
        phase = .downloading(version: pendingVersion ?? "", fraction: nil)
    }

    func handleUpdateFound(
        version: String,
        releasePage: URL?,
        informationOnly: Bool,
        stage: Stage = .notDownloaded
    ) -> SPUUserUpdateChoice {
        pendingVersion = version
        pendingIsInformationOnly = informationOnly
        releasePageURL = releasePage
        finishManualCheck(status: .idle)

        let decision = Self.decideUpdateFound(
            version: version, stage: stage, installRequested: installRequested, informationOnly: informationOnly)
        installRequested = decision.choice == .install
        deferredVersion = decision.phase == .readyToInstall(version: version, deferred: true) ? version : nil
        phase = decision.phase
        return decision.choice
    }

    func handleDownloadInitiated() {
        expectedDownloadBytes = 0
        receivedDownloadBytes = 0
        lastProgressPublish = .distantPast
        phase = .downloading(version: pendingVersion ?? "", fraction: nil)
    }

    func handleDownloadExpectedLength(_ length: UInt64) {
        expectedDownloadBytes = length
    }

    func handleDownloadReceived(bytes: UInt64) {
        receivedDownloadBytes += bytes
        guard expectedDownloadBytes > 0 else { return }
        let fraction = min(1.0, Double(receivedDownloadBytes) / Double(expectedDownloadBytes))
        publish(.downloading(version: pendingVersion ?? "", fraction: fraction), force: fraction >= 1)
    }

    func handleExtractionStarted() {
        lastProgressPublish = .distantPast
        if case .downloading(let version, let fraction) = phase, fraction != 1 {
            phase = .downloading(version: version, fraction: 1)
        }
        phase = .extracting(version: pendingVersion ?? "", fraction: nil)
    }

    func handleExtractionProgress(_ progress: Double) {
        let fraction = min(1.0, max(0.0, progress))
        publish(.extracting(version: pendingVersion ?? "", fraction: fraction), force: fraction >= 1)
    }

    func handleReadyToInstall(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = pendingVersion ?? ""
        if resumeInstallRequested || installRequested {
            installRequested = false
            resumeInstallRequested = false
            deferredVersion = nil
            phase = .installing(version: version)
            reply(.install)
            return
        }
        readyReply = reply
        phase = .readyToInstall(version: version, deferred: false)
    }

    func handleInstalling() {
        phase = .installing(version: pendingVersion ?? "")
    }

    func handleNotFound() {
        installRequested = false
        resumeInstallRequested = false
        readyReply = nil
        pendingVersion = nil
        pendingIsInformationOnly = false
        releasePageURL = nil
        deferredVersion = nil
        phase = .idle
        finishManualCheck(status: .upToDate)
    }

    func handleError(_ message: String) {
        finishManualCheck(status: .failed)
        readyReply = nil
        if installRequested || resumeInstallRequested {
            log.error("Update install failed")
            phase = .failed(message: Self.failureMessageKey)
        } else {
            log.debug("Update check failed silently")
            phase = idleOrPendingPhase
        }
        installRequested = false
        resumeInstallRequested = false
    }

    func handleDismissInstallation() {
        installRequested = false
        resumeInstallRequested = false
        readyReply = nil
        switch phase {
        case .checking, .downloading, .extracting, .installing:
            phase = idleOrPendingPhase
        case .idle, .available, .readyToInstall, .failed:
            break
        }
    }

    private var idleOrPendingPhase: Phase {
        pendingVersion.map { .available(version: $0) } ?? .idle
    }

    private var deferredVersion: String? {
        get { defaults.string(forKey: Self.deferredVersionDefaultsKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.deferredVersionDefaultsKey)
            } else {
                defaults.removeObject(forKey: Self.deferredVersionDefaultsKey)
            }
        }
    }

    private func publish(_ next: Phase, force: Bool) {
        let instant = now()
        guard force || instant.timeIntervalSince(lastProgressPublish) >= Self.progressPublishInterval else { return }
        lastProgressPublish = instant
        phase = next
    }

    private func finishManualCheck(status: ManualCheckStatus) {
        guard manualCheckPending else { return }
        manualCheckPending = false
        manualCheckStatus = status
        guard status != .idle else { return }
        manualCheckResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
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
            informationOnly: appcastItem.isInformationOnlyUpdate,
            stage: Self.stage(state.stage)
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

    func showExtractionReceivedProgress(_ progress: Double) {
        manager.handleExtractionProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        manager.handleReadyToInstall(reply: reply)
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

    private static func stage(_ stage: SPUUserUpdateStage) -> UpdateManager.Stage {
        switch stage {
        case .downloaded: return .downloaded
        case .installing: return .installing
        default: return .notDownloaded
        }
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateManager.feedURL(
            environment: ProcessInfo.processInfo.environment,
            override: UserDefaults.standard.string(forKey: UpdateManager.feedOverrideDefaultsKey),
            isDevelopmentBuild: Bundle.main.object(forInfoDictionaryKey: "TokenGaugeDevelopmentBuild") as? Bool ?? true
        )
    }
}
