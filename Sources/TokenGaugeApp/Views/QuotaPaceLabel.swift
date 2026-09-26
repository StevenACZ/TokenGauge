import SwiftUI
import TokenGaugeCore

struct QuotaPaceDisplay {
    let current: QuotaPace?
    let previous: QuotaPace?

    var isHistorical: Bool { previous != nil && (current?.pointsPerHour ?? 0) <= 0 }
    var value: QuotaPace? { isHistorical ? previous : current }
}

struct QuotaPaceLabel: View {
    let pace: QuotaPace?
    var previousPace: QuotaPace?
    @State private var showingInfo = false

    private var display: QuotaPaceDisplay { QuotaPaceDisplay(current: pace, previous: previousPace) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(
                display.value.map {
                    (display.isHistorical ? "pace.last_value" : "pace.value").localized(
                        QuotaPaceDetailsView.number($0.pointsPerHour))
                } ?? "pace.collecting".localized
            )
            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Button {
                showingInfo.toggle()
            } label: {
                Image(systemName: "info.circle").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("pace.info_title".localized)
            .help("pace.info_title".localized)
            .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                QuotaPaceDetailsView(display: display)
            }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

struct SessionForecastLabel: View {
    let forecast: QuotaForecast

    private var pace: String { UsageFormatters.percentage(forecast.pointsPerHour ?? 0) }

    private var style: (symbol: String, tint: Color, text: String, detail: String) {
        switch forecast.verdict {
        case .runsOut(let date):
            let time = date.formatted(
                .dateTime.hour().minute().locale(Locale(identifier: LocalizationManager.shared.language.rawValue)))
            return (
                "exclamationmark.triangle.fill", .red, "session.runs_out".localized(time),
                "session.detail_runs_out".localized(
                    pace, UsageFormatters.duration(forecast.reset.timeIntervalSince(date)))
            )
        case .tight(let margin):
            return (
                "exclamationmark.circle.fill", .orange, "session.tight".localized(pace),
                "session.detail".localized(pace, UsageFormatters.percentage(max(0, margin)))
            )
        case .lasts(let margin):
            return (
                "checkmark.circle.fill", .green, "session.lasts".localized(pace),
                "session.detail".localized(pace, UsageFormatters.percentage(margin))
            )
        case .noUsage, .exhausted: return ("", .clear, "", "")
        }
    }

    var body: some View {
        let style = style
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: style.symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(style.tint)
                .accessibilityHidden(true)
            Text(style.text).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .help(style.detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.detail)
    }
}

struct QuotaPaceDetailsView: View {
    let display: QuotaPaceDisplay
    private var locale: Locale { Locale(identifier: LocalizationManager.shared.language.rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("pace.info_title".localized).font(.system(size: 12, weight: .semibold))
            Text("pace.info_explanation".localized).font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if let current = display.current {
                reading(current, title: "pace.current".localized)
            } else {
                Text((display.previous == nil ? "pace.info_waiting" : "pace.info_saved").localized)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let previous = display.previous {
                reading(previous, title: "pace.previous".localized)
            }
            Text("pace.info_method".localized).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("pace.info_retention".localized).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(width: 285)
    }

    private func reading(_ pace: QuotaPace, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 10))
                Spacer()
                Text("pace.value".localized(Self.number(pace.pointsPerHour)))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            Text(pace.sampledAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(locale)))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    static func number(_ value: Double) -> String {
        value.formatted(
            .number.precision(.fractionLength(1))
                .locale(Locale(identifier: LocalizationManager.shared.language.rawValue)))
    }
}
