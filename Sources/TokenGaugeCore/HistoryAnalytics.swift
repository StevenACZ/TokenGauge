import Foundation

public struct HistoryBounds: Equatable, Sendable {
    public let firstDay: String?
    public let lastDay: String?

    public init(firstDay: String?, lastDay: String?) {
        self.firstDay = firstDay
        self.lastDay = lastDay
    }
}

public struct QuotaPace: Equatable, Sendable {
    public let pointsPerHour: Double
    public let observedMinutes: Double
    public let sampledAt: Date
    public let resetsAt: Date?
    public let lastUsedPercentage: Double?

    public init(
        pointsPerHour: Double, observedMinutes: Double, sampledAt: Date,
        resetsAt: Date? = nil, lastUsedPercentage: Double? = nil
    ) {
        self.pointsPerHour = pointsPerHour
        self.observedMinutes = observedMinutes
        self.sampledAt = sampledAt
        self.resetsAt = resetsAt
        self.lastUsedPercentage = lastUsedPercentage
    }
}

public enum HistoryAnalytics {
    public static func sameReset(_ left: Date?, _ right: Date?) -> Bool {
        guard let left, let right else { return false }
        return abs(left.timeIntervalSince(right)) <= 1
    }

    public static func streaks(usageDays: Set<String>, today: String, calendar: Calendar = .current)
        -> (current: Int, longest: Int)
    {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let ordinals = Set(
            usageDays.compactMap { formatter.date(from: $0) }
                .compactMap { calendar.ordinality(of: .day, in: .era, for: $0) })
        var longest = 0
        for start in ordinals where !ordinals.contains(start - 1) {
            var length = 1
            while ordinals.contains(start + length) { length += 1 }
            longest = max(longest, length)
        }
        var current = 0
        if let reference = formatter.date(from: today).flatMap({ calendar.ordinality(of: .day, in: .era, for: $0) }) {
            var cursor = ordinals.contains(reference) ? reference : reference - 1
            while ordinals.contains(cursor) {
                current += 1
                cursor -= 1
            }
        }
        return (current, longest)
    }

    public static func pace(
        rows: [HistoryQuotaRow],
        provider: UsageProvider,
        windowID: String,
        now: Date
    ) -> QuotaPace? {
        let cutoff = now.addingTimeInterval(-3600)
        let stream = rows.filter {
            $0.provider == provider && $0.windowID == windowID && $0.sampledAt >= cutoff && $0.sampledAt <= now
        }
        let boundary = stream.compactMap(\.continuityStartedAt).max() ?? cutoff
        let groups = Dictionary(grouping: stream.filter { $0.sampledAt >= boundary }, by: \.sampledAt)
        var suffix: [HistoryQuotaRow] = []
        for timestamp in groups.keys.sorted() {
            guard let duplicates = groups[timestamp], let row = duplicates.first,
                duplicates.allSatisfy({ $0 == row }), row.isVerified, row.durationMinutes == 10_080,
                row.usedPercentage.isFinite, (0...100).contains(row.usedPercentage),
                let reset = row.resetsAt, reset > now
            else {
                suffix.removeAll(keepingCapacity: true)
                continue
            }
            if let previous = suffix.last,
                !sameReset(suffix.first?.resetsAt, row.resetsAt) || previous.usedPercentage > row.usedPercentage
                    || row.sampledAt.timeIntervalSince(previous.sampledAt) > 1800
            {
                suffix.removeAll(keepingCapacity: true)
            }
            suffix.append(row)
        }
        guard suffix.count >= 3, let first = suffix.first, let last = suffix.last,
            now.timeIntervalSince(last.sampledAt) <= 1200
        else { return nil }
        let elapsed = last.sampledAt.timeIntervalSince(first.sampledAt)
        guard elapsed >= 1800 else { return nil }
        return QuotaPace(
            pointsPerHour: (last.usedPercentage - first.usedPercentage) / (elapsed / 3600),
            observedMinutes: elapsed / 60,
            sampledAt: last.sampledAt, resetsAt: last.resetsAt, lastUsedPercentage: last.usedPercentage
        )
    }
}
