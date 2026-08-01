import Testing
@testable import PieNSCore

@Test func parsesCommaAndWhitespaceSeparatedServers() throws {
    let servers = try DNSValidation.parseServers("192.168.1.2, 10.0.0.1\n2606:4700:4700::1111")

    #expect(servers == ["192.168.1.2", "10.0.0.1", "2606:4700:4700::1111"])
}

@Test func rejectsInvalidServers() {
    #expect(throws: DNSValidationError.invalid("pihole.local")) {
        try DNSValidation.parseServers("192.168.1.2 pihole.local")
    }
}

@Test func rejectsEmptyServers() {
    #expect(throws: DNSValidationError.empty) {
        try DNSValidation.parseServers("   ")
    }
}
