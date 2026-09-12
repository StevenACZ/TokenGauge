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
                previous.resetsAt != row.resetsAt || previous.usedPercentage > row.usedPercentage
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
