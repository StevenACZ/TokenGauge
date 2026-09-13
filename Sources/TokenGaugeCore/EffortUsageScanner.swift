import CryptoKit
import Foundation

public enum EffortUsageScanner {
    public static func scan(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        lookbackDays: Int = 7
    ) throws -> [EffortUsageRecord] {
        guard lookbackDays > 0 else { return [] }
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1 - lookbackDays, to: now) ?? now)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        var records: [String: EffortUsageRecord] = [:]
        let roots: [(UsageProvider, URL)] = [
            (.codex, homeDirectory.appending(path: ".codex/sessions")),
            (.claude, homeDirectory.appending(path: ".claude/projects")),
        ]
        for (provider, root) in roots {
            guard safePath(root, home: homeDirectory) else { continue }
            let recentDirectories = Set(
                provider == .codex ? codexDirectories(root: root, cutoff: cutoff, now: now).map(\.path) : [])
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
            guard
                let files = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
                )
            else { continue }
            for case let file as URL in files {
                guard let info = try? file.resourceValues(forKeys: keys), info.isSymbolicLink != true else {
                    files.skipDescendants()
                    continue
                }
                guard info.isRegularFile == true, file.pathExtension == "jsonl",
                    recentDirectories.contains(file.deletingLastPathComponent().path)
                        || (info.contentModificationDate ?? .distantPast) >= cutoff
                else { continue }
                var context: EffortTranscriptMetadata.Payload?
                try EffortJSONLReader.read(file) { line in
                    autoreleasepool {
                        guard let metadata = try? decoder.decode(EffortTranscriptMetadata.self, from: line) else {
                            return
                        }
                        if provider == .codex, metadata.type == "turn_context" {
                            context = metadata.payload
                            return
                        }
                        guard metadata.type == (provider == .codex ? "token_usage_record" : "assistant"),
                            let timestamp = metadata.timestamp,
                            let date = fractional.date(from: timestamp) ?? standard.date(from: timestamp),
                            date >= cutoff, date <= now,
                            let record = makeRecord(
                                metadata, provider: provider, context: context, date: date, calendar: calendar)
                        else { return }
                        records[record.id] = merge(records[record.id], record)
                    }
                }
            }
        }
        return records.values.sorted { $0.recordedAt == $1.recordedAt ? $0.id < $1.id : $0.recordedAt < $1.recordedAt }
    }

    private static func makeRecord(
        _ metadata: EffortTranscriptMetadata, provider: UsageProvider,
        context: EffortTranscriptMetadata.Payload?, date: Date, calendar: Calendar
    ) -> EffortUsageRecord? {
        let identifier: String?
        let model: String?
        let effort: String?
        let tokens: Int?
        if provider == .codex {
            guard metadata.type == "token_usage_record", let payload = metadata.payload else { return nil }
            identifier = payload.response_id
            let matching = context?.turn_id != nil && context?.turn_id == payload.turn_id ? context : nil
            model = matching?.model
            effort = matching?.effort
            tokens = payload.usage?.total_tokens
        } else {
            guard metadata.type == "assistant", let message = metadata.message else { return nil }
            identifier = message.id
            model = message.model
            effort = metadata.perTurnEffort ?? metadata.effort
            tokens = message.usage?.claudeTotal
        }
        guard let identifier, !identifier.isEmpty, let tokens, tokens > 0 else { return nil }
        let hex = Array("0123456789abcdef".utf8)
        let hash = String(
            decoding: SHA256.hash(data: Data("\(provider.rawValue):\(identifier)".utf8)).flatMap {
                [hex[Int($0 >> 4)], hex[Int($0 & 15)]]
            }, as: UTF8.self)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return EffortUsageRecord(
            id: hash, provider: provider, recordedAt: date, day: day,
            model: EffortTranscriptMetadata.normalizedModel(model),
            effort: EffortTranscriptMetadata.normalizedEffort(effort), tokens: tokens)
    }

    private static func merge(_ existing: EffortUsageRecord?, _ incoming: EffortUsageRecord) -> EffortUsageRecord {
        guard let existing else { return incoming }
        let earliest = existing.recordedAt <= incoming.recordedAt ? existing : incoming
        return EffortUsageRecord(
            id: existing.id, provider: existing.provider, recordedAt: earliest.recordedAt, day: earliest.day,
            model: existing.model == "unknown" ? incoming.model : existing.model,
            effort: existing.effort == "unknown" ? incoming.effort : existing.effort,
            tokens: max(existing.tokens, incoming.tokens))
    }

    private static func codexDirectories(root: URL, cutoff: Date, now: Date) -> [URL] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var date = utc.startOfDay(for: cutoff.addingTimeInterval(-86_400))
        var directories: [URL] = []
        while date <= now {
            let components = utc.dateComponents([.year, .month, .day], from: date)
            directories.append(
                root.appending(
                    path: String(format: "%04d/%02d/%02d", components.year!, components.month!, components.day!)))
            date = date.addingTimeInterval(86_400)
        }
        return directories
    }

    private static func safePath(_ url: URL, home: URL) -> Bool {
        var current = url.standardizedFileURL
        while current.path != "/" {
            guard let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true
            else { return false }
            if current == home.standardizedFileURL { return true }
            current.deleteLastPathComponent()
        }
        return true
    }
}
