import Darwin
import Foundation

final class FileChangeMonitor: @unchecked Sendable {
    private let url: URL
    private let debounce: TimeInterval
    private let handler: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.stevenacz.TokenGauge.file-monitor", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var stopped = false

    init(url: URL, debounce: TimeInterval = 0.4, handler: @escaping @Sendable () -> Void) {
        self.url = url
        self.debounce = debounce
        self.handler = handler
    }

    deinit {
        source?.cancel()
    }

    func start() {
        queue.async { self.arm() }
    }

    func stop() {
        queue.sync {
            stopped = true
            source?.cancel()
            source = nil
            pending?.cancel()
            retry?.cancel()
        }
    }

    private func arm() {
        source?.cancel()
        source = nil
        retry?.cancel()
        guard !stopped else { return }
        let watchesFile = FileManager.default.fileExists(atPath: url.path)
        let target = watchesFile ? url : url.deletingLastPathComponent()
        let descriptor = open(target.path, O_EVTONLY)
        guard descriptor >= 0 else {
            let item = DispatchWorkItem { [weak self] in self?.arm() }
            retry = item
            queue.asyncAfter(deadline: .now() + 30, execute: item)
            return
        }
        let events: DispatchSource.FileSystemEvent =
            watchesFile ? [.write, .extend, .attrib, .delete, .rename] : .write
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let replaced = !source.data.isDisjoint(with: [.delete, .rename])
            if !watchesFile || replaced { self.arm() }
            if watchesFile || FileManager.default.fileExists(atPath: self.url.path) { self.schedule() }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.handler()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
