import AppKit

final class WeeklyStatusPillView: NSView {
    var presentation = WeeklyPillPresentation(snapshot: nil) {
        didSet { needsDisplay = true }
    }
    var showsRisk = false {
        didSet { needsDisplay = true }
    }
    var onHoverChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.34).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.27).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        let money = attributed("💰", color: .white, size: 11, weight: .medium)
        let percent = attributed(presentation.remaining, color: .white, size: 10.5, weight: .semibold)
        let divider = attributed("｜", color: .white.withAlphaComponent(0.48), size: 11, weight: .medium)
        let calendar = attributed("📅", color: .white.withAlphaComponent(0.78), size: 11, weight: .medium)
        let reset = attributed(presentation.resetDate, color: .white.withAlphaComponent(0.78), size: 10.5, weight: .medium)
        let parts = [money, percent, divider, calendar, reset]
        let gaps: [CGFloat] = [10, 9, 9, 10]
        let totalWidth = parts.reduce(CGFloat.zero) { $0 + $1.size().width } + gaps.reduce(0, +)
        var x = (bounds.width - totalWidth) / 2 - (showsRisk ? 3 : 0)
        for (index, part) in parts.enumerated() {
            let size = part.size()
            part.draw(at: NSPoint(x: x, y: bounds.midY - size.height / 2))
            x += size.width
            if index < gaps.count { x += gaps[index] }
        }

        if showsRisk {
            NSColor(calibratedRed: 1, green: 0.7, blue: 0.27, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 10, y: bounds.midY - 2.5, width: 5, height: 5)).fill()
        }
    }

    private func attributed(_ text: String, color: NSColor, size: CGFloat, weight: NSFont.Weight) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .kern: 0.05
            ]
        )
    }
}
