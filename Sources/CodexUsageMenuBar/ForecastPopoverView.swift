import AppKit

final class ForecastPopoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    private var snapshot: UsageSnapshot?
    private var forecast = WeeklyUsageForecast(snapshot: nil)
    private var history = WeeklyUsageHistory()
    private var now = Date()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { nil }

    func update(snapshot: UsageSnapshot?, history: WeeklyUsageHistory, now: Date) {
        self.snapshot = snapshot
        self.forecast = WeeklyUsageForecast(snapshot: snapshot, now: now)
        self.history = history
        self.now = now
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: card, xRadius: 15, yRadius: 15)
        NSColor(calibratedRed: 0.065, green: 0.135, blue: 0.145, alpha: 0.97).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        drawForecast(in: card)
        drawDivider(y: 158)
        drawConsumption(in: card)
    }

    private func drawForecast(in rect: NSRect) {
        let x = rect.minX + 20
        let state: String
        let headline: String
        let detail: String
        let stateColor: NSColor

        switch forecast.pace {
        case .fast:
            state = "配速偏快"
            headline = "预计 \(formatDate(forecast.exhaustionDate, format: "M 月 d 日 HH:mm")) 耗尽"
            detail = "比额度重置早 \(earlyBy())"
            stateColor = NSColor(calibratedRed: 1, green: 0.72, blue: 0.31, alpha: 1)
        case .suitable:
            state = "配速合适"
            headline = "预计重置时剩余 \(forecast.projectedRemainingAtReset ?? 0)%"
            detail = "额度重置：\(formatDate(snapshot?.weeklyResetsAt, format: "M 月 d 日 HH:mm"))"
            stateColor = NSColor(calibratedRed: 0.55, green: 0.83, blue: 0.73, alpha: 1)
        case .slow:
            state = "配速偏慢"
            headline = "预计重置时剩余 \(forecast.projectedRemainingAtReset ?? 0)%"
            detail = "额度重置：\(formatDate(snapshot?.weeklyResetsAt, format: "M 月 d 日 HH:mm"))"
            stateColor = NSColor(calibratedRed: 0.47, green: 0.85, blue: 0.71, alpha: 1)
        case .collecting:
            state = "正在积累数据"
            headline = "稍后将显示本周期预测"
            detail = "额度重置：\(formatDate(snapshot?.weeklyResetsAt, format: "M 月 d 日 HH:mm"))"
            stateColor = NSColor.white.withAlphaComponent(0.72)
        }

        // AppKit's origin is bottom-left: keep the forecast above the chart divider.
        drawText(state, at: NSPoint(x: x, y: 236), size: 18, weight: .semibold, color: stateColor)
        drawText(headline, at: NSPoint(x: x, y: 202), size: 18, weight: .bold, color: .white)
        drawText(detail, at: NSPoint(x: x, y: 174), size: 13, weight: .medium, color: .white.withAlphaComponent(0.68))
    }

    private func drawConsumption(in rect: NSRect) {
        let x = rect.minX + 20
        drawText("本周期消耗", at: NSPoint(x: x, y: 126), size: 14, weight: .semibold, color: .white)
        if let dailyRate = forecast.dailyRate {
            drawText("日均 \(dailyRate)%", at: NSPoint(x: rect.maxX - 20, y: 126), size: 12, weight: .medium, color: .white.withAlphaComponent(0.68), align: .right)
        }
        drawText(
            "\(formatDate(cycleStart, format: "M/d HH:mm"))  →  \(formatDate(snapshot?.weeklyResetsAt, format: "M/d HH:mm"))",
            at: NSPoint(x: x, y: 105),
            size: 10,
            weight: .medium,
            color: .white.withAlphaComponent(0.42)
        )

        guard let reset = snapshot?.weeklyResetsAt else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: cycleStart ?? now)
        let end = calendar.startOfDay(for: reset)
        let dailySamples = history.dailyUsage(resetAt: reset, timeZone: .current)
        let usage = Dictionary(uniqueKeysWithValues: dailySamples.map { ($0.day, $0.usedPercent) })
        let firstObserved = dailySamples.map(\.day).min()
        let days = dates(from: start, through: end, calendar: calendar)
        guard !days.isEmpty else { return }

        let chart = NSRect(x: x, y: 20, width: rect.width - 40, height: 65)
        let columnWidth = chart.width / CGFloat(days.count)
        for (index, day) in days.enumerated() {
            let center = chart.minX + columnWidth * (CGFloat(index) + 0.5)
            let isToday = calendar.isDateInToday(day)
            let isFuture = day > calendar.startOfDay(for: now)
            let value = usage[day]

            drawText(formatDate(day, format: "d"), at: NSPoint(x: center, y: 86), size: 11, weight: .semibold, color: isToday ? .white : .white.withAlphaComponent(isFuture ? 0.34 : 0.78), align: .center)
            drawText(isToday ? "今天" : weekday(for: day, calendar: calendar), at: NSPoint(x: center, y: 71), size: 10, weight: isToday ? .semibold : .medium, color: isToday ? .white : .white.withAlphaComponent(isFuture ? 0.26 : 0.42), align: .center)
            if let value {
                drawText("\(value)%", at: NSPoint(x: center, y: 54), size: 10, weight: .semibold, color: .white.withAlphaComponent(0.88), align: .center)
                let height = max(7, min(34, CGFloat(value) * 3.4))
                let bar = NSRect(x: center - 8, y: chart.minY, width: 16, height: height)
                let barPath = NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4)
                if isToday {
                    NSColor(calibratedRed: 0.54, green: 0.86, blue: 0.77, alpha: 1).setFill()
                } else {
                    NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.68, alpha: 1).setFill()
                }
                barPath.fill()
                if isToday {
                    NSColor.white.withAlphaComponent(0.7).setStroke()
                    barPath.lineWidth = 0.75
                    barPath.stroke()
                }
            } else if isFuture || (firstObserved != nil && day < firstObserved!) {
                NSColor.white.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: NSRect(x: center - 7, y: chart.minY, width: 14, height: 1), xRadius: 1, yRadius: 1).fill()
            }
        }

        if dailySamples.isEmpty {
            let remaining = snapshot?.weeklyRemaining.map { "\($0)%" } ?? "当前"
            drawText(
                "已建立 \(remaining) 基线，下一次额度变化后显示日用量",
                at: NSPoint(x: rect.midX, y: 24),
                size: 10,
                weight: .medium,
                color: .white.withAlphaComponent(0.52),
                align: .center
            )
        }
    }

    private var cycleStart: Date? {
        guard let reset = snapshot?.weeklyResetsAt,
              let duration = snapshot?.weeklyWindowDurationMins else { return nil }
        return reset.addingTimeInterval(-TimeInterval(duration * 60))
    }

    private func earlyBy() -> String {
        guard let reset = snapshot?.weeklyResetsAt, let exhaustion = forecast.exhaustionDate else { return "--" }
        let components = Calendar.current.dateComponents([.day, .hour], from: exhaustion, to: reset)
        if let days = components.day, days > 0 {
            return "\(days) 天 \(components.hour ?? 0) 小时"
        }
        return "\(components.hour ?? 0) 小时"
    }

    private func dates(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var current = start
        while current <= end {
            result.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    private func weekday(for date: Date, calendar: Calendar) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: date) - 1]
    }

    private func formatDate(_ date: Date?, format: String) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func drawDivider(y: CGFloat) {
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 20, y: y))
        line.line(to: NSPoint(x: bounds.width - 20, y: y))
        line.lineWidth = 1
        line.stroke()
    }

    private func drawText(
        _ string: String,
        at point: NSPoint,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        align: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(string: string, attributes: attributes)
        let width = align == .left ? bounds.width - point.x - 16 : 180
        text.draw(in: NSRect(x: align == .right || align == .center ? point.x - width / 2 : point.x, y: point.y, width: width, height: 28))
    }
}
