import Foundation

@objc(DNSChangerHelperProtocol)
protocol DNSChangerHelperProtocol {
    func applyDNS(_ servers: [String], withReply reply: @escaping (Bool, String) -> Void)
    func clearDNS(withReply reply: @escaping (Bool, String) -> Void)
    func flushDNSCache(withReply reply: @escaping (Bool, String) -> Void)
}

@objc(DNSChangerHelperBlessProtocol)
protocol DNSChangerHelperBlessProtocol {
    func isHelperReady(withReply reply: @escaping (Bool) -> Void)
}

@objc(DNSChangerHelperXPCProtocol)
protocol DNSChangerHelperXPCProtocol: DNSChangerHelperProtocol, DNSChangerHelperBlessProtocol {}
