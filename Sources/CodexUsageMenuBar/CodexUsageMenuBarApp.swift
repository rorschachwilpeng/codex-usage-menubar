import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let retainedDelegate = AppDelegate()
    private var controller: MenuBarController?

    static func main() {
        let app = NSApplication.shared
        app.delegate = retainedDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController()
    }
}

@MainActor
final class MenuBarController: NSObject, ObservableObject {
    @Published private(set) var title = "Usage --"
    @Published private(set) var weeklyReset = "--"
    @Published private(set) var statusText = "Loading…"

    private var client: AppServerClient?
    private var store: UsageStore?
    private var refreshTask: Task<Void, Never>?
    private var powerObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem!
    private var weeklyResetItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var overlayPanels: [NSPanel] = []
    private var overlayViews: [WeeklyStatusPillView] = []
    private var forecastPanels: [NSPanel] = []
    private var forecastViews: [ForecastPopoverView] = []
    private var closePopoverTask: Task<Void, Never>?

    override init() {
        super.init()
        configureMenuBar()
        do {
            let client = try AppServerClient()
            self.client = client
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            store = UsageStore(
                reader: client,
                cacheURL: support.appendingPathComponent("CodexUsageMenuBar/last-usage.json"),
                historyURL: support.appendingPathComponent("CodexUsageMenuBar/weekly-usage-history.json")
            )
            updatePresentation()
            observePowerEvents()
            observeScreenChanges()
            startRefreshLoop()
        } catch {
            statusText = error.localizedDescription
        }
    }

    @objc func refreshNow() {
        Task { [weak self] in
            guard let self, let store = self.store else { return }
            await store.refresh()
            self.updatePresentation()
        }
    }

    @objc func quit() {
        refreshTask?.cancel()
        Task { [weak self] in
            if let client = self?.client { await client.shutdown() }
            NSApp.terminate(nil)
        }
    }

    private func startRefreshLoop() {
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let store = self.store else { return }
                await store.refresh()
                self.updatePresentation()
                let delay = store.isSleeping ? 5 : store.nextRefreshDelay
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func observePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        powerObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.store?.markSleeping() }
        })
        powerObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in
                controller.store?.markAwake()
                controller.refreshNow()
            }
        })
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.configureOverlay() }
        }
    }

    private func updatePresentation() {
        guard let store else { return }
        title = store.title
        weeklyReset = formatDate(store.snapshot?.weeklyResetsAt)
        switch store.status {
        case .loading:
            statusText = "Loading…"
        case .fresh:
            statusText = "Updated \(formatTime(store.snapshot?.updatedAt))"
        case let .stale(message):
            statusText = "Stale data: \(message)"
        case .loginRequired:
            statusText = "Sign in to Codex first"
        }
        let pillPresentation = WeeklyPillPresentation(snapshot: store.snapshot)
        let forecast = WeeklyUsageForecast(snapshot: store.snapshot)
        setStatusTitle(pillPresentation.menuBarText)
        overlayViews.forEach {
            $0.presentation = pillPresentation
            $0.showsRisk = forecast.pace == .fast
        }
        forecastViews.forEach { $0.update(snapshot: store.snapshot, history: store.history, now: Date()) }
        weeklyResetItem.title = "Weekly limit resets: \(weeklyReset)"
        updateItem.title = statusText
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.button?.title = ""
        configureOverlay()

        let menu = NSMenu()
        weeklyResetItem = infoItem("Weekly limit resets: --")
        updateItem = infoItem("Loading…")
        menu.addItem(weeklyResetItem)
        menu.addItem(updateItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func setStatusTitle(_ title: String) {
        let attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .kern: 0.05
            ]
        )
        statusItem.button?.attributedTitle = attributedTitle
        statusItem.button?.setAccessibilityLabel(title)
    }

    private func configureOverlay() {
        overlayPanels.forEach { $0.close() }
        forecastPanels.forEach { $0.close() }
        overlayPanels.removeAll()
        overlayViews.removeAll()
        forecastPanels.removeAll()
        forecastViews.removeAll()

        let size = NSSize(width: 154, height: 24)
        for screen in NSScreen.screens {
            guard let leftArea = screen.auxiliaryTopLeftArea else { continue }
            let origin: NSPoint
            origin = NSPoint(
                x: max(leftArea.minX + 8, leftArea.maxX - size.width - 40),
                y: leftArea.midY - size.height / 2
            )
            let panel = NSPanel(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let view = WeeklyStatusPillView(frame: NSRect(origin: .zero, size: size))
            panel.contentView = view

            let forecastPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 286)),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            forecastPanel.level = .screenSaver
            forecastPanel.isOpaque = false
            forecastPanel.backgroundColor = .clear
            forecastPanel.hasShadow = false
            forecastPanel.hidesOnDeactivate = false
            forecastPanel.isReleasedWhenClosed = false
            forecastPanel.ignoresMouseEvents = false
            forecastPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let forecastView = ForecastPopoverView(frame: NSRect(origin: .zero, size: forecastPanel.frame.size))
            forecastPanel.contentView = forecastView

            view.onHoverChanged = { [weak self, weak panel, weak forecastPanel] hovering in
                self?.setForecastVisibility(hovering, anchor: panel, panel: forecastPanel)
            }
            forecastView.onHoverChanged = { [weak self, weak panel, weak forecastPanel] hovering in
                self?.setForecastVisibility(hovering, anchor: panel, panel: forecastPanel)
            }
            panel.orderFrontRegardless()
            overlayPanels.append(panel)
            overlayViews.append(view)
            forecastPanels.append(forecastPanel)
            forecastViews.append(forecastView)
        }
        statusItem.isVisible = overlayPanels.isEmpty
    }

    private func setForecastVisibility(_ visible: Bool, anchor: NSPanel?, panel: NSPanel?) {
        closePopoverTask?.cancel()
        guard let anchor, let panel else { return }
        if visible {
            positionForecastPanel(panel, below: anchor)
            panel.orderFrontRegardless()
            return
        }
        closePopoverTask = Task { [weak panel] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { panel?.orderOut(nil) }
        }
    }

    private func positionForecastPanel(_ panel: NSPanel, below anchor: NSPanel) {
        guard let screen = anchor.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let x = min(max(anchor.frame.midX - 78, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        let y = max(visibleFrame.minY + 8, anchor.frame.minY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

final class StatusPillView: NSView {
    var presentation = UsagePillPresentation(snapshot: nil) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.32).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        drawGroup(
            emoji: "⏰",
            percent: presentation.primaryPercent,
            reset: presentation.primaryReset,
            urgent: presentation.primaryIsUrgent,
            in: NSRect(x: 5, y: 0, width: 75, height: bounds.height)
        )
        drawGate()
        drawGroup(
            emoji: "📅",
            percent: presentation.secondaryPercent,
            reset: presentation.secondaryReset,
            urgent: presentation.secondaryIsUrgent,
            in: NSRect(x: 95, y: 0, width: 70, height: bounds.height)
        )
    }

    private func drawGroup(emoji: String, percent: String, reset: String, urgent: Bool, in rect: NSRect) {
        let emojiText = NSAttributedString(
            string: emoji,
            attributes: [.font: NSFont.systemFont(ofSize: 10)]
        )
        let percentText = NSAttributedString(
            string: percent,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            ]
        )
        let resetText = NSAttributedString(
            string: reset,
            attributes: [
                .foregroundColor: urgent
                    ? NSColor(calibratedRed: 1, green: 0.68, blue: 0.25, alpha: 1)
                    : NSColor.white.withAlphaComponent(0.76),
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            ]
        )
        let parts = [emojiText, percentText, resetText]
        let gaps: [CGFloat] = [5, 7]
        let width = parts.reduce(CGFloat.zero) { $0 + $1.size().width } + gaps.reduce(0, +)
        var x = rect.midX - width / 2

        for (index, part) in parts.enumerated() {
            let size = part.size()
            part.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
            x += size.width
            if index < gaps.count { x += gaps[index] }
        }
    }

    private func drawGate() {
        let top = bounds.midY + 8.5
        let bottom = bounds.midY - 8.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 84, y: bottom))
        path.line(to: NSPoint(x: 84, y: top))
        NSColor.white.withAlphaComponent(0.76).setStroke()
        path.lineWidth = 1
        path.stroke()

        let secondaryPath = NSBezierPath()
        secondaryPath.move(to: NSPoint(x: 90, y: bottom))
        secondaryPath.line(to: NSPoint(x: 90, y: top))
        NSColor.white.withAlphaComponent(0.32).setStroke()
        secondaryPath.lineWidth = 1
        secondaryPath.stroke()
    }
}
