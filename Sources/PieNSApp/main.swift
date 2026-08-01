import AppKit
import Foundation
import PieNSCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaults = UserDefaults.standard
    private lazy var helperClient = HelperClient()
    private var isManual = false
    private var activeService = "Unknown"

    func applicationDidFinishLaunching(_ notification: Notification) {
        PieNSLog.write("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshState()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = PieIcon.make(isManual: false)
        button.toolTip = "PieNS"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.length = 26
        PieNSLog.write("status item configured")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            PieNSLog.write("right click")
            showMenu()
        } else {
            PieNSLog.write("left click")
            toggleDNS()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let state = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: isManual ? "Turn Automatic DNS On" : "Turn Manual DNS On", action: #selector(toggleDNSAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Configure DNS Servers...", action: #selector(configureDNSServers), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Enable Helper", action: #selector(enableHelper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Status", action: #selector(refreshStateAction), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit PieNS", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleDNSAction() {
        toggleDNS()
    }

    private func toggleDNS() {
        PieNSLog.write("toggle requested while \(isManual ? "manual" : "automatic")")
        ensureHelperEnabled { [weak self] enabled in
            guard let self, enabled else {
                PieNSLog.write("toggle stopped because helper is not enabled")
                return
            }

            if self.isManual {
                PieNSLog.write("setting automatic DNS")
                self.helperClient.setAutomatic { result in
                    self.handleMutation(result)
                }
            } else {
                guard let servers = self.configuredServers(promptIfMissing: true) else {
                    PieNSLog.write("toggle stopped because no DNS servers are configured")
                    return
                }

                PieNSLog.write("setting manual DNS: \(servers.joined(separator: ","))")
                self.helperClient.setManual(servers) { result in
                    self.handleMutation(result)
                }
            }
        }
    }

    private func handleMutation(_ result: HelperResult) {
        DispatchQueue.main.async {
            if result.ok {
                PieNSLog.write("toggle succeeded: \(result.mode ?? "unknown") on \(result.service ?? "unknown")")
                self.apply(result)
            } else {
                PieNSLog.write("toggle failed: \(result.message)")
                self.showAlert(title: "PieNS could not change DNS", message: result.message)
            }
        }
    }

    private func refreshState() {
        helperClient.currentState { result in
            DispatchQueue.main.async {
                guard result.ok else {
                    PieNSLog.write("helper unavailable: \(result.message)")
                    self.statusItem.button?.image = PieIcon.make(isManual: false)
                    self.statusItem.button?.toolTip = "PieNS: helper unavailable"
                    return
                }

                PieNSLog.write("state refresh: \(result.mode ?? "unknown") on \(result.service ?? "unknown")")
                self.apply(result)
            }
        }
    }

    private func apply(_ result: HelperResult) {
        activeService = result.service ?? "Unknown"
        isManual = result.mode == HelperResponseMode.manual
        statusItem.button?.image = PieIcon.make(isManual: isManual)
        statusItem.button?.toolTip = statusTitle
    }

    private var statusTitle: String {
        isManual ? "PieNS ON: Manual DNS (\(activeService))" : "PieNS OFF: Automatic DNS (\(activeService))"
    }

    @objc private func configureDNSServers() {
        let current = configuredServers(promptIfMissing: false)?.joined(separator: ", ") ?? ""
        let alert = NSAlert()
        alert.messageText = "Configure DNS Servers"
        alert.informativeText = "Enter one or more DNS server IP addresses separated by commas or spaces."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = current
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            let servers = try DNSValidation.parseServers(input.stringValue)
            defaults.set(servers, forKey: PieNSConstants.dnsServersDefaultsKey)
            PieNSLog.write("configured DNS servers: \(servers.joined(separator: ","))")
        } catch {
            showAlert(title: "Invalid DNS Servers", message: error.localizedDescription)
        }
    }

    private func configuredServers(promptIfMissing: Bool) -> [String]? {
        if let servers = defaults.stringArray(forKey: PieNSConstants.dnsServersDefaultsKey), !servers.isEmpty {
            return servers
        }

        if promptIfMissing {
            configureDNSServers()
            return defaults.stringArray(forKey: PieNSConstants.dnsServersDefaultsKey)
        }

        return nil
    }

    @objc private func enableHelper() {
        ensureHelperEnabled { _ in }
    }

    private func ensureHelperEnabled(completion: @escaping (Bool) -> Void) {
        let service = SMAppService.daemon(plistName: PieNSConstants.helperPlistName)

        switch service.status {
        case .enabled:
            completion(true)
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            showAlert(
                title: "Enable PieNS Helper",
                message: "PieNS needs its helper enabled in System Settings before it can change DNS."
            )
            completion(false)
        default:
            do {
                try service.register()
                if service.status == .enabled {
                    completion(true)
                } else {
                    SMAppService.openSystemSettingsLoginItems()
                    showAlert(
                        title: "Approve PieNS Helper",
                        message: "Approve the PieNS helper in System Settings, then try the toggle again."
                    )
                    completion(false)
                }
            } catch {
                showAlert(title: "Could not enable helper", message: error.localizedDescription)
                completion(false)
            }
        }
    }

    @objc private func refreshStateAction() {
        refreshState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

struct HelperResult {
    let ok: Bool
    let message: String
    let service: String?
    let mode: String?
    let servers: [String]

    init(dictionary: NSDictionary) {
        ok = dictionary[HelperResponseKey.ok] as? Bool ?? false
        message = dictionary[HelperResponseKey.message] as? String ?? "Unknown helper error."
        service = dictionary[HelperResponseKey.service] as? String
        mode = dictionary[HelperResponseKey.mode] as? String
        servers = dictionary[HelperResponseKey.servers] as? [String] ?? []
    }
}

final class HelperClient {
    private var connection: NSXPCConnection?

    func currentState(completion: @escaping (HelperResult) -> Void) {
        proxy { helper in
            helper.currentState { completion(HelperResult(dictionary: $0)) }
        } onError: {
            completion($0)
        }
    }

    func setManual(_ servers: [String], completion: @escaping (HelperResult) -> Void) {
        proxy { helper in
            helper.setManualDNSServers(servers as NSArray) { completion(HelperResult(dictionary: $0)) }
        } onError: {
            completion($0)
        }
    }

    func setAutomatic(completion: @escaping (HelperResult) -> Void) {
        proxy { helper in
            helper.setAutomaticDNS { completion(HelperResult(dictionary: $0)) }
        } onError: {
            completion($0)
        }
    }

    private func proxy(_ body: @escaping (PieNSHelperProtocol) -> Void, onError: @escaping (HelperResult) -> Void) {
        let connection = self.connection ?? makeConnection()
        self.connection = connection

        let remote = connection.remoteObjectProxyWithErrorHandler { error in
            self.connection?.invalidate()
            self.connection = nil
            onError(HelperResult(dictionary: [
                HelperResponseKey.ok: false,
                HelperResponseKey.message: error.localizedDescription
            ]))
        } as? PieNSHelperProtocol

        guard let remote else {
            onError(HelperResult(dictionary: [
                HelperResponseKey.ok: false,
                HelperResponseKey.message: "Could not connect to the PieNS helper."
            ]))
            return
        }

        body(remote)
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: PieNSConstants.helperMachServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PieNSHelperProtocol.self)
        connection.resume()
        return connection
    }
}

enum PieNSLog {
    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        let logURL = logsDirectory.appendingPathComponent("PieNS.log")

        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Logging must never prevent the menu-bar app from launching.
        }
    }
}

enum PieIcon {
    static func make(isManual: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        if isManual {
            let badge = NSBezierPath(roundedRect: NSRect(x: 2, y: 1.5, width: 20, height: 15), xRadius: 7.5, yRadius: 7.5)
            NSColor.systemGreen.setFill()
            badge.fill()
        }

        let strokeColor = isManual ? NSColor.black : NSColor.labelColor.withAlphaComponent(0.58)
        strokeColor.setStroke()

        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: x * size.width, y: y * size.height)
        }

        let center = point(0.50, 0.50)
        let outerRadius: CGFloat = 6.0
        let innerRadius: CGFloat = 4.0
        let startAngle: CGFloat = 18
        let endAngle: CGFloat = 77

        let crust = NSBezierPath()
        crust.lineWidth = isManual ? 1.85 : 1.75
        crust.lineCapStyle = .round
        crust.lineJoinStyle = .round
        crust.appendArc(withCenter: center, radius: outerRadius, startAngle: endAngle, endAngle: startAngle + 360)
        crust.stroke()

        let cut = NSBezierPath()
        cut.lineWidth = isManual ? 1.2 : 1.1
        cut.lineCapStyle = .round
        cut.move(to: center)
        cut.line(to: point(0.73, 0.60))
        cut.move(to: center)
        cut.line(to: point(0.55, 0.82))
        cut.stroke()

        let filling = NSBezierPath()
        filling.lineWidth = isManual ? 0.9 : 0.8
        filling.lineCapStyle = .round
        filling.appendArc(withCenter: center, radius: innerRadius, startAngle: endAngle + 8, endAngle: startAngle + 352)
        filling.stroke()

        let lattice = NSBezierPath()
        lattice.lineWidth = isManual ? 0.85 : 0.7
        lattice.lineCapStyle = .round
        lattice.move(to: point(0.38, 0.43))
        lattice.line(to: point(0.49, 0.59))
        lattice.move(to: point(0.41, 0.61))
        lattice.line(to: point(0.55, 0.40))
        lattice.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
