import CoreServices
import Foundation

final class DirectoryActivityMonitor: @unchecked Sendable {
    private let url: URL
    private let latency: TimeInterval
    private let handler: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.stevenacz.TokenGauge.activity-monitor", qos: .utility)
    private var stream: FSEventStreamRef?

    init(url: URL, latency: TimeInterval = 10, handler: @escaping @Sendable () -> Void) {
        self.url = url
        self.latency = latency
        self.handler = handler
    }

    func start() {
        queue.async { [self] in
            guard stream == nil else { return }
            // The stream retains the monitor until stop() releases it.
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                retain: { info in
                    guard let info else { return nil }
                    _ = Unmanaged<DirectoryActivityMonitor>.fromOpaque(info).retain()
                    return info
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<DirectoryActivityMonitor>.fromOpaque(info).release()
                }, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<DirectoryActivityMonitor>.fromOpaque(info).takeUnretainedValue().handler()
            }
            guard
                let stream = FSEventStreamCreate(
                    nil, callback, &context, [url.resolvingSymlinksInPath().path] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
            else { return }
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            self.stream = stream
        }
    }

    func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
}
