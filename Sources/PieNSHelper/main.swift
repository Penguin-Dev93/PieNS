import Foundation
import PieNSCore

enum HelperLog {
    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        let url = URL(fileURLWithPath: "/Library/Logs/PieNSHelper.log")

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Helper logging is best effort only.
        }
    }
}

enum HelperError: LocalizedError {
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

final class DNSController {
    private let runner = CommandRunner()

    func currentState() throws -> [String: Any] {
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

    func setManual(_ servers: [String]) throws -> [String: Any] {
        guard !servers.isEmpty, servers.allSatisfy(DNSValidation.isIPAddress) else {
            throw HelperError.invalidServers
        }

        let service = try activeServiceName()
        _ = try networksetup(["-setdnsservers", service] + servers)

        return [
            HelperResponseKey.ok: true,
            HelperResponseKey.service: service,
            HelperResponseKey.mode: HelperResponseMode.manual,
            HelperResponseKey.servers: servers
        ]
    }

    func setAutomatic() throws -> [String: Any] {
        let service = try activeServiceName()
        _ = try networksetup(["-setdnsservers", service, "empty"])

        return [
            HelperResponseKey.ok: true,
            HelperResponseKey.service: service,
            HelperResponseKey.mode: HelperResponseMode.automatic
        ]
    }

    private func activeServiceName() throws -> String {
        let route = try runner.run("/sbin/route", ["-n", "get", "default"])
        guard route.status == 0 else {
            throw HelperError.commandFailed(route.stderrOrStdout)
        }

        guard let device = NetworkSetupParsing.parseDefaultInterface(route.stdout) else {
            throw HelperError.noDefaultInterface
        }

        let services = try networksetup(["-listnetworkserviceorder"]).stdout
        if let service = NetworkSetupParsing.parseServiceName(forDevice: device, serviceOrderOutput: services) {
            return service
        }

        guard let service = NetworkSetupParsing.preferredFallbackServiceName(serviceOrderOutput: services) else {
            throw HelperError.noNetworkService(device)
        }

        return service
    }

    private func networksetup(_ arguments: [String]) throws -> CommandResult {
        let result = try runner.run("/usr/sbin/networksetup", arguments)
        guard result.status == 0 else {
            throw HelperError.commandFailed(result.stderrOrStdout)
        }

        return result
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

final class HelperService: NSObject, PieNSHelperProtocol {
    private let controller = DNSController()

    func currentState(reply: @escaping (NSDictionary) -> Void) {
        reply(response { try controller.currentState() })
    }

    func setManualDNSServers(_ servers: NSArray, reply: @escaping (NSDictionary) -> Void) {
        reply(response {
            let values = servers.compactMap { $0 as? String }
            return try controller.setManual(values)
        })
    }

    func setAutomaticDNS(reply: @escaping (NSDictionary) -> Void) {
        reply(response { try controller.setAutomatic() })
    }

    private func response(_ operation: () throws -> [String: Any]) -> NSDictionary {
        do {
            return try operation() as NSDictionary
        } catch {
            return [
                HelperResponseKey.ok: false,
                HelperResponseKey.message: error.localizedDescription
            ] as NSDictionary
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        HelperLog.write("connection accepted")
        connection.exportedInterface = NSXPCInterface(with: PieNSHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: PieNSConstants.helperMachServiceName)
listener.delegate = delegate
HelperLog.write("helper starting")
listener.resume()
Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
    HelperLog.write("idle exit")
    exit(0)
}
RunLoop.main.run()
