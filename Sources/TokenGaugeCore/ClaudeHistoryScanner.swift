import Foundation

public enum ClaudeHistoryScanner {
    public static func scan(
        projectsRoot: URL = UsagePaths.claudeProjects(),
        days: Int = 8,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [ModelTokenBucket] {
        guard days > 0 else { return [] }
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: projectsRoot,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        var messages: [String: (day: String, hour: Date, model: String, tokens: Int)] = [:]

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, (values.contentModificationDate ?? .distantPast) >= start else {
                continue
            }

            try JSONLReader.read(fileURL) { line in
                autoreleasepool {
                    guard
                        let record = try? decoder.decode(ClaudeTranscriptRecord.self, from: line),
                        record.type == "assistant",
                        let message = record.message,
                        let usage = message.usage,
                        let timestamp = record.timestamp,
                        let date = fractionalFormatter.date(from: timestamp) ?? standardFormatter.date(from: timestamp),
                        date >= start,
                        date <= now.addingTimeInterval(300),
                        let messageID = message.id ?? record.uuid
                    else { return }

                    let tokens =
                        max(usage.inputTokens ?? 0, 0)
                        + max(usage.outputTokens ?? 0, 0)
                        + max(usage.cacheCreationInputTokens ?? 0, 0)
                        + max(usage.cacheReadInputTokens ?? 0, 0)
                    guard tokens > 0 else { return }
                    let model = normalizedModel(message.model)
                    let day = dayString(date, calendar: calendar)
                    let hour = hourStart(date)
                    if let current = messages[messageID], current.tokens >= tokens {
                        return
                    }
                    messages[messageID] = (day, hour, model, tokens)
                }
            }
        }

        var totals: [ModelTokenBucket.ID: ModelTokenBucket] = [:]
        for message in messages.values {
            let key = "\(message.model)-\(message.hour.timeIntervalSince1970)"
            let merged = (totals[key]?.tokens ?? 0) + message.tokens
            totals[key] = ModelTokenBucket(
                day: message.day,
                hourStart: message.hour,
                model: message.model,
                tokens: merged
            )
        }
        return totals.values.sorted { left, right in
            if left.hourStart != right.hourStart { return left.hourStart < right.hourStart }
            return left.model < right.model
        }
    }

    private static func normalizedModel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("<") else { return "unknown" }
        return raw
    }

    private static func hourStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct ClaudeTranscriptRecord: Decodable {
    let type: String?
    let timestamp: String?
    let uuid: String?
    let message: ClaudeTranscriptMessage?
}

private struct ClaudeTranscriptMessage: Decodable {
    let id: String?
    let model: String?
    let usage: ClaudeTranscriptUsage?
}

private struct ClaudeTranscriptUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

private enum JSONLReader {
    private static let maximumLineBytes = 1_048_576

    static func read(_ url: URL, lineHandler: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        var discardingLongLine = false

        while true {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty {
                if !discardingLongLine, !buffer.isEmpty { lineHandler(buffer) }
                return
            }

            var segmentStart = chunk.startIndex
            while segmentStart < chunk.endIndex,
                let newline = chunk[segmentStart...].firstIndex(of: 0x0A)
            {
                let segment = chunk[segmentStart..<newline]
                if !discardingLongLine, buffer.count + segment.count <= maximumLineBytes {
                    buffer.append(contentsOf: segment)
                    if !buffer.isEmpty { lineHandler(buffer) }
                }
                buffer.removeAll(keepingCapacity: false)
                discardingLongLine = false
                segmentStart = chunk.index(after: newline)
            }

            guard segmentStart < chunk.endIndex else { continue }
            if discardingLongLine { continue }
            let tail = chunk[segmentStart...]
            if buffer.count + tail.count > maximumLineBytes {
                buffer.removeAll(keepingCapacity: false)
                discardingLongLine = true
            } else {
                buffer.append(contentsOf: tail)
            }
        }
    }
}
