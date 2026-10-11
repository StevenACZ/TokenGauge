import AppKit
import SwiftUI
import TokenGaugeCore

struct MenuBarTourState: Equatable {
    enum Step: String, CaseIterable, Identifiable {
        case click, panel
        case rightClick = "right_click"
        case hover

        var id: String { rawValue }
        var titleKey: String { "settings.tour.\(rawValue).title" }
        var textKey: String { "settings.tour.\(rawValue).text" }

        var symbol: String {
            switch self {
            case .click: "cursorarrow.click"
            case .panel: "macwindow"
            case .rightClick: "contextualmenu.and.cursorarrow"
            case .hover: "cursorarrow.rays"
            }
        }
    }

    enum Phase: Int, Comparable {
        case rest, point, press, open

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Mock { case panel, menu, tooltip }
    enum Cursor { case start, indicator, panelHeader }

    var step: Step
    var phase: Phase

    var mock: Mock? {
        switch step {
        case .click: phase == .open ? .panel : nil
        case .panel: .panel
        case .rightClick: phase == .open ? .menu : nil
        case .hover: phase == .open ? .tooltip : nil
        }
    }

    var cursor: Cursor {
        switch step {
        case .click: phase == .rest ? .start : .indicator
        case .panel: .panelHeader
        case .rightClick: phase == .rest ? .panelHeader : .indicator
        case .hover: .indicator
        }
    }

    private var clicks: Bool { step == .click || step == .rightClick }
    var pointing: Bool { clicks && phase == .point }
    var pressed: Bool { clicks && phase >= .press }
    var highlightsIndicator: Bool { mock == .panel || mock == .menu || (clicks && phase == .press) }
    var highlightsPanel: Bool { step == .panel && phase == .open }

    static func script(animated: Bool) -> [(state: MenuBarTourState, seconds: Double)] {
        guard animated else { return Step.allCases.map { (MenuBarTourState(step: $0, phase: .open), 3.2) } }
        return [
            (MenuBarTourState(step: .click, phase: .rest), 0.35),
            (MenuBarTourState(step: .click, phase: .point), 0.8),
            (MenuBarTourState(step: .click, phase: .press), 0.25),
            (MenuBarTourState(step: .click, phase: .open), 2.2),
            (MenuBarTourState(step: .panel, phase: .point), 0.6),
            (MenuBarTourState(step: .panel, phase: .open), 2.6),
            (MenuBarTourState(step: .rightClick, phase: .rest), 0.35),
            (MenuBarTourState(step: .rightClick, phase: .point), 0.7),
            (MenuBarTourState(step: .rightClick, phase: .press), 0.25),
            (MenuBarTourState(step: .rightClick, phase: .open), 2.8),
            (MenuBarTourState(step: .hover, phase: .rest), 0.6),
            (MenuBarTourState(step: .hover, phase: .open), 2.6),
        ]
    }
}

struct MenuBarTourStage: View {
    let presentation: MenuBarPresentation
    let mode: UsageDisplayMode
    let privacy: Bool
    let state: MenuBarTourState?
    let motion: Bool

    static let barHeight: CGFloat = 28
    static let collapsedHeight: CGFloat = 46
    static let expandedHeight: CGFloat = 196
    static let panelWidth: CGFloat = 212
    static let menuWidth: CGFloat = 190
    static let captionWidth: CGFloat = 190

    private static let history: [CGFloat] = [5, 9, 4, 12, 7, 3, 10, 14, 6, 9, 12, 5, 8, 11]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Theme.codex.opacity(0.75), Color.purple.opacity(0.45), Theme.claude.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            bar.frame(maxHeight: .infinity, alignment: .top)
            if let state {
                caption(state.step).padding(12).transition(.opacity)
            }
        }
        .overlayPreferenceValue(IndicatorAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let state { layer(state, indicator: proxy[anchor], bounds: proxy.size) }
            }
        }
        .frame(height: state == nil ? Self.collapsedHeight : Self.expandedHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var bar: some View {
        let key = "\(presentation.accessibilityLabel)|\(presentation.style)|\(presentation.size)"
        return HStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                menus([30, 38, 26])
                menus([30])
                menus([])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                Image(nsImage: presentation.renderedImage())
                    .id(key)
                    .transition(motion ? .scale(scale: 0.82).combined(with: .opacity) : .opacity)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(state?.highlightsIndicator == true ? 0.18 : 0))
            )
            .anchorPreference(key: IndicatorAnchorKey.self, value: .bounds) { $0 }
            .animation(motion ? Theme.Motion.content : nil, value: key)
            Group {
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(verbatim: "9:41").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.75))
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: Self.barHeight)
        .background(.ultraThinMaterial)
    }

    private func menus(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 13, weight: .semibold))
            Text("app.name".localized).font(.system(size: 13, weight: .bold)).lineLimit(1)
            ForEach(widths, id: \.self) { width in
                Capsule().fill(Color.primary.opacity(0.22)).frame(width: width, height: 6)
            }
        }
    }

    private func caption(_ step: MenuBarTourState.Step) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(step.titleKey.localized, systemImage: step.symbol).font(.callout.weight(.semibold))
            Text(step.textKey.localized).font(.caption).foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(MenuBarTourState.Step.allCases) { item in
                    Circle().fill(Color.primary.opacity(item == step ? 0.8 : 0.22)).frame(width: 5, height: 5)
                }
            }
            .padding(.top, 2)
            .accessibilityHidden(true)
        }
        .padding(11)
        .frame(width: Self.captionWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func layer(_ state: MenuBarTourState, indicator: CGRect, bounds: CGSize) -> some View {
        let top = Self.barHeight + 5
        let clear = Self.captionWidth + 20
        let panelX = min(max(indicator.midX - Self.panelWidth / 2, clear), bounds.width - Self.panelWidth - 8)
        let menuX = min(max(indicator.minX, clear), bounds.width - Self.menuWidth - 8)
        let onIndicator = CGPoint(x: indicator.midX, y: indicator.midY + 3)
        let cursor: CGPoint
        switch state.cursor {
        case .start: cursor = CGPoint(x: max(indicator.midX - 150, 40), y: bounds.height - 30)
        case .indicator: cursor = onIndicator
        case .panelHeader: cursor = CGPoint(x: panelX + Self.panelWidth - 46, y: top + 16)
        }
        let pop: AnyTransition = motion ? .scale(scale: 0.92, anchor: .top).combined(with: .opacity) : .opacity
        return ZStack(alignment: .topLeading) {
            if state.mock == .panel {
                panelMock(highlighted: state.highlightsPanel).offset(x: panelX, y: top).transition(pop)
            }
            if state.mock == .menu {
                menuMock.offset(x: menuX, y: top).transition(pop)
            }
            if state.mock == .tooltip {
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: onIndicator.x + 12, maxHeight: 1).layoutPriority(1)
                    tooltipMock.fixedSize().layoutPriority(1)
                    Spacer(minLength: 8)
                }
                .frame(width: bounds.width)
                .offset(y: indicator.maxY + 14)
                .transition(.opacity)
            }
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 26, height: 26)
                .scaleEffect(state.pressed ? 1.7 : 0.5)
                .opacity(state.pointing ? 0.9 : 0)
                .position(onIndicator)
            Image(systemName: "cursorarrow")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.black)
                .shadow(color: .white, radius: 0.6)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .scaleEffect(state.pressed && state.phase == .press ? 0.85 : 1, anchor: .topLeading)
                .position(x: cursor.x + 6, y: cursor.y + 8)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func panelMock(highlighted: Bool) -> some View {
        let outline = Color.accentColor.opacity(highlighted ? 1 : 0)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 13, height: 13)
                Text("app.name".localized).font(.system(size: 9.5, weight: .semibold))
                Spacer(minLength: 0)
                Group {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                        Image(systemName: privacy ? "eye.slash" : "eye")
                        Image(systemName: "gearshape")
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(outline, lineWidth: 1.5))
                    Image(systemName: "arrow.clockwise")
                }
                .font(.system(size: 8.5)).foregroundStyle(.secondary)
            }
            HStack(spacing: 2) {
                ForEach(UsageDisplayMode.allCases) { item in
                    Text(item.titleKey.localized)
                        .font(.system(size: 8.5, weight: item == mode ? .semibold : .regular))
                        .foregroundStyle(item == mode ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(item == mode ? 0.1 : 0)))
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(outline, lineWidth: 1.5))
            VStack(spacing: 5) {
                ForEach(Array(presentation.segments.prefix(4).enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 5) {
                        mark(segment).frame(width: 11, height: 11)
                        Text(segment.label ?? "")
                            .font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 26, alignment: .leading)
                        GaugeBar(
                            fraction: (segment.remainingPercentage ?? 0) / 100,
                            tint: Color(nsColor: segment.graphicColor))
                        Text(segment.text)
                            .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                    .frame(height: 12)
                }
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(Self.history.enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(index == Self.history.count - 1 ? 0.45 : 0.16))
                        .frame(height: height)
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
        .padding(9)
        .frame(width: Self.panelWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    @ViewBuilder
    private func mark(_ segment: MenuBarPresentation.Segment) -> some View {
        let color = segment.markColor ?? segment.graphicColor
        if segment.account == nil {
            ProviderLogo(provider: segment.provider, size: 10)
        } else if let icon = segment.icon,
            let image = AccountIconArt.image(icon, letter: segment.letter, color: color, size: 10)
        {
            Image(nsImage: image)
        } else {
            Circle().fill(Color(nsColor: color)).frame(width: 6, height: 6)
        }
    }

    private var menuMock: some View {
        let provider = presentation.segments.last { $0.account == nil }?.provider ?? .claude
        return VStack(alignment: .leading, spacing: 1) {
            menuHeader("provider.\(provider.rawValue)".localized)
            menuRow("menu.quick.show_in_bar".localized, checked: true)
            Divider().padding(.vertical, 3)
            menuHeader("settings.indicator_style".localized)
            ForEach(QuotaMenuBarStyle.allCases) { style in
                menuRow(style.titleKey.localized, checked: presentation.style == style)
            }
            Divider().padding(.vertical, 3)
            menuRow("settings.hide_account".localized, checked: privacy)
        }
        .padding(.vertical, 6)
        .frame(width: Self.menuWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func menuHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 15)
    }

    private func menuRow(_ title: String, checked: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                .opacity(checked ? 1 : 0)
            Text(title).font(.system(size: 11.5)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 17)
    }

    private var tooltipMock: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(presentation.segments.prefix(5).enumerated()), id: \.offset) { _, segment in
                Text(segment.description).font(.system(size: 10.5)).lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.18)))
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
}

private struct IndicatorAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
