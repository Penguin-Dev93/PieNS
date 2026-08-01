import Foundation
import Darwin

public enum DNSValidationError: LocalizedError, Equatable {
    case empty
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter at least one DNS server."
        case .invalid(let value):
            return "'\(value)' is not a valid IPv4 or IPv6 address."
        }
    }
}

public enum DNSValidation {
    public static func parseServers(_ rawValue: String) throws -> [String] {
        let servers = rawValue
            .split { character in
                character == "," || character == "\n" || character == "\t" || character == " "
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !servers.isEmpty else {
            throw DNSValidationError.empty
        }

        for server in servers where !isIPAddress(server) {
            throw DNSValidationError.invalid(server)
        }

        return servers
    }

    public static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }

        var ipv6 = in6_addr()
        if value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            return true
        }

        return false
    }
}
