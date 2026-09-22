import SwiftUI

struct ResetCreditsBadge: View {
    let count: Int

    var body: some View {
        Text(UsageFormatters.resetCredits(count))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .background(Capsule().fill(Color.primary.opacity(0.05)).padding(.vertical, -2))
            .help(UsageFormatters.resetCreditsAvailable(count))
            .accessibilityLabel(UsageFormatters.resetCreditsAvailable(count))
    }
}
