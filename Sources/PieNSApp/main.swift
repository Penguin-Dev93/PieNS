import AppKit
import Foundation
import PieNSCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let defaults = UserDefaults.standard
    private lazy var helperClient = HelperClient()
    private var isManual = false
    private var activeService = "Unknown"

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleDNS()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let state = NSMenuItem(title: "\(activeService): \(isManual ? "Manual DNS" : "Automatic DNS")", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)

        menu.addItem(NSMenuItem.separator())
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

    private func toggleDNS() {
        ensureHelperEnabled { [weak self] enabled in
            guard let self, enabled else {
                return
            }

            if self.isManual {
                self.helperClient.setAutomatic { result in
                    self.handleMutation(result)
                }
            } else {
                guard let servers = self.configuredServers(promptIfMissing: true) else {
                    return
                }

                self.helperClient.setManual(servers) { result in
                    self.handleMutation(result)
                }
            }
        }
    }

    private func handleMutation(_ result: HelperResult) {
        DispatchQueue.main.async {
            if result.ok {
                self.apply(result)
            } else {
                self.showAlert(title: "PieNS could not change DNS", message: result.message)
            }
        }
    }

    private func refreshState() {
        helperClient.currentState { result in
            DispatchQueue.main.async {
                guard result.ok else {
                    self.statusItem.button?.image = PieIcon.make(isManual: false)
                    self.statusItem.button?.toolTip = "PieNS: helper unavailable"
                    return
                }

                self.apply(result)
            }
        }
    }

    private func apply(_ result: HelperResult) {
        activeService = result.service ?? "Unknown"
        isManual = result.mode == HelperResponseMode.manual
        statusItem.button?.image = PieIcon.make(isManual: isManual)
        statusItem.button?.toolTip = "PieNS: \(activeService) is \(isManual ? "manual" : "automatic")"
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

enum PieIcon {
    static func make(isManual: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let strokeColor = isManual ? NSColor.systemGreen : NSColor.labelColor
        strokeColor.setStroke()

        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: x * size.width, y: y * size.height)
        }

        let center = point(0.50, 0.50)
        let outerRadius: CGFloat = 6.5
        let innerRadius: CGFloat = 4.35
        let startAngle: CGFloat = 18
        let endAngle: CGFloat = 77

        let crust = NSBezierPath()
        crust.lineWidth = 1.75
        crust.lineCapStyle = .round
        crust.lineJoinStyle = .round
        crust.appendArc(withCenter: center, radius: outerRadius, startAngle: endAngle, endAngle: startAngle + 360)
        crust.stroke()

        let cut = NSBezierPath()
        cut.lineWidth = 1.1
        cut.lineCapStyle = .round
        cut.move(to: center)
        cut.line(to: point(0.84, 0.61))
        cut.move(to: center)
        cut.line(to: point(0.57, 0.86))
        cut.stroke()

        let filling = NSBezierPath()
        filling.lineWidth = 0.9
        filling.lineCapStyle = .round
        filling.appendArc(withCenter: center, radius: innerRadius, startAngle: endAngle + 8, endAngle: startAngle + 352)
        filling.stroke()

        let lattice = NSBezierPath()
        lattice.lineWidth = 0.75
        lattice.lineCapStyle = .round
        lattice.move(to: point(0.30, 0.42))
        lattice.line(to: point(0.48, 0.62))
        lattice.move(to: point(0.35, 0.63))
        lattice.line(to: point(0.58, 0.38))
        lattice.stroke()

        image.unlockFocus()
        image.isTemplate = !isManual
        return image
    }
}
