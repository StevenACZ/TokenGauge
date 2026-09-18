import Foundation

@MainActor
final class RefreshScheduler {
    private let interval: TimeInterval
    private let fire: @MainActor () -> Void
    private var periodicTimer: Timer?
    private var resetTimer: Timer?

    init(interval: TimeInterval = 300, fire: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.fire = fire
    }

    func start() {
        periodicTimer?.invalidate()
        periodicTimer = timer(after: interval, repeats: true)
    }

    func scheduleResetRefresh(at reset: Date?, now: Date = Date()) {
        resetTimer?.invalidate()
        resetTimer = reset.map { timer(after: max($0.timeIntervalSince(now) + 5, 1), repeats: false) }
    }

    func stop() {
        periodicTimer?.invalidate()
        resetTimer?.invalidate()
        periodicTimer = nil
        resetTimer = nil
    }

    private func timer(after delay: TimeInterval, repeats: Bool) -> Timer {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: repeats) { [weak self] _ in
            Task { @MainActor in
                self?.fire()
            }
        }
    }
}
