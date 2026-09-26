import SwiftUI
import TokenGaugeCore

struct ForecastChartView: View {
    let forecast: QuotaForecast
    let tint: Color
    let locale: Locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    @State private var drawn: CGFloat = 0
    @State private var projected: CGFloat = 0
    @State private var hoverDate: Date?

    static let height: CGFloat = 138
    private let inset = EdgeInsets(top: 14, leading: 30, bottom: 18, trailing: 6)

    private var animates: Bool { animateChanges && !reduceMotion }
    private var drawProgress: CGFloat { animates ? drawn : 1 }
    private var projectionProgress: CGFloat { animates ? projected : 1 }
    private var danger: Bool { forecast.runsOutAt != nil || forecast.remaining <= 0 }
    private var projectionTint: Color { danger ? .red : tint }

    var body: some View {
        GeometryReader { proxy in
            let plot = CGRect(
                x: inset.leading, y: inset.top, width: max(1, proxy.size.width - inset.leading - inset.trailing),
                height: max(1, proxy.size.height - inset.top - inset.bottom))
            ZStack(alignment: .topLeading) {
                grid(plot)
                awayBands(plot)
                area(plot)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(Double(drawProgress))
                line(plot).trim(from: 0, to: drawProgress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let recent = recentProjection(plot) {
                    recent.trim(from: 0, to: projectionProgress)
                        .stroke(
                            Color.secondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1.5, 3.5]))
                }
                projection(plot).trim(from: 0, to: projectionProgress)
                    .stroke(
                        projectionTint.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [5, 4]))
                markers(plot)
                if let hoverDate { hoverOverlay(plot, date: hoverDate) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let fraction = min(max((location.x - plot.minX) / plot.width, 0), 1)
                    hoverDate = forecast.start.addingTimeInterval(Double(fraction) * span)
                case .ended:
                    hoverDate = nil
                }
            }
        }
        .frame(height: Self.height)
        .onAppear(perform: play)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var span: TimeInterval { max(1, forecast.reset.timeIntervalSince(forecast.start)) }

    private func x(_ date: Date, _ plot: CGRect) -> CGFloat {
        plot.minX + CGFloat(min(max(date.timeIntervalSince(forecast.start) / span, 0), 1)) * plot.width
    }

    private func y(_ remaining: Double, _ plot: CGRect) -> CGFloat {
        plot.maxY - CGFloat(min(max(remaining, 0), 100) / 100) * plot.height
    }

    private func play() {
        guard animates else {
            drawn = 1
            projected = 1
            return
        }
        drawn = 0
        projected = 0
        withAnimation(.easeOut(duration: 0.75)) { drawn = 1 }
        withAnimation(.easeInOut(duration: 0.5).delay(0.6)) { projected = 1 }
    }

    private var segments: [[ForecastPoint]] {
        let starts = Set(forecast.boosts.map(\.date))
        var result: [[ForecastPoint]] = []
        for point in forecast.points {
            if let last = result.last?.last,
                !starts.contains(point.date) && !QuotaForecast.crosses(forecast.away, last, point)
            {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    private func awayInterval(at date: Date) -> DateInterval? {
        forecast.away.first { $0.start <= date && date <= $0.end && $0.end > forecast.start }
    }

    private func awayLabel(_ interval: DateInterval) -> String {
        let left = forecast.points.last { $0.date <= interval.start }?.remaining
        let back = forecast.points.first { $0.date >= interval.end }?.remaining
        return "stats.chart.away".localized(
            left.map(UsageFormatters.percentage) ?? "—", back.map(UsageFormatters.percentage) ?? "—")
    }

    private func awayBands(_ plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(forecast.away.filter { $0.end > forecast.start }, id: \.start) { interval in
                let minX = x(interval.start, plot)
                let width = x(interval.end, plot) - minX
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: max(1, width), height: plot.height)
                    .position(x: minX + width / 2, y: plot.midY)
                if width >= 16 {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .position(x: minX + width / 2, y: plot.minY + 9)
                        .accessibilityHidden(true)
                }
            }
        }
        .opacity(Double(drawProgress))
        .allowsHitTesting(false)
    }

    private func line(_ plot: CGRect) -> Path {
        Path { path in
            for segment in segments {
                for (index, point) in segment.enumerated() {
                    let location = CGPoint(x: x(point.date, plot), y: y(point.remaining, plot))
                    if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
                }
            }
        }
    }

    private func area(_ plot: CGRect) -> Path {
        Path { path in
            for segment in segments {
                guard let first = segment.first, let last = segment.last else { continue }
                path.move(to: CGPoint(x: x(first.date, plot), y: plot.maxY))
                for point in segment {
                    path.addLine(to: CGPoint(x: x(point.date, plot), y: y(point.remaining, plot)))
                }
                path.addLine(to: CGPoint(x: x(last.date, plot), y: plot.maxY))
                path.closeSubpath()
            }
        }
    }

    private func projectionPath(pace: Double?, runsOut: Date?, _ plot: CGRect) -> Path? {
        guard let pace, forecast.remaining > 0 else { return nil }
        let start = CGPoint(x: x(forecast.now, plot), y: y(forecast.remaining, plot))
        return Path { path in
            path.move(to: start)
            if let runsOut {
                path.addLine(to: CGPoint(x: x(runsOut, plot), y: plot.maxY))
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            } else {
                path.addLine(
                    to: CGPoint(x: plot.maxX, y: y(forecast.remaining - pace * forecast.hoursLeft, plot)))
            }
        }
    }

    private func projection(_ plot: CGRect) -> Path {
        projectionPath(pace: forecast.pointsPerHour, runsOut: forecast.runsOutAt, plot) ?? Path()
    }

    private func recentProjection(_ plot: CGRect) -> Path? {
        guard let recent = forecast.recentPointsPerHour, let average = forecast.pointsPerHour,
            abs(recent - average) * forecast.hoursLeft >= 5
        else { return nil }
        return projectionPath(pace: recent, runsOut: forecast.recentRunsOutAt, plot)
    }

    private func grid(_ plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([0.0, 50.0, 100.0], id: \.self) { value in
                Path { path in
                    path.move(to: CGPoint(x: plot.minX, y: y(value, plot)))
                    path.addLine(to: CGPoint(x: plot.maxX, y: y(value, plot)))
                }
                .stroke(Color.primary.opacity(value == 0 ? 0.14 : 0.07), lineWidth: 1)
                Text("\(Int(value))%")
                    .font(.system(size: 8, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: plot.minX - 5, alignment: .trailing)
                    .position(x: (plot.minX - 5) / 2, y: y(value, plot))
            }
            ForEach(forecast.isSession ? hourTicks(plot) : dayTicks(plot), id: \.date) { tick in
                Text(tick.label)
                    .font(.system(size: 8, weight: tick.isCurrent ? .semibold : .regular))
                    .foregroundStyle(tick.isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .position(x: tick.x, y: plot.maxY + 10)
            }
        }
    }

    private struct AxisTick {
        let date: Date
        let x: CGFloat
        let label: String
        let isCurrent: Bool
    }

    private func hourTicks(_ plot: CGRect) -> [AxisTick] {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .hour, for: forecast.now)?.start
        var hour = calendar.dateInterval(of: .hour, for: forecast.start)?.end ?? forecast.reset
        var ticks: [AxisTick] = []
        while hour < forecast.reset {
            if hour.timeIntervalSince(forecast.start) >= 600, forecast.reset.timeIntervalSince(hour) >= 600 {
                ticks.append(
                    AxisTick(
                        date: hour, x: x(hour, plot), label: hour.formatted(.dateTime.hour().locale(locale)),
                        isCurrent: hour == current))
            }
            hour = calendar.date(byAdding: .hour, value: 1, to: hour) ?? forecast.reset
        }
        return ticks
    }

    private func dayTicks(_ plot: CGRect) -> [AxisTick] {
        let calendar = Calendar.current
        var ticks: [AxisTick] = []
        var day = calendar.startOfDay(for: forecast.start)
        let today = calendar.startOfDay(for: forecast.now)
        while day < forecast.reset {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? forecast.reset
            let middle = Date(
                timeIntervalSince1970: (max(day, forecast.start).timeIntervalSince1970
                    + min(next, forecast.reset).timeIntervalSince1970) / 2)
            if min(next, forecast.reset).timeIntervalSince(max(day, forecast.start)) >= 6 * 3600 {
                ticks.append(
                    AxisTick(
                        date: day, x: x(middle, plot),
                        label: day.formatted(.dateTime.weekday(.narrow).locale(locale)),
                        isCurrent: day == today))
            }
            day = next
        }
        return ticks
    }

    private func markers(_ plot: CGRect) -> some View {
        let nowX = x(forecast.now, plot)
        let nowY = y(forecast.remaining, plot)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: nowX, y: plot.minY - 6))
                path.addLine(to: CGPoint(x: nowX, y: plot.maxY))
            }
            .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            Path { path in
                path.move(to: CGPoint(x: plot.maxX, y: plot.minY - 6))
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            }
            .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            Text("stats.chart.now".localized(UsageFormatters.percentage(forecast.remaining)))
                .font(.system(size: 8, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .position(x: min(max(nowX, plot.minX + 26), plot.maxX - 60), y: plot.minY - 8)
            Text("stats.chart.reset".localized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .fixedSize()
                .position(x: plot.maxX - 18, y: plot.minY - 8)
                .opacity(nowX < plot.maxX - 100 ? 1 : 0)
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(tint, lineWidth: 2.5))
                .frame(width: 9, height: 9)
                .position(x: nowX, y: nowY)
                .scaleEffect(drawProgress >= 1 ? 1 : 0.01, anchor: .center)
                .animation(animates ? .spring(response: 0.35, dampingFraction: 0.6) : nil, value: drawProgress >= 1)
            ForEach(forecast.boosts, id: \.date) { boost in
                Image(systemName: "arrow.up")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color.green))
                    .position(x: x(boost.date, plot), y: plot.maxY)
                    .opacity(Double(drawProgress))
                    .help("stats.chart.boost".localized)
            }
            if let runsOut = forecast.runsOutAt {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color.red))
                    .position(x: x(runsOut, plot), y: plot.maxY)
                    .opacity(Double(projectionProgress))
            }
        }
    }

    private func hoverOverlay(_ plot: CGRect, date: Date) -> some View {
        let isFuture = date > forecast.now
        let away = awayInterval(at: date)
        let value: Double? =
            away != nil
            ? nil
            : isFuture
                ? forecast.pointsPerHour.map {
                    max(0, forecast.remaining - $0 * date.timeIntervalSince(forecast.now) / 3600)
                }
                : QuotaForecast.interpolatedRemaining(forecast.points, at: date)
        let px = x(date, plot)
        let label =
            date.formatted(
                forecast.isSession
                    ? .dateTime.hour().minute().locale(locale)
                    : .dateTime.weekday(.abbreviated).hour().minute().locale(locale)) + " · "
            + (away.map(awayLabel)
                ?? value.map { (isFuture ? "stats.chart.expected".localized : "") + UsageFormatters.percentage($0) }
                ?? "—")
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: px, y: plot.minY))
                path.addLine(to: CGPoint(x: px, y: plot.maxY))
            }
            .stroke(Color.primary.opacity(0.35), lineWidth: 1)
            if let value {
                Circle().fill(isFuture ? projectionTint : tint).frame(width: 6, height: 6)
                    .position(x: px, y: y(value, plot))
            }
            Text(label)
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Theme.panelBackground)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12)))
                )
                .fixedSize()
                .position(x: min(max(px, plot.minX + 55), plot.maxX - 55), y: plot.minY + 10)
        }
        .allowsHitTesting(false)
    }

    private var accessibilitySummary: String {
        let now = UsageFormatters.percentage(forecast.remaining)
        guard let projected = forecast.projectedRemainingAtReset else { return now }
        return now + " · " + "stats.chart.expected".localized + UsageFormatters.percentage(max(0, projected))
    }
}
