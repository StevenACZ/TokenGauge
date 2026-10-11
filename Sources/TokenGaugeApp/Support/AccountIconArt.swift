import AppKit
import SwiftUI
import TokenGaugeCore

extension ClaudeExtraAccount.Icon {
    var symbol: String? {
        switch self {
        case .dot: "circle.fill"
        case .balloon: nil
        case .briefcase: "briefcase.fill"
        case .house: "house.fill"
        case .person: "person.fill"
        case .building: "building.2.fill"
        case .letter: nil
        }
    }
}

enum AccountIconArt {
    static func balloonPath(in rect: CGRect) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = CGMutablePath()
        path.move(to: point(0.5, 0.02))
        path.addCurve(to: point(0.88, 0.37), control1: point(0.71, 0.02), control2: point(0.88, 0.17))
        path.addCurve(to: point(0.62, 0.71), control1: point(0.88, 0.53), control2: point(0.72, 0.62))
        path.addLine(to: point(0.38, 0.71))
        path.addCurve(to: point(0.12, 0.37), control1: point(0.28, 0.62), control2: point(0.12, 0.53))
        path.addCurve(to: point(0.5, 0.02), control1: point(0.12, 0.17), control2: point(0.29, 0.02))
        path.closeSubpath()
        for (top, bottom) in [(0.39, 0.42), (0.61, 0.58)] {
            path.move(to: point(top - 0.035, 0.7))
            path.addLine(to: point(top + 0.035, 0.7))
            path.addLine(to: point(bottom + 0.03, 0.82))
            path.addLine(to: point(bottom - 0.03, 0.82))
            path.closeSubpath()
        }
        path.addRoundedRect(
            in: CGRect(origin: point(0.38, 0.8), size: CGSize(width: rect.width * 0.24, height: rect.height * 0.18)),
            cornerWidth: rect.width * 0.04, cornerHeight: rect.width * 0.04)
        return path
    }

    static func letterImage(_ letter: String, color: NSColor, size: CGFloat) -> NSImage {
        let base = NSFont.systemFont(ofSize: (size * 0.86).rounded(), weight: .heavy)
        let font =
            base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: letter,
                attributes: [
                    .font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                ]))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return NSImage(size: NSSize(width: ceil(ink.width) + 1, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(color.cgColor)
            context.textPosition = CGPoint(
                x: (rect.width - ink.width) / 2 - ink.minX, y: (rect.height - ink.height) / 2 - ink.minY)
            CTLineDraw(line, context)
            return true
        }
    }

    static func swatch(_ color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    static func image(_ icon: ClaudeExtraAccount.Icon, letter: String = "", color: NSColor, size: CGFloat) -> NSImage? {
        if icon == .letter { return letterImage(letter, color: color, size: size) }
        guard let symbol = icon.symbol else {
            return NSImage(size: NSSize(width: size * 0.8, height: size), flipped: true) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.addPath(balloonPath(in: rect))
                context.setFillColor(color.cgColor)
                context.fillPath()
                return true
            }
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: (size * 0.82).rounded(), weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
}

struct HotAirBalloonShape: Shape {
    func path(in rect: CGRect) -> Path { Path(AccountIconArt.balloonPath(in: rect)) }
}
