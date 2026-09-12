import Foundation

enum EffortJSONLReader {
    static let maximumLineBytes = 1_048_576

    static func read(_ url: URL, lineHandler: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        var discarding = false
        while true {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty {
                if !discarding, !buffer.isEmpty { lineHandler(buffer) }
                return
            }
            var start = chunk.startIndex
            while start < chunk.endIndex, let newline = chunk[start...].firstIndex(of: 0x0A) {
                let segment = chunk[start..<newline]
                if !discarding, buffer.count + segment.count <= maximumLineBytes {
                    buffer.append(contentsOf: segment)
                    if !buffer.isEmpty { lineHandler(buffer) }
                }
                buffer.removeAll(keepingCapacity: false)
                discarding = false
                start = chunk.index(after: newline)
            }
            guard start < chunk.endIndex, !discarding else { continue }
            let tail = chunk[start...]
            if buffer.count + tail.count > maximumLineBytes {
                buffer.removeAll(keepingCapacity: false)
                discarding = true
            } else {
                buffer.append(contentsOf: tail)
            }
        }
    }
}
