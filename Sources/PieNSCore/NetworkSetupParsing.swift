import Foundation

public enum DNSMode: Equatable {
    case automatic
    case manual([String])
}

public enum NetworkSetupParsing {
    public static func parseDNSOutput(_ output: String) -> DNSMode {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains("There aren't any DNS Servers") {
            return .automatic
        }

        let servers = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return servers.isEmpty ? .automatic : .manual(servers)
    }

    public static func parseDefaultInterface(_ routeOutput: String) -> String? {
        for line in routeOutput.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if parts.count == 2 && parts[0] == "interface" && !parts[1].isEmpty {
                return parts[1]
            }
        }

        return nil
    }

    public static func parseServiceName(forDevice device: String, serviceOrderOutput: String) -> String? {
        let lines = serviceOrderOutput.components(separatedBy: .newlines)
        var currentService: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("Device: \(device)") {
                return currentService
            }

            if trimmed.hasPrefix("("), let close = trimmed.firstIndex(of: ")") {
                let numberStart = trimmed.index(after: trimmed.startIndex)
                let marker = trimmed[numberStart..<close]
                if marker.allSatisfy(\.isNumber) {
                    let afterIndex = trimmed.index(after: close)
                    currentService = String(trimmed[afterIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continue
            }
        }

        return nil
    }

    public static func parseOrderedServiceNames(_ serviceOrderOutput: String) -> [String] {
        serviceOrderOutput
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("("), let close = trimmed.firstIndex(of: ")") else {
                    return nil
                }

                let numberStart = trimmed.index(after: trimmed.startIndex)
                let marker = trimmed[numberStart..<close]
                guard marker.allSatisfy(\.isNumber) else {
                    return nil
                }

                let afterIndex = trimmed.index(after: close)
                let service = String(trimmed[afterIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return service.isEmpty || service.hasPrefix("*") ? nil : service
            }
    }

    public static func preferredFallbackServiceName(serviceOrderOutput: String) -> String? {
        let services = parseOrderedServiceNames(serviceOrderOutput)
        if let wifi = services.first(where: { $0.localizedCaseInsensitiveContains("wi-fi") || $0.localizedCaseInsensitiveContains("wifi") }) {
            return wifi
        }

        return services.first
    }
}
