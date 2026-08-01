import AppKit
import Foundation
import PieNSCore

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

    func applicationWillTerminate(_ notification: Notification) {
        PieNSLog.write("applicationWillTerminate")
        helperClient.reset()
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
        statusItem.length = 32
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
                    Task { @MainActor in
                        self.handleMutation(result)
                    }
                }
            } else {
                guard let servers = self.configuredServers(promptIfMissing: true) else {
                    PieNSLog.write("toggle stopped because no DNS servers are configured")
                    return
                }

                PieNSLog.write("setting manual DNS: \(servers.joined(separator: ","))")
                self.helperClient.setManual(servers) { result in
                    Task { @MainActor in
                        self.handleMutation(result)
                    }
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

    private func ensureHelperEnabled(completion: @escaping (Bool) -> Void) {
        completion(true)
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

struct HelperResult: Sendable {
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

final class HelperClient: @unchecked Sendable {
    private let controller = LocalDNSController()

    func reset() {
        controller.reset()
    }

    func currentState(completion: @escaping @Sendable (HelperResult) -> Void) {
        controller.currentState(completion: completion)
    }

    func setManual(_ servers: [String], completion: @escaping @Sendable (HelperResult) -> Void) {
        controller.setManual(servers, completion: completion)
    }

    func setAutomatic(completion: @escaping @Sendable (HelperResult) -> Void) {
        controller.setAutomatic(completion: completion)
    }
}

enum LocalDNSError: LocalizedError {
    case noDefaultInterface
    case noNetworkService(String)
    case commandFailed(String)
    case invalidServers

    var errorDescription: String? {
        switch self {
        case .noDefaultInterface:
            return "Could not find the active default network interface."
        case .noNetworkService(let device):
            return "Could not find a network service for device \(device)."
        case .commandFailed(let message):
            return message
        case .invalidServers:
            return "The requested DNS servers were invalid."
        }
    }
}

struct CommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

struct CommandRunner {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            status: process.terminationStatus
        )
    }
}

final class LocalDNSController: @unchecked Sendable {
    private let runner = CommandRunner()
    private let queue = DispatchQueue(label: "PieNS.LocalDNSController", qos: .userInitiated)

    func reset() {}

    func currentState(completion: @escaping @Sendable (HelperResult) -> Void) {
        queue.async {
            completion(self.response { try self.currentStateDictionary() })
        }
    }

    func setManual(_ servers: [String], completion: @escaping @Sendable (HelperResult) -> Void) {
        queue.async {
            completion(self.response { try self.setManualDictionary(servers) })
        }
    }

    func setAutomatic(completion: @escaping @Sendable (HelperResult) -> Void) {
        queue.async {
            completion(self.response { try self.setAutomaticDictionary() })
        }
    }

    private func currentStateDictionary() throws -> [String: Any] {
        let service = try activeServiceName()
        let output = try networksetup(["-getdnsservers", service]).stdout
        let mode = NetworkSetupParsing.parseDNSOutput(output)

        switch mode {
        case .automatic:
            return [
                HelperResponseKey.ok: true,
                HelperResponseKey.service: service,
                HelperResponseKey.mode: HelperResponseMode.automatic
            ]
        case .manual(let servers):
            return [
                HelperResponseKey.ok: true,
                HelperResponseKey.service: service,
                HelperResponseKey.mode: HelperResponseMode.manual,
                HelperResponseKey.servers: servers
            ]
        }
    }

    private func setManualDictionary(_ servers: [String]) throws -> [String: Any] {
        guard !servers.isEmpty, servers.allSatisfy(DNSValidation.isIPAddress) else {
            throw LocalDNSError.invalidServers
        }

        let service = try activeServiceName()
        try privilegedNetworksetup(["-setdnsservers", service] + servers)

        return [
            HelperResponseKey.ok: true,
            HelperResponseKey.service: service,
            HelperResponseKey.mode: HelperResponseMode.manual,
            HelperResponseKey.servers: servers
        ]
    }

    private func setAutomaticDictionary() throws -> [String: Any] {
        let service = try activeServiceName()
        try privilegedNetworksetup(["-setdnsservers", service, "empty"])

        return [
            HelperResponseKey.ok: true,
            HelperResponseKey.service: service,
            HelperResponseKey.mode: HelperResponseMode.automatic
        ]
    }

    private func activeServiceName() throws -> String {
        let route = try runner.run("/sbin/route", ["-n", "get", "default"])
        guard route.status == 0 else {
            throw LocalDNSError.commandFailed(route.stderrOrStdout)
        }

        guard let device = NetworkSetupParsing.parseDefaultInterface(route.stdout) else {
            throw LocalDNSError.noDefaultInterface
        }

        let services = try networksetup(["-listnetworkserviceorder"]).stdout
        if let service = NetworkSetupParsing.parseServiceName(forDevice: device, serviceOrderOutput: services) {
            return service
        }

        guard let service = NetworkSetupParsing.preferredFallbackServiceName(serviceOrderOutput: services) else {
            throw LocalDNSError.noNetworkService(device)
        }

        return service
    }

    private func networksetup(_ arguments: [String]) throws -> CommandResult {
        let result = try runner.run("/usr/sbin/networksetup", arguments)
        guard result.status == 0 else {
            throw LocalDNSError.commandFailed(result.stderrOrStdout)
        }

        return result
    }

    private func privilegedNetworksetup(_ arguments: [String]) throws {
        let command = ([ "/usr/sbin/networksetup" ] + arguments)
            .map(shellQuote)
            .joined(separator: " ")
        let script = "do shell script \"\(appleScriptQuote(command))\" with administrator privileges"
        let result = try runner.run("/usr/bin/osascript", ["-e", script])

        guard result.status == 0 else {
            throw LocalDNSError.commandFailed(result.stderrOrStdout)
        }
    }

    private func response(_ operation: () throws -> [String: Any]) -> HelperResult {
        do {
            return HelperResult(dictionary: try operation() as NSDictionary)
        } catch {
            return HelperResult(dictionary: [
                HelperResponseKey.ok: false,
                HelperResponseKey.message: error.localizedDescription
            ])
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension CommandResult {
    var stderrOrStdout: String {
        let stderrText = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrText.isEmpty {
            return stderrText
        }

        let stdoutText = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdoutText.isEmpty ? "Command failed with exit status \(status)." : stdoutText
    }
}

enum PieNSLog {
    static func write(_ message: String) {
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
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
        let resourceName = isManual ? "TrayIconOn" : "TrayIconOff"
        let size = isManual ? NSSize(width: 25, height: 22) : NSSize(width: 28, height: 18)

        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = size
            image.isTemplate = false
            return image
        }

        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.white.setStroke()
        let fallback = NSBezierPath(ovalIn: NSRect(x: 4, y: 6, width: 17, height: 8))
        fallback.lineWidth = 1.2
        fallback.stroke()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
