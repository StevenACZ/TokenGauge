import Foundation

public struct PastQuotaSession: Equatable, Identifiable, Sendable {
    public struct Call: Equatable, Sendable {
        public let madeAt: Date
        public let predictedRunOut: Date?
    }

    public let forecast: QuotaForecast
    public let depletedAt: Date?
    public let call: Call?

    public static let callThreshold = 50.0
    static let minimumUse = 1.0

    public var id: Date { forecast.reset }
    public var ranOut: Bool { depletedAt != nil }
    public var callWasRight: Bool? { call.map { ($0.predictedRunOut != nil) == ranOut } }

    public static func history(
        like current: QuotaForecast, rows: [HistoryQuotaRow], accountFingerprint: String? = nil,
        gradesCalls: Bool = true
    ) -> [PastQuotaSession] {
        let duration = current.reset.timeIntervalSince(current.start)
        let candidates = rows.filter {
            $0.provider == current.provider && $0.windowID == current.windowID && $0.sampledAt < current.now
                && $0.usedPercentage.isFinite && (0...100).contains($0.usedPercentage)
        }.sorted { $0.sampledAt < $1.sampledAt }
        let owns = { (row: HistoryQuotaRow) in
            accountFingerprint == nil || row.accountFingerprint == accountFingerprint
        }
        let away = QuotaForecast.awayIntervals(candidates, owns: owns, now: current.now)
        var groups: [(reset: Date, rows: [HistoryQuotaRow])] = []
        for row in candidates.filter(owns) {
            guard let reset = row.resetsAt, reset <= current.now, !near(reset, current.reset) else { continue }
            if let index = groups.lastIndex(where: { near($0.reset, reset) }) {
                groups[index] = (reset, groups[index].rows + [row])
            } else {
                groups.append((reset, [row]))
            }
        }
        return groups.sorted { $0.reset > $1.reset }.compactMap { group in
            let start = group.reset.addingTimeInterval(-duration)
            let observed = group.rows.filter { $0.sampledAt > start && $0.sampledAt <= group.reset }
            guard let last = observed.last, observed.contains(where: { $0.usedPercentage >= minimumUse })
            else { return nil }
            let points =
                [ForecastPoint(date: start, remaining: 100)]
                + observed.map { ForecastPoint(date: $0.sampledAt, remaining: 100 - $0.usedPercentage) }
                + [ForecastPoint(date: group.reset, remaining: 100 - last.usedPercentage)]
            let gaps = away.filter { $0.start < group.reset && $0.end > start }
            let boosts = zip(points, points.dropFirst()).compactMap { previous, next in
                next.remaining - previous.remaining > QuotaForecast.boostThreshold
                    && !QuotaForecast.crosses(gaps, previous, next) ? next : nil
            }
            let forecast = QuotaForecast(
                provider: current.provider, windowID: current.windowID, displayName: current.displayName,
                start: start, reset: group.reset, now: group.reset, points: points,
                remaining: 100 - last.usedPercentage, boosts: boosts, away: gaps, pointsPerHour: nil,
                recentPointsPerHour: nil)
            return PastQuotaSession(
                forecast: forecast, depletedAt: observed.first { $0.usedPercentage >= 100 }?.sampledAt,
                call: gradesCalls
                    ? call(
                        observed, reset: group.reset, duration: duration, current: current, rows: rows,
                        accountFingerprint: accountFingerprint) : nil)
        }
    }

    private static func near(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) <= QuotaForecast.resetTolerance
    }

    private static func call(
        _ observed: [HistoryQuotaRow], reset: Date, duration: TimeInterval, current: QuotaForecast,
        rows: [HistoryQuotaRow], accountFingerprint: String?
    ) -> Call? {
        guard let row = observed.first(where: { $0.usedPercentage >= callThreshold }), row.usedPercentage < 100,
            let made = QuotaForecast.make(
                provider: current.provider,
                window: QuotaWindow(
                    id: current.windowID, usedPercentage: row.usedPercentage, resetsAt: reset,
                    durationMinutes: Int(duration / 60), displayName: current.displayName),
                rows: rows, now: row.sampledAt, accountFingerprint: accountFingerprint)
        else { return nil }
        if case .runsOut(let date) = made.verdict { return Call(madeAt: row.sampledAt, predictedRunOut: date) }
        return Call(madeAt: row.sampledAt, predictedRunOut: nil)
    }
}
