import CryptoKit
import Foundation

enum JSONLReader {
    static let maximumLineBytes = 1_048_576
    static let anchorBytes = 4_096

    struct Progress {
        let bytesRead: Int
        let committedOffset: Int
    }

    enum ReadError: Error {
        case offsetNotAtLineBoundary
    }

    static func anchor(_ url: URL, endingAt offset: Int) throws -> String? {
        guard offset > 0 else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = min(offset, anchorBytes)
        try handle.seek(toOffset: UInt64(offset - length))
        guard let data = try handle.read(upToCount: length), data.count == length else { return nil }
        return Hex.string(SHA256.hash(data: data))
    }

    @discardableResult
    static func read(_ url: URL, from offset: Int = 0, lineHandler: (Data) -> Void) throws -> Progress {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if offset > 0 {
            try handle.seek(toOffset: UInt64(offset - 1))
            guard try handle.read(upToCount: 1) == Data([0x0A]) else { throw ReadError.offsetNotAtLineBoundary }
        }
        var buffer = Data()
        var discarding = false
        var bytesRead = 0
        var committed = offset
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 65_536) ?? Data() }
            if chunk.isEmpty {
                if !discarding, !buffer.isEmpty { lineHandler(buffer) }
                return Progress(bytesRead: bytesRead, committedOffset: committed)
            }
            let chunkOffset = offset + bytesRead
            bytesRead += chunk.count
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
                committed = chunkOffset + chunk.distance(from: chunk.startIndex, to: start)
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
