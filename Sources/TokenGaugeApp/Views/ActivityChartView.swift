import Charts
import SwiftUI
import TokenGaugeCore

private struct ActivityPoint: Identifiable {
    let date: Date
    let provider: UsageProvider
    let tokens: Int

    var id: String { "\(provider.rawValue)-\(date.timeIntervalSince1970)" }
}

struct ActivityChartView: View {
    let claude: ProviderUsageSnapshot?
    let codex: ProviderUsageSnapshot?

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset - 6, to: today)
        }
    }

    private var points: [ActivityPoint] {
        let snapshots = Dictionary(
            uniqueKeysWithValues: [claude, codex].compactMap { snapshot in
                snapshot.map { ($0.provider, $0) }
            })
        return days.flatMap { date in
            UsageProvider.allCases.map { provider in
                let usage = snapshots[provider]?.dailyUsage.first { $0.day == Self.dayKey(date) }?.tokens ?? 0
                return ActivityPoint(date: date, provider: provider, tokens: usage)
            }
        }
    }

    private var chartDomain: ClosedRange<Date> {
        let half: TimeInterval = 43_200
        let first = days.first ?? Date()
        let last = days.last ?? Date()
        return first.addingTimeInterval(-half)...last.addingTimeInterval(half)
    }

    private var maximumTokens: Int {
        max(points.map(\.tokens).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("activity.title".localized)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                legend
            }

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("activity.day".localized, point.date, unit: .day),
                        y: .value("activity.tokens".localized, point.tokens),
                        width: .fixed(9)
                    )
                    .position(by: .value("activity.provider".localized, point.provider.rawValue), span: .fixed(20))
                    .foregroundStyle(point.provider == .claude ? Theme.claude : Theme.codex)
                    .cornerRadius(2.5)
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: 0...maximumTokens)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: days) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                            Text(date, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 9, weight: selected ? .bold : .regular))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.09))
                        .frame(height: 1)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case .active(let location) = phase, let plotFrame = proxy.plotFrame else { return }
                            let frame = geometry[plotFrame]
                            guard frame.contains(location) else { return }
                            let xPosition = location.x - frame.minX
                            guard let date: Date = proxy.value(atX: xPosition) else { return }
                            selectedDate = Calendar.current.startOfDay(for: date)
                        }
                }
            }
            .frame(height: 58)

            Text(selectedSummary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var selectedSummary: String {
        let day = selectedDate.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .day()
                .locale(Locale(identifier: LocalizationManager.shared.language.rawValue))
        )
        let claudeTokens =
            points.first {
                $0.provider == .claude && Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
            }?.tokens ?? 0
        let codexTokens =
            points.first {
                $0.provider == .codex && Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
            }?.tokens ?? 0
        return "activity.selected".localized(
            day,
            UsageFormatters.tokens(claudeTokens),
            UsageFormatters.tokens(codexTokens)
        )
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem(color: Theme.claude, title: "provider.claude_short".localized)
            legendItem(color: Theme.codex, title: "provider.codex".localized)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
    }

    private static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
