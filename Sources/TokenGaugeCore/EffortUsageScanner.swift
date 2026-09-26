import CryptoKit
import Foundation

public enum EffortUsageScanner {
    public static func scan(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        lookbackDays: Int = 7
    ) throws -> [EffortUsageRecord] {
        try TranscriptScanner.scan(
            homeDirectory: homeDirectory, stateURL: nil, now: now, calendar: .current, historyDays: 0,
            effortDays: lookbackDays
        ).effortRecords
    }

    static func entry(from metadata: EffortTranscriptMetadata, at date: Date, context: CodexTurnContext?) -> ScanEntry?
    {
        guard metadata.type == "token_usage_record", let payload = metadata.payload,
            let identifier = payload.response_id, !identifier.isEmpty,
            let tokens = payload.usage?.total_tokens, tokens > 0
        else { return nil }
        let matching = context?.turnID != nil && context?.turnID == payload.turn_id ? context : nil
        let model = matching?.model ?? "unknown"
        let time = date.timeIntervalSince1970
        return ScanEntry(
            id: hash(provider: .codex, identifier: identifier), firstAt: time, peakAt: time, tokens: tokens,
            model: model, effortModel: model, effort: matching?.effort ?? "unknown", eligible: true,
            cachedTokens: payload.usage?.cached_input_tokens.map { max(0, $0) })
    }

    static func records(
        _ entries: some Sequence<(provider: UsageProvider, entry: ScanEntry)>, cutoff: Date, now: Date,
        calendar: Calendar
    ) -> [EffortUsageRecord] {
        let earliest = cutoff.timeIntervalSince1970
        let latest = now.timeIntervalSince1970
        return entries.compactMap { provider, entry -> EffortUsageRecord? in
            guard entry.eligible, entry.firstAt >= earliest, entry.firstAt <= latest else { return nil }
            let recordedAt = Date(timeIntervalSince1970: entry.firstAt)
            return EffortUsageRecord(
                id: entry.id, provider: provider, recordedAt: recordedAt,
                day: TranscriptScanner.dayString(recordedAt, calendar: calendar),
                model: entry.effortModel, effort: entry.effort, tokens: entry.tokens, cachedTokens: entry.cachedTokens)
        }.sorted { $0.recordedAt == $1.recordedAt ? $0.id < $1.id : $0.recordedAt < $1.recordedAt }
    }

    static func hash(provider: UsageProvider, identifier: String) -> String {
        Hex.string(SHA256.hash(data: Data("\(provider.rawValue):\(identifier)".utf8)))
    }

    static func codexDirectories(root: URL, cutoff: Date, now: Date) -> [URL] {
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

    static func safePath(_ url: URL, home: URL) -> Bool {
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
