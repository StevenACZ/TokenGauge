import Foundation
import os

enum BlockingWork {
    struct TimedOut: Error {}

    private static let queue = DispatchQueue(
        label: "com.stevenacz.TokenGauge.blocking-work", qos: .utility, attributes: .concurrent)

    static func run<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func waitForResult<Value: Sendable>(
        timeout: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> Value
    ) throws -> Value {
        let outcome = OSAllocatedUnfairLock<Result<Value, any Error>?>(initialState: nil)
        let semaphore = DispatchSemaphore(value: 0)
        let task = Task.detached(priority: .utility) {
            do {
                let value = try await operation()
                outcome.withLock { $0 = .success(value) }
            } catch {
                outcome.withLock { $0 = .failure(error) }
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            throw TimedOut()
        }
        guard let result = outcome.withLock({ $0 }) else { throw TimedOut() }
        return try result.get()
    }
}
