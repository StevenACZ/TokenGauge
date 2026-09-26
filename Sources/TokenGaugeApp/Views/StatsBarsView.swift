import SwiftUI
import TokenGaugeCore

struct StatsBarsView: View {
    let days: [StatsDayTotal]
    let typical: Int?
    let providers: [UsageProvider]
    let locale: Locale
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAnimationsEnabled) private var animateChanges
    @State private var grown = false
    @State private var hovered: String?

    private let chartHeight: CGFloat = 70

    private var maximum: Int { max(1, days.compactMap(\.total).max() ?? 1, typical ?? 0) }
    private var focus: StatsDayTotal? { days.first { $0.id == hovered } ?? days.last }

    static func color(_ segment: StatsSegment, providers: [UsageProvider]) -> Color {
        if segment.id == StatsSummary.otherLabel { return Color.secondary.opacity(0.35) }
        let base = segment.provider == .claude ? Theme.claude : Theme.codex
        if providers.count > 1 { return base }
        switch segment.rank {
        case 0: return base
        case 1: return Color(nsColor: NSColor(base).blended(withFraction: 0.45, of: .white) ?? NSColor(base))
        default: return base.opacity(0.4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        bar(day, index: index)
                    }
                }
                .frame(height: chartHeight, alignment: .bottom)
                if let typical, typical > 0 {
                    typicalLine(typical)
                }
            }
            HStack(spacing: 4) {
                ForEach(days) { day in
                    Text(day.date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                        .font(.system(size: 8, weight: day.id == days.last?.id ? .semibold : .regular))
                        .foregroundStyle(day.id == focus?.id ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            guard !grown else { return }
            if animateChanges && !reduceMotion {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.15)) { grown = true }
            } else {
                grown = true
            }
        }
    }

    private var caption: some View {
        HStack(spacing: 6) {
            if let focus {
                Text(focus.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale)))
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(focus.total.map(UsageFormatters.tokens) ?? "history.unknown".localized)
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .animation(.easeOut(duration: 0.15), value: focus?.id)
    }

    private func bar(_ day: StatsDayTotal, index: Int) -> some View {
        let height = CGFloat(day.total ?? 0) / CGFloat(maximum) * chartHeight
        let isFocus = day.id == focus?.id
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                ForEach(day.segments) { segment in
                    Rectangle()
                        .fill(Self.color(segment, providers: providers))
                        .frame(height: segmentHeight(segment, of: day, height: height))
                }
            }
            .frame(height: max(day.total == nil ? 0 : 2, height), alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .scaleEffect(y: grown || !(animateChanges && !reduceMotion) ? 1 : 0.02, anchor: .bottom)
            .animation(
                animateChanges && !reduceMotion
                    ? .spring(response: 0.55, dampingFraction: 0.8).delay(0.012 * Double(index)) : nil,
                value: grown)
            if day.total == nil {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(width: 5, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(tint.opacity(isFocus && hovered != nil ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = day.id } else if hovered == day.id { hovered = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            day.date.formatted(.dateTime.weekday(.wide).day().month().locale(locale)) + ": "
                + (day.total.map(UsageFormatters.tokens) ?? "history.unknown".localized))
    }

    private func segmentHeight(_ segment: StatsSegment, of day: StatsDayTotal, height: CGFloat) -> CGFloat {
        let total = CGFloat(max(1, day.total ?? 1))
        let share = CGFloat(segment.tokens) / total
        return max(0, height * share - 1)
    }

    private func typicalLine(_ typical: Int) -> some View {
        let y = chartHeight - CGFloat(typical) / CGFloat(maximum) * chartHeight
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: 2_000, y: y))
            }
            .stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Text("stats.daily.typical".localized)
                .font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 3)
                .background(Theme.panelBackground.opacity(0.85))
                .offset(y: y - 12)
        }
        .frame(height: chartHeight)
        .clipped()
        .allowsHitTesting(false)
    }
}
