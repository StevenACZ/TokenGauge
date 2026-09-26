import Foundation

public struct ForecastPoint: Equatable, Sendable {
    public let date: Date
    public let remaining: Double

    public init(date: Date, remaining: Double) {
        self.date = date
        self.remaining = remaining
    }
}

public struct QuotaForecast: Equatable, Identifiable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case noUsage
        case lasts(margin: Double)
        case tight(margin: Double)
        case runsOut(at: Date)
        case exhausted
    }

    public let provider: UsageProvider
    public let windowID: String
    public let displayName: String?
    public let start: Date
    public let reset: Date
    public let now: Date
    public let points: [ForecastPoint]
    public let remaining: Double
    public let boosts: [ForecastPoint]
    public let away: [DateInterval]
    public let pointsPerHour: Double?
    public let recentPointsPerHour: Double?

    public struct Horizon: Equatable, Sendable {
        public let pace: TimeInterval
        public let recent: TimeInterval
        let minimumPace: TimeInterval
        let minimumRecent: TimeInterval
        let spansPreviousWindows: Bool

        public static let weekly = Horizon(
            pace: 72 * 3600, recent: 24 * 3600, minimumPace: 3 * 3600, minimumRecent: 6 * 3600,
            spansPreviousWindows: true)
        public static let session = Horizon(
            pace: 5 * 3600, recent: 3600, minimumPace: 10 * 60, minimumRecent: 30 * 60, spansPreviousWindows: false)

        public static func of(durationMinutes minutes: Int) -> Horizon { minutes < 1_440 ? .session : .weekly }
    }

    public static let tightMargin = 10.0
    static let boostThreshold = 3.0
    static let resetTolerance: TimeInterval = 3600

    public var id: String { provider.rawValue + ":" + windowID }
    public var isSession: Bool { reset.timeIntervalSince(start) < 86_400 }
    public var horizon: Horizon { isSession ? .session : .weekly }
    public var budgetUnit: TimeInterval { isSession ? 3600 : 86_400 }
    public var hoursLeft: Double { max(0, reset.timeIntervalSince(now) / 3600) }

    public var projectedRemainingAtReset: Double? {
        pointsPerHour.map { remaining - $0 * hoursLeft }
    }

    public var runsOutAt: Date? { exhaustion(pace: pointsPerHour) }
    public var recentRunsOutAt: Date? { exhaustion(pace: recentPointsPerHour) }

    public var budget: Double { remaining / max(hoursLeft * 3600 / budgetUnit, 1) }

    public var verdict: Verdict {
        if remaining <= 0 { return .exhausted }
        guard let projected = projectedRemainingAtReset else {
            return remaining >= 100 ? .noUsage : margin(remaining)
        }
        if projected <= 0, let date = runsOutAt { return .runsOut(at: date) }
        if remaining >= 100, pointsPerHour == 0 { return .noUsage }
        return margin(projected)
    }

    private func margin(_ value: Double) -> Verdict {
        value < Self.tightMargin ? .tight(margin: value) : .lasts(margin: value)
    }

    public init(
        provider: UsageProvider, windowID: String, displayName: String?, start: Date, reset: Date, now: Date,
        points: [ForecastPoint], remaining: Double, boosts: [ForecastPoint], away: [DateInterval] = [],
        pointsPerHour: Double?, recentPointsPerHour: Double?
    ) {
        self.provider = provider
        self.windowID = windowID
        self.displayName = displayName
        self.start = start
        self.reset = reset
        self.now = now
        self.points = points
        self.remaining = remaining
        self.boosts = boosts
        self.away = away
        self.pointsPerHour = pointsPerHour
        self.recentPointsPerHour = recentPointsPerHour
    }

    public static func make(
        provider: UsageProvider, window: QuotaWindow, rows: [HistoryQuotaRow], now: Date,
        accountFingerprint: String? = nil
    ) -> QuotaForecast? {
        guard let reset = window.resetsAt, let minutes = window.durationMinutes, minutes > 0, reset > now,
            window.usedPercentage.isFinite
        else { return nil }
        let start = reset.addingTimeInterval(-Double(minutes) * 60)
        guard start < now else { return nil }
        let remaining = min(max(window.remainingPercentage, 0), 100)
        let candidates = rows.filter { matches($0, provider: provider, window: window, now: now) }
            .sorted { $0.sampledAt < $1.sampledAt }
        let owns = { (row: HistoryQuotaRow) in
            accountFingerprint == nil || row.accountFingerprint == nil || row.accountFingerprint == accountFingerprint
        }
        let matching = candidates.filter(owns)
        let away = awayIntervals(candidates, owns: owns, now: now)
        let observed = matching.filter { $0.sampledAt > start && sameReset($0.resetsAt, reset) }.map(point)
        let origin = ForecastPoint(date: start, remaining: 100)
        let current = ForecastPoint(date: now, remaining: remaining)
        let points = [origin] + observed + [current]
        let boosts = zip(points, points.dropFirst()).compactMap { previous, next in
            next.remaining - previous.remaining > boostThreshold && !crosses(away, previous, next) ? next : nil
        }
        let horizon = Horizon.of(durationMinutes: minutes)
        let previous = horizon.spansPreviousWindows ? matching.filter { $0.sampledAt < start }.map(point) : []
        let timeline = previous + points
        return QuotaForecast(
            provider: provider, windowID: window.id, displayName: window.displayName, start: start, reset: reset,
            now: now, points: points, remaining: remaining, boosts: boosts, away: away,
            pointsPerHour: pace(timeline, away: away, span: horizon.pace, minimum: horizon.minimumPace, now: now),
            recentPointsPerHour: pace(
                timeline, away: away, span: horizon.recent, minimum: horizon.minimumRecent, now: now))
    }

    private static func matches(_ row: HistoryQuotaRow, provider: UsageProvider, window: QuotaWindow, now: Date) -> Bool
    {
        row.provider == provider && row.windowID == window.id && row.sampledAt < now && row.usedPercentage.isFinite
            && (0...100).contains(row.usedPercentage)
    }

    private static func sameReset(_ rowReset: Date?, _ reset: Date) -> Bool {
        rowReset.map { abs($0.timeIntervalSince(reset)) <= resetTolerance } ?? false
    }

    private static func point(_ row: HistoryQuotaRow) -> ForecastPoint {
        ForecastPoint(date: row.sampledAt, remaining: 100 - row.usedPercentage)
    }

    static func pace(
        _ timeline: [ForecastPoint], away: [DateInterval], span: TimeInterval, minimum: TimeInterval, now: Date
    ) -> Double? {
        guard let first = timeline.first else { return nil }
        let cutoff = max(now.addingTimeInterval(-span), first.date)
        let window =
            [ForecastPoint(date: cutoff, remaining: interpolatedRemaining(timeline, at: cutoff))]
            + timeline.filter { $0.date > cutoff }
        let steps = zip(window, window.dropFirst()).filter { !crosses(away, $0.0, $0.1) }
        let elapsed = steps.reduce(0) { $0 + $1.1.date.timeIntervalSince($1.0.date) }
        guard elapsed >= minimum else { return nil }
        let consumed = steps.reduce(0) { $0 + max(0, $1.0.remaining - $1.1.remaining) }
        return consumed / (elapsed / 3600)
    }

    public static func crosses(_ away: [DateInterval], _ from: ForecastPoint, _ to: ForecastPoint) -> Bool {
        away.contains { $0.start < to.date && $0.end > from.date }
    }

    static func awayIntervals(_ rows: [HistoryQuotaRow], owns: (HistoryQuotaRow) -> Bool, now: Date) -> [DateInterval] {
        var intervals: [DateInterval] = []
        var leftAt: Date?
        for row in rows {
            if !owns(row) {
                leftAt = leftAt ?? row.sampledAt
            } else if let start = leftAt {
                intervals.append(DateInterval(start: start, end: row.sampledAt))
                leftAt = nil
            }
        }
        if let start = leftAt, start < now { intervals.append(DateInterval(start: start, end: now)) }
        return intervals
    }

    public static func interpolatedRemaining(_ points: [ForecastPoint], at date: Date) -> Double {
        guard let index = points.firstIndex(where: { $0.date >= date }) else { return points.last?.remaining ?? 100 }
        guard index > 0 else { return points[index].remaining }
        let before = points[index - 1]
        let after = points[index]
        let interval = after.date.timeIntervalSince(before.date)
        guard interval > 0 else { return after.remaining }
        return before.remaining + (after.remaining - before.remaining) * date.timeIntervalSince(before.date) / interval
    }

    private func exhaustion(pace: Double?) -> Date? {
        guard let pace, pace > 0, remaining > 0 else { return nil }
        let hours = remaining / pace
        return hours < hoursLeft ? now.addingTimeInterval(hours * 3600) : nil
    }
}
