import Foundation

@objc public protocol PieNSHelperProtocol {
    func currentState(reply: @escaping (NSDictionary) -> Void)
    func setManualDNSServers(_ servers: NSArray, reply: @escaping (NSDictionary) -> Void)
    func setAutomaticDNS(reply: @escaping (NSDictionary) -> Void)
}

public enum HelperResponseKey {
    public static let ok = "ok"
    public static let message = "message"
    public static let service = "service"
    public static let mode = "mode"
    public static let servers = "servers"
}

public enum HelperResponseMode {
    public static let automatic = "automatic"
    public static let manual = "manual"
}
