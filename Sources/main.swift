import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let refreshInterval: TimeInterval = 60
    private static let lowBattery = 20

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = DispatchQueue(label: "battery-meter.refresh")
    private let logitech = LogitechBattery()
    private var timer: Timer?
    private var lastUpdate: Date?

    /// Logitech mice stop answering while asleep; keep showing their last known level (dimmed).
    private var lastSeen: [String: (device: BatteryDevice, fresh: Bool)] = [:]
    private var bluetooth: [BatteryDevice] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "…"
        rebuildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let bt = BluetoothBattery.read()
            let logi = self.logitech.read()
            DispatchQueue.main.async { self.apply(bluetooth: bt, logitech: logi) }
        }
    }

    private func apply(bluetooth bt: [BatteryDevice], logitech logi: [BatteryDevice]) {
        bluetooth = bt
        for key in lastSeen.keys { lastSeen[key]?.fresh = false }
        for device in logi { lastSeen[device.id] = (device, true) }
        lastUpdate = Date()
        updateTitle()
        rebuildMenu()
    }

    private var entries: [(device: BatteryDevice, fresh: Bool)] {
        let all = bluetooth.map { ($0, true) } + lastSeen.values.map { ($0.device, $0.fresh) }
        return all.sorted { order($0.0.kind) < order($1.0.kind) }
    }

    private func order(_ kind: DeviceKind) -> Int {
        switch kind {
        case .headphones: return 0
        case .mouse: return 1
        case .keyboard: return 2
        case .other: return 3
        }
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let font = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString()
        for (i, entry) in entries.enumerated() {
            let color = color(for: entry.device, fresh: entry.fresh)
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            title.append(symbol(entry.device.kind.symbolName, font: font, color: color))
            if entry.device.charging { title.append(symbol("bolt.fill", font: font, color: color, scale: .small)) }
            title.append(NSAttributedString(string: " \(entry.device.percent)%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
                .foregroundColor: color,
                .baselineOffset: 0,
            ]))
        }
        if title.length == 0 { title.append(symbol("battery.0percent", font: font, color: .secondaryLabelColor)) }
        button.attributedTitle = title
    }

    private func color(for device: BatteryDevice, fresh: Bool) -> NSColor {
        if device.percent <= Self.lowBattery && !device.charging { return .systemRed }
        return fresh ? .labelColor : .secondaryLabelColor
    }

    private func symbol(_ name: String, font: NSFont, color: NSColor, scale: NSImage.SymbolScale = .medium) -> NSAttributedString {
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular, scale: scale)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSAttributedString() }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - image.size.height) / 2,
                                   width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        if entries.isEmpty {
            menu.addItem(withTitle: "No devices with battery info", action: nil, keyEquivalent: "")
        }
        for entry in entries {
            var text = "\(entry.device.name) — \(entry.device.percent)%"
            if entry.device.charging { text += " (charging)" }
            if !entry.fresh { text += " (asleep, last known)" }
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: entry.device.kind.symbolName, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if let lastUpdate {
            let f = DateFormatter()
            f.timeStyle = .short
            menu.addItem(withTitle: "Updated \(f.string(from: lastUpdate))", action: nil, keyEquivalent: "")
        }
        menu.addItem(withTitle: "Refresh now", action: #selector(refresh), keyEquivalent: "r").target = self
        let login = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
