import SwiftUI
import TokenGaugeCore

struct QuotaPaceLabel: View {
    let pace: QuotaPace?

    var body: some View {
        Text(pace.map { "pace.value".localized(number($0.pointsPerHour)) } ?? "pace.collecting".localized)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .help(pace.map { "pace.details".localized(number($0.observedMinutes)) } ?? "pace.insufficient".localized)
    }

    private func number(_ value: Double) -> String {
        value.formatted(
            .number.precision(.fractionLength(1)).locale(
                Locale(identifier: LocalizationManager.shared.language.rawValue)))
    }
}
