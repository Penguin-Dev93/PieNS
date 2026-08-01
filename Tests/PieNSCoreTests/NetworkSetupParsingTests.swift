import Testing
@testable import PieNSCore

@Test func parsesAutomaticDNSOutput() {
    let output = "There aren't any DNS Servers set on Wi-Fi.\n"

    #expect(NetworkSetupParsing.parseDNSOutput(output) == .automatic)
}

@Test func parsesManualDNSOutput() {
    let output = "192.168.1.2\n10.0.0.1\n"

    #expect(NetworkSetupParsing.parseDNSOutput(output) == .manual(["192.168.1.2", "10.0.0.1"]))
}

@Test func parsesDefaultRouteInterface() {
    let output = """
       route to: default
    destination: default
           mask: default
        gateway: 192.168.1.1
      interface: en0
    """

    #expect(NetworkSetupParsing.parseDefaultInterface(output) == "en0")
}

@Test func mapsDeviceToNetworkServiceName() {
    let output = """
    An asterisk (*) denotes that a network service is disabled.
    (1) Thunderbolt Bridge
    (Hardware Port: Thunderbolt Bridge, Device: bridge0)

    (2) Wi-Fi
    (Hardware Port: Wi-Fi, Device: en0)
    """

    #expect(NetworkSetupParsing.parseServiceName(forDevice: "en0", serviceOrderOutput: output) == "Wi-Fi")
}
