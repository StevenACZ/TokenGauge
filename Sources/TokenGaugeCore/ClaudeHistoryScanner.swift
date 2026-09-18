import Foundation

public enum ClaudeHistoryScanner {
    public static func scan(
        projectsRoot: URL = UsagePaths.claudeProjects(),
        days: Int = 8,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [ModelTokenBucket] {
        try TranscriptScanner.scan(
            claudeProjects: projectsRoot, codexSessions: nil, stateURL: nil, now: now, calendar: calendar,
            historyDays: days, effortDays: 0
        ).buckets
    }

    static func entry(from metadata: EffortTranscriptMetadata, at date: Date) -> ScanEntry? {
        guard metadata.type == "assistant", let message = metadata.message, let usage = message.usage,
            let key = message.id ?? metadata.uuid, let tokens = usage.claudeTotal, tokens > 0
        else { return nil }
        let time = date.timeIntervalSince1970
        return ScanEntry(
            id: EffortUsageScanner.hash(provider: .claude, identifier: key), firstAt: time, peakAt: time,
            tokens: tokens, model: normalizedModel(message.model),
            effortModel: EffortTranscriptMetadata.normalizedModel(message.model),
            effort: EffortTranscriptMetadata.normalizedEffort(metadata.perTurnEffort ?? metadata.effort),
            eligible: message.id?.isEmpty == false)
    }

    static func buckets(
        _ entries: some Sequence<ScanEntry>, start: Date, now: Date, calendar: Calendar
    ) -> [ModelTokenBucket] {
        let earliest = start.timeIntervalSince1970
        let latest = now.timeIntervalSince1970 + 300
        var totals: [String: ModelTokenBucket] = [:]
        let ordered = entries.filter { $0.peakAt >= earliest && $0.peakAt <= latest }.sorted {
            $0.peakAt == $1.peakAt ? $0.id < $1.id : $0.peakAt < $1.peakAt
        }
        for entry in ordered {
            let hour = hourStart(entry.peakAt)
            let key = "\(entry.model)-\(hour.timeIntervalSince1970)"
            let current = totals[key]
            totals[key] = ModelTokenBucket(
                day: current?.day
                    ?? TranscriptScanner.dayString(Date(timeIntervalSince1970: entry.peakAt), calendar: calendar),
                hourStart: hour,
                model: entry.model,
                tokens: (current?.tokens ?? 0) + entry.tokens
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

    private static func hourStart(_ time: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (time / 3600).rounded(.down) * 3600)
    }
}
